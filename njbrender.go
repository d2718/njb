// njbrender.go
//
// Custom markdown renderer for njb.
//
// 2021-02-23
// (updated to stay in line with small chroma API change)
//
package main

import( "fmt"; "io"; "io/ioutil"; "os";
        "github.com/gomarkdown/markdown";
        "github.com/gomarkdown/markdown/ast";
        "github.com/gomarkdown/markdown/html";
        "github.com/gomarkdown/markdown/parser";
        "github.com/alecthomas/chroma";
        "github.com/alecthomas/chroma/lexers";
        "github.com/alecthomas/chroma/styles";
        chtml "github.com/alecthomas/chroma/formatters/html";
)

var fmtr chroma.Formatter
var isSetup bool = false

func setupSyntax() error {
    fmtr = chtml.New(chtml.WithClasses(true), chtml.TabWidth(4))
    if fmtr == nil {
        return fmt.Errorf("Unable to setup output formatter.")
    } else {
        isSetup = true
        return nil
    }
}

func writeCode(w io.Writer, text, codeType string) error {
    if !isSetup {
        err := setupSyntax()
        if err != nil { return err }
    }
    lxr := lexers.Get(codeType)
    if lxr == nil { lxr = lexers.Fallback }
    lxr = chroma.Coalesce(lxr)
    
    stuff, err := lxr.Tokenise(nil, text)
    if err != nil { return err }
    return fmtr.Format(w, styles.Fallback, stuff)
}


func renderHookCodeInfo(w io.Writer, node ast.Node, entering bool) (ast.WalkStatus, bool) {
    // skip if not an ast.CodeBlock
    if n, ok := node.(*ast.CodeBlock); !ok {
        return ast.GoToNext, false
    } else {
        //~ err := quick.Highlight(w, string(n.Literal), string(n.Info),
                              //~ "html", "default")
        err := writeCode(w, string(n.Literal), string(n.Info))
        if err != nil {
            fmt.Fprintf(os.Stderr, "Error parsing code block: %s\n", err)
        }
        return ast.GoToNext, true
    }
}

func main() {
    var input []byte
    var err error
    
    if input, err = ioutil.ReadAll(os.Stdin); err != nil {
        fmt.Fprintf(os.Stderr, "Error reading from stdin: %s\n", err)
        os.Exit(-1)
    }
    
    var extensions = parser.Tables | parser.FencedCode |
                     parser.Strikethrough | parser.SpaceHeadings |
                     parser.HeadingIDs | parser.BackslashLineBreak |
                     parser.DefinitionLists | parser.OrderedListStart |
                     parser.SuperSubscript | parser.MathJax
    var htmlFlags = html.FootnoteReturnLinks | html.Smartypants |
                    html.SmartypantsFractions | html.SmartypantsLatexDashes
    params := html.RendererOptions{
                Flags: htmlFlags,
                RenderNodeHook: renderHookCodeInfo,
              }
    renderer := html.NewRenderer(params)
    
    var output []byte
    parser := parser.NewWithExtensions(extensions)
    output = markdown.ToHTML(input, parser, renderer)
    
    if _, err = os.Stdout.Write(output); err != nil {
        fmt.Fprintf(os.Stderr, "Error writing output: %s\n", err)
        os.Exit(-1)
    }
}
