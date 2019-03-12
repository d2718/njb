# njb
A minimal blogging framework.

`njb` is a minimalist, flyweight,
[New Jersey style](https://en.wikipedia.org/wiki/Worse_is_better)
approach to blogging. The intended user is sufficiently technical to
upload files via FTP or `scp` and run programs from the command line.
`njb` stores post content as markdown files and writes static HTML to
be viewed.

## Installation for System Administrators

Stash the directory `default_templates/` and its contents somewhere.

Stash the contents of the directory `njb_mods/` somewhere. You can put
them where installed Lua packages go, or somewhere else.

Stash `style.css` and `config.template` somewhere.

All good place for all of these might be `/usr/local/share/njb/` or
something similar.

Edit the table in the file `njb_mods/njb_config.lua` to point to where
you put everything in the previous steps. If you have something like
Pandoc installed, you can set the `'markdown_render_cmd'` to use that
instead of `cmark`. (This is especially useful if you lack `cmark`.)

If you stuck the Lua packages in `njb_mods/` somewhere Lua normally
looks for packages, you can set the `NJB_MODS_DIR` variable near the top
of `njb.lua` to `nil`. Otherwise, you need to point it at where you put
the contents of `njb_mods/`.

Finally stick `njb.lua` somewhere executable and mark it so. Bonus points
for removing the file extension.

## Use for Users

Make a directory to hold your blog data, and run `njb -i` from inside of
it to install an empty blog there.

```bash
you@webhost:~/blogdata$ njb -i
```

Your directory will now contain four things:

  * `njb.cfg` -- a configuration file you will need to edit
  * `style.css` -- a default stylesheet for your blog which you can edit
    to change its appearance
  * `posts/` -- the directory where your post data files will be kept
  * `templates/` -- the templates used to render HTML versions of your blog
    for viewing on the WWW. You can also edit these to further customize the
    appearance of your blog.

Before you can use your blog, you will need to set two options in `njb.cfg`:

  * `HTTP_ROOT` will need to point to the URL of your blog's index file.
    This will probably be something like `http://www.somedomain.com/blog/`
    or, if you're a member of an old-school institution,
    `http://www.school.edu/~you/blog/`.
  * `HTTP_DIR` will need to point to the directory on the local disk where
    your blog's index file will sit (the one accessible via HTTP through
    the value of `HTTP_ROOT`). This will probably be something like
    `/home/you/public_html/blog/`.

To write your first post, invoke `njb` with the `-n` option and a tag
to uniquely identify your post.

```bash
you@webhost:~/blogdata$ njb -n first_post
```

At this point, if your `EDITOR` option is configured in `njb.cfg` or your
`$EDITOR` environment variable is set, this editor will be launched for you
to compose your post. Otherwise, the file `posts/first_post.md` will be
created, and you can edit that however you wish. Either way, it will
at first look like this

```
title: 
time:   2019-03-08 14:02:05

```

Give your post a title in the `title:` header field and leave a blank line
after the `time:` header, then start your post.

```
title: This is my first post.
time:  2019-03-08 14:02:05

This is the text of my first post. It is boring because _I_ am boring,
which is why I am _writing blogging software_ instead of _writing a blog_.
```

Save it and quit your editor. If `njb` opened your editor for you, your
blog post will automatically be rendered into HTML in the configured
location. If this is, indeed, your first post, your `index.html` file will
also be written, and your .css files copied. If you had to open and edit
your blog post file manually, you can make `njb` update your blog by
invoking it with the `-u` option.

With no arguments given, the `-u` option will automatically update all
posts whose post files have been altered since the last time `njb` was
invoked with `-u`.

```bash
you@webhost:~/blogdata$ njb -u`
```
You now have a blog.

You can force the update of specific posts by giving the `-u` option
arguments:

```bash
you@webhost:~/blogdata$ njb -u first_post
```

And you can force your entire blog to be rerendered with the `-f` option.

### Customizing Your Blog

As mentioned, you can edit the files in the `templates/` directory to change
the appearance of your blog; this should be straightforward. It should also
be pretty clear that the HTML-comment-looking constructs such as
`<!-- ##CONTENT## -->` signal the template parser to insert the appropriate
generated HTML, and that removing or mangling them will probably cause your
blog to not display correctly. To maintain simplicity, `njb` does no checking
or validation of the contents of these files, so you can definitely shoot
yourself in the foot this way.

One simple hook you can use is the `<!-- ##HEADER:xyz## -->` parser directive.
If what appears after the colon is the name of one of the headers in your
post, the value of the header will be inserted there. (You may notice that
this is how `njb` inserts the titles of your posts.) Only the `title:` and
`time:` headers are required for your post to be displayed, but any number
of arbitrary headers are allowed. Take the top of the following example
post:

```
title:    Flux Quaz Blue
time:     2019-03-10 12:34:56
subtitle: <h3>The Legend of the Winged Frogs</h3>

Once upon a time...
```

When writing the HTML for this post, if the parser encounters
`<!-- ##HEADER:subtitle## -->` in the `post.html` template, it will get
replaced by `<h3>The Legend of the Winged Frogs</h3>`. If the post had
no `subtitle:` header, then the parser directive would be replaced by
an empty string.

### More Involved Hooks

If, while parsing one of the post templates (`post.html`, `prev.html`,
`next.html`, or `home_link.html`), the `njb` encounters the parser directive
`<!-- ##HOOK:xyz## -->`, it will attempt to load a library from the file
`njb_hooks.lua` and call the function `xyz()` from it, with a table containing
the post's headers as an argument.

For example, consider:

The file `njb_hooks.lua` in your blog directory (the one from which you're
running `njb -u`):

```lua
-- njb_hooks.lua
-- User-level njb library.

local mod_tab = {}

local function barf_headers(headers)
    local chunks = { '<table class="headers">' }
    
    for key, val in pairs(headers) do
        local line = string.format('  <tr><td>%s :</td><td>%s</td></tr>',
                                   key, val)
        table.insert(chunks, line)
    end
    
    table.insert(chunks, '</table>')
    return table.concat(chunks, '\n')
end

mod_tab.barf = barf_headers

return mod_tab
```

The beginning of the post in question:

```
title:  Frogs of the Amazon
time:   2019-03-15 15:16:17
tags:   frogs, amphibians, rainforest, Amazon
color:  blue

Today I want to share with you one of my pseudoherpetological passions...
```

When the parser encounters `<!-- ##HOOK:barf## -->` in your edited copy
of `post.html`, it will get replaced with something like

```HTML
<table class="headers">
  <tr><td>title :</td><td>Frogs of the Amazon</td></tr>
  <tr><td>time :</td><td>2019-03-15 15:16:17</td></tr>
  <tr><td>tags :</td><td>frogs, amphibians, rainforest, Amazon</td></tr>
  <tr><td>color :</td><td>blue</td></tr>
</table>
```

If there are any hitches in this process, `njb` should complain in a Lua-y
way on stderr and substitute an empty string in place of
`<!-- ##HOOK:xyz##-- >`.
