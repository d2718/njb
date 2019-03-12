--[[
    njb_post.lua
    
    Module for dealing with posts. This is where the meat of the
    functionality is.
    
    updated 2019-03-12
--]]

local dconfig   = require 'dconfig'
local errz      = require 'njb_errors'
local util      = require 'njb_utils'
local templater = require 'templater'

local modt = {}

-- For matching "name: value" pairs in post headers.
local HEADER_PATTERN = '^%s*([^:]+)%s*:%s*(.-)%s*$'
-- How we store times in unambiguous textual format around here.
local INTERNAL_TIME  = '%Y-%m-%d %H:%M:%S'
modt.INTERNAL_TIME = INTERNAL_TIME
-- How we read times from said unambiguous textual format.
local TIME_PATTERN   = '(%d+)%-(%d+)%-(%d+)%s+(%d+):(%d+):?(%d*)'
-- Because Lua can't both read from and write to the same subprocess, we
-- need a place to stash markdown that's been rendered into HTML. This is
-- the name of that stash.
local TEMP_FILENAME  = '.temp_markdown_output'
-- This file gets rewritten to with every call to "njb -u" or "njb -f"
-- so that njb can tell which files have been changed since. The text in
-- the file is the time of the update, but that's just for show because
-- njb reads the file modification time.
local update_time_fname = '.last_update'

-- These are all configuration file options.
local http_root = nil
local http_dir  = nil
local index_previews = 5
local preview_length = 240
local link_title_length = 32
local display_time_format  = '%b %d, %I:%M %p'
local css_href = ''
local editor = nil
local markdown_command = nil

-- This turns a string in the INTERNAL_TIME format into a *nixy time.
local function parse_intl_time(tstr)
    local ys, mos, ds, hs, mis, ss = tstr:match(TIME_PATTERN)
    
    local nz = {}
    for _, s in ipairs({ ys, mos, ds, hs, mis }) do
        local x = tonumber(s)
        if not x then return nil end
        table.insert(nz, x)
    end
    table.insert(nz, tonumber(ss))
    
    local t = {}
    t.year, t.month, t.day, t.hour, t.min, t.sec = unpack(nz)
    
    return os.time(t)
end

-- Ensures the provided path ends it ".md".
local function ensure_md_extension(path)
    local ext = util.file_extension(path)
    if ext == 'md' then
        return path
    elseif path:sub(#path, #path) == '.' then
        return path .. 'md'
    else
        return path .. '.md'
    end
end

-- Strips out (or possibly just mangles irrevocably) HTML tags. Pay no
-- attention to the man behind this SO answer:
-- https://stackoverflow.com/questions/1732348/regex-match-open-tags-except-xhtml-self-contained-tags/1732454#1732454
local function strip_html_tags(s)
    return s:gsub('<[^>]->', '')
end

-- Initializes the module with the user's configured settings. You must
-- call this with the table returned by requiring 'njb_config'.
modt.init = function(cfgt)
    dconfig.init()
    dconfig.add_str('HTTP_ROOT',   nil, { TRIM=true })
    dconfig.add_str('HTTP_DIR',    nil, { TRIM=true })
    dconfig.add_str('DISPLAY_TIME_FORMAT', nil)
    dconfig.add_num('INDEX_PREVIEWS',    index_previews)
    dconfig.add_num('PREVIEW_LENGTH',    preview_length)
    dconfig.add_num('LINK_TITLE_LENGTH', link_title_length)
    dconfig.add_str('MARKDOWN_COMMAND', '', { TRIM=true })
    dconfig.add_str('EDITOR',      '',  { TRIM=true })
    local fread = dconfig.configure({ 'njb.cfg' }, true)
    if not fread then
        errz.die('unable to find configuration file "njb.cfg"')
    end
    
    local tmp = dconfig.get('HTTP_ROOT')
    if tmp and tmp:match('%S') then
        http_root = tmp
        if http_root:sub(#http_root, #http_root) ~= '/' then
            http_root = http_root .. '/'
        end
    else
        errz.die('ERROR: Option "HTTP_ROOT" not defined in njb.cfg.')
    end
    tmp = dconfig.get('HTTP_DIR')
    if tmp and tmp:match('%S') then
        http_dir = tmp
        if http_dir:sub(#http_dir, #http_dir) ~= '/' then
            http_dir = http_dir .. '/'
        end
    else
        errz.die('ERROR: Option "HTTP_DIR" not defined in njb.cfg.')
    end
    
    tmp = dconfig.get('DISPLAY_TIME_FORMAT')
    if tmp then
        display_time_format = tmp
    end
    tmp = dconfig.get('INDEX_PREVIEWS')
    if tmp then
        if tmp >= 1 then
            index_previews = tmp
        else
            errz.warn('WARNING: Option "INDEX_PREVIEWS" must be positive integer.')
        end
    end
    tmp = dconfig.get('PREVIEW_LENGTH')
    if tmp then
        if tmp >= 1 then
            preview_length = tmp
        else
            errz.warn('WARNING: Option "PREVIEW_LENGTH" must be positive integer.')
        end
    end
    tmp = dconfig.get('LINK_TITLE_LENGTH')
    if tmp then
        if tmp >= 1 then
            link_title_length = tmp
        else
            errz.warn('WARNING: Option "LINK_TITLE_LENGTH" must be a positive integer.')
        end
    end
    
    tmp = dconfig.get('MARKDOWN_COMMAND')
    if tmp and tmp:match('%S') then
        markdown_command = tmp
    else
        markdown_command = cfgt['markdown_render_cmd']
    end
    tmp = dconfig.get('EDITOR')
    if tmp and tmp:match('%S') then
        editor = tmp
    end
    
    css_href = http_root .. util.fbase_extract(cfgt['default_css_file']) .. '.css'
    
    if not util.dir_exists(http_dir) then
        errz.warn('Target directory "%s" doesn\'t exist; creating.', http_dir)
        local cmd = string.format('mkdir %s', http_dir)
        local err = os.execute(cmd)
        if err ~= 0 then
            errz.die('Unable to create target directory "%s": %s',
                     http_dir, err)
        end
    end
    
    if not util.dir_exists(http_dir .. 'posts/') then
        local cmd = string.format('mkdir %sposts/', http_dir)
        local err = os.execute(cmd)
        if err ~= 0 then
            errz.die('Unable to create post directory "%s": %s',
                     http_dir, err)
        end
    end
    
    return nil
end

-- Return the last time the user ran njb with the -u or -f options.
local function get_update_time()
    local ut, err = util.last_modified(update_time_fname)
    if err then
        errz.warn('WARNING: unable to read last update file "%s": %s',
                  update_time_fname, err)
    end
    return ut, err
end

-- Set the last update time (for when the user runs njb with -u or -f).
local function set_update_time()
    local f, err = io.open(update_time_fname, 'w')
    if not f then
        return string.format('unable to open last update file "%s" for writing: %s',
                             update_time_fname, err)
    end
    f:write(os.date())
    f:write('\n')
    f:flush()
    f:close()
    return nil
end

-- Given the freshly-opened file handle of a post file, this will return
-- a { ['key'] = 'value' } table of all the "key: value" headers in the post.
modt.read_headers = function(open_file)
    local h = {}
    local line = open_file:read('*line')
    local k, v = line:match(HEADER_PATTERN)
    while k and v do
        h[string.lower(k)] = v
        line = open_file:read('*line')
        k, v = line:match(HEADER_PATTERN)
    end
    
    return h
end

-- Returns the closest thing we get to a "post struct" given a post filename.
-- It's pretty clear from the code below what the format is.
modt.get_post_info = function(fname)
    local f, err = io.open(fname, 'r')
    if not f then
        return nil, string.format('unable to open file "%s": %s', fname, err)
    end
    
    local h = modt.read_headers(f)
    f:close()
    
    local fbase = util.fbase_extract(fname)
    local t_ok, ptime = pcall(parse_intl_time, h.time)
    local ptitle = h.title
    
    if fbase and t_ok and ptitle then
        local p = {
            ['title']    = ptitle,
            ['time']     = ptime,
            ['tag']      = fbase,
            ['headers']  = h,
            ['filename'] = fname,
            ['htmlfile'] = string.format('%sposts/%s.html', http_dir, fbase),
            ['url']      = string.format('%sposts/%s.html', http_root, fbase)
        }
        
        return p, nil
    else
        return nil, string.format('problem with header or filename of "%s"',
                                  fname)
    end
end

-- Return a table mapping post identifiers to post objects (see get_post_info()
-- above) for all the posts in the blog.
modt.get_posts = function()
    local mdflist, err = util.ls('posts/')
    if err then return nil, err end
    
    local post_files = {}
    for _, pfname in ipairs(mdflist) do
        local p, err = modt.get_post_info(pfname)
        if p then
            post_files[p.tag] = p
        else
            errz.warn('WARNING: "%s"', err)
        end
    end
    
    return post_files
end

-- Given a { ['identifier'] = post_object } table (as returned by get_posts()
-- above), supplies an array of the post identifiers in reverse chronological
-- order (that is, most recent first).
modt.post_order = function(posts)
    local tags = {}
    for k, _ in pairs(posts) do table.insert(tags, k) end
    table.sort(tags, function(a, b)
                        return posts[a]['time'] > posts[b]['time']
                    end)
    return tags
end

-- Create a new post, given an identifier.
--   * Create a posts/identifier.md file
--   * Give it a skeleton header populated with a blank title: and the
--     current time:
--   * If the user has an editor configured, open that editor so the post
--     can be written, and render the new post upon quitting the editor.
--     If no editor is configured, print a message informing the user of
--     the new filename and what to do.
modt.new_post = function(tag)
    local fname = string.format('posts/%s', ensure_md_extension(tag))
    if util.exists(fname) then
        return string.format('There is already a post file "%s".', fname)
    end
    
    local f, err = io.open(fname, 'w')
    if not f then
        return string.format('Unable to open file "%s" for writing: %s',
                             fname, err)
    end
    f:write('title: \n')
    f:write(string.format('time:  %s\n\n', os.date(INTERNAL_TIME)))
    f:close()
    
    local cmd = editor
    if cmd then
        cmd = string.format('%s "%s"', cmd, fname)
    else
        local editor_exec = os.getenv('EDITOR')
        if editor_exec then
            cmd = string.format('%s "%s"', editor_exec, fname)
        end
    end
    if cmd then
        err = os.execute(cmd)
        if err ~= 0 then
            errz.warn('WARNING: There may have been a problem with your "EDITOR_COMMAND" config option.')
        else
            local post_tabs = modt.get_posts()
            if not post_tabs then
                errz.die('Unable to read posts.')
            end
            local post_keys = modt.post_order(post_tabs)
            err = modt.update_by_time(post_tabs, post_keys)
            if err then
                errz.die('Error updating: %s', err)
            end
        end
    else
        errz.warn('Added file "%s". Edit and then update with "njb -u".',
                  fname)
    end
    
    return nil
end

-- Return the body of the post in the provided filename as rendered HTML.
modt.markdown = function(filename)
    local f, err = io.open(filename, 'r')
    if not f then
        return nil, string.format('error opening "%s" for reading: %s',
                                 filename, err)
    end
    modt.read_headers(f)
    
    local cmd = string.format('%s >%s', markdown_command, TEMP_FILENAME)
    
    local p, err = io.popen(cmd, 'w')
    if not p then
        return nil, string.format('error launching markdown renderer: %s', err)
    end
    
    local txt = f:read('*all')
    p:write(txt)
    p:flush()
    p:close()
    f:close()
    
    f, err = io.open(TEMP_FILENAME, 'r')
    if not f then
        return nil, string.format('error opening temporary file "%s" for reading: %s',
                                  TEMP_FILENAME, err)
    end
    txt = f:read('*all')
    f:close()
    
    local ok, err = os.remove(TEMP_FILENAME)
    if not ok then
        errz.warn('WARNING: error removing temporary markdown file "%s": %s',
                  TEMP_FILENAME, err)
    end
    
    return txt, nil
end

-- Attempt to load, run, and return the value from a user-defined hook.
modt.user_hook = function(arg, headers)
    local ok, usrlib = pcall(require, 'njb_hooks')
    if not ok then
        errz.warn('WARNING: unable to load module "njb_hooks.lua": %s', usrlib)
        return ''
    end
    if type(usrlib) ~= 'table' then
        errz.warn('WARNING: requiring "njb_hooks.lua" returned %s',
                  type(usrlib))
        return ''
    end
    
    local f = usrlib[arg]
    if not f then
        errz.warn('WARNING: no function %s(...) in module "njb_hooks.lua"', arg)
        return ''
    end
    
    local ok, txt = pcall(f, headers)
    if ok then
        if type(txt) == 'string' then
            return txt
        else
            errz.warn('WARNING: call to %s(...) returned %s', arg, type(txt))
            return ''
        end
    else
        errz.warn('WARNING: call to %s(...) returned error: %s', arg, txt)
        return ''
    end
end

-- (Re-)write the HTML for the supplied post object. Objects for the next
-- and previous post are required for the text that goes in the "next post"
-- and "previous post" links. If either is nil, no link will be written.
modt.render_post = function(this_post, prev_post, next_post)
    local subt = {}
    local err = nil
    
    subt['CONTENT'], err = modt.markdown(this_post.filename)
    if err then
        return string.format('error rendering post "%s": %s',
                             this_post.filename, err)
    end
    
    subt['STYLESHEET'] = css_href
    subt['TIME'] = os.date(display_time_format, this_post.time)
    
    local function headers(arg)
        local v = this_post.headers[arg]
        return v or ''
    end
    
    local function hook(arg)
        return modt.user_hook(arg, this_post.headers)
    end
    
    subt['HEADER'] = headers
    subt['HOOK']   = hook
    
    subt['PREV'] = ''
    subt['NEXT'] = ''
    subt['HOME'] = ''
    do
        local hst = {
            ['URL']    = http_root,
            ['HEADER'] = headers,
            ['HOOK']   = hook
        }
        subt['HOME'] = templater.afile('templates/home_link.html', hst)
    end
    if prev_post then
        local pst = {
            ['URL']    = prev_post.url,
            ['TITLE']  = util.string_limit(prev_post.title, link_title_length),
            ['HEADER'] = headers,
            ['HOOK']   = hook
        }
        subt['PREV'] = templater.afile('templates/prev.html', pst)
    end
    if next_post then
        local nst = {
            ['URL']    = next_post.url,
            ['TITLE']  = util.string_limit(next_post.title, link_title_length),
            ['HEADER'] = headers,
            ['HOOK']   = hook
        }
        subt['NEXT'] = templater.afile('templates/next.html', nst)
    end
    
    local f, err = io.open(this_post.htmlfile, 'w')
    if not f then
        return string.format('unable to open file "%s" for writing: %s',
                             this_post.htmlfile, err)
    end
    for line in templater.afile_iter('templates/post.html', subt) do
        f:write(line)
        f:write('\n')
    end
    f:close()
    
    return nil
end

-- Write a preview for the provided post object to the provided open file
-- handle. This should probably be the file handle to the "index.html" file.
modt.render_preview = function(post, open_file)

    local subt = {}
    local err = nil
    
    local prev_txt, err = modt.markdown(post.filename)
    if err then
        return string.format('error rendering preview for post "%s": %s',
                             post.filename, err)
    end
    prev_txt = strip_html_tags(prev_txt)
    subt['PREVIEW'] = util.string_limit(prev_txt, preview_length)
    subt['TIME'] = os.date(display_time_format, post.time)
    subt['URL']  = post.url
    
    local function headers(arg)
        local v = post.headers[arg]
        return v or ''
    end
    
    subt['HEADER'] = headers
    
    for line in templater.afile_iter('templates/preview.html', subt) do
        open_file:write(line)
        open_file:write('\n')
    end
    
    return nil
end

-- Render the blog's index page. Arguments should be the return values of
-- get_posts() and post_order(), respectively.
modt.write_index = function(posts, post_order)
    local tgt_fname = http_dir .. 'index.html'
    local err = nil
    local f = ''
    
    local function previews()
        for n = 1,index_previews,1 do
            local post = posts[post_order[n]]
            if post then
                err = modt.render_preview(post, f)
                if err then
                    errz.warn('WARNING: error rendering preview for "%s": %s',
                              post.filename, err)
                end
            end
        end
        return ''
    end
    
    local subt = {
        ['STYLESHEET'] = css_href,
        ['HISTORY_LINK'] = http_root .. 'history.html',
        ['PREVIEWS']   = previews
    }
    
    f, err = io.open(tgt_fname, 'w')
    if not f then
        return string.format('error opening "%s" for writing: %s',
                             tgt_fname, err)
    end
    
    for line in templater.afile_iter('templates/index.html', subt) do
        f:write(line)
        f:write('\n')
    end
    f:close()
    
    return nil
end

-- Write the business content of the history page. Arguments are the
-- return values of get_posts() and post_order(), as well as the open
-- file handle to the history.html file being written.
local function write_history_list(posts, post_order, open_file)
    local max_n = #post_order
    
    local first_post = posts[post_order[1]]
    local fptimet = os.date('*t', first_post.time)
    local cur_year = fptimet.year
    local cur_mo   = fptimet.month
    open_file:write('<ul id="history">\n')
    open_file:write(string.format(
[[   <li class="year">%s <ul>
        <li class="month">%s <ul>
]], os.date('%Y', first_post.time), os.date('%B', first_post.time)))
    
    for n, ptag in ipairs(post_order) do
        local p = posts[ptag]
        local ptimet = os.date('*t', p.time)
        if ptimet.year ~= cur_year then
            open_file:write(string.format(
[[       </ul></li>
        </ul></li>
    <li class="year">%s <ul>
        <li class="month">%s <ul>
]], os.date('%Y', p.time), os.date('%B', p.time)))
        elseif ptimet.month ~= cur_mo then
            open_file:write(string.format(
[[      </ul></li>
        <li class="month">%s <ul>
]], os.date('%B', p.time)))
        end
        
        open_file:write(string.format(
[[          <li class="post"><a href="%s">%s</a></li>
]], p.url, p.title))
        cur_year = ptimet.year
        cur_mo   = ptimet.month
    end
    
    open_file:write(
[[        </ul></li>
    </ul></li>
</ul>
]])
end

-- Write the history.html file with links to all the posts. Arguments are
-- the return values of get_posts() and post_order().
modt.write_history = function(posts, post_order)
    local hist_fname = http_dir .. 'history.html'
    local f, err = io.open(hist_fname, 'w')
    if err then
        return string.format('error opening "%s" for writing: %s',
                             hist_fname, err)
    end

    local function meat_func()
        write_history_list(posts, post_order, f)
        return ''
    end
    
    local subt = {
        ['STYLESHEET'] = css_href,
        ['HOME_URL']   = http_root,
        ['HISTORY']    = meat_func
    }
    
    for line in templater.afile_iter('templates/history.html', subt) do
        f:write(line)
        f:write('\n')
    end
    
    f:close()
    return nil
end

-- Rerender all the HTML for every post, as well as the index and
-- history pages.
modt.update_all = function(posts, post_order)
    for n, tag in ipairs(post_order) do
        local prevp = posts[post_order[n+1]]
        local nextp = posts[post_order[n-1]]
        local p = posts[tag]
        
        local err = modt.render_post(p, prevp, nextp)
        if err then
            errz.warn('WARNING: error rendering post "%s": %s',
                       p.filename, err)
        end
    end
    
    local err = modt.write_index(posts, post_order)
    if err then
        return string.format('error writing index file: %s', err)
    end
    
    local css_files, err = util.ls('./', '*.css')
    if err then
        errz.warn('WARNING: error listing CSS files: %s', err)
    else
        for _, fname in ipairs(css_files) do
            local cmd = string.format('cp %s %s', fname, http_dir)
            err = os.execute(cmd)
            if err ~= 0 then
                errz.warn('WARNING: error copying file "%s"', fname)
            end
        end
    end
    
    err = modt.write_history(posts, post_order)
    if err then
        return string.format('error writing history file: %s', err)
    end
    
    err = set_update_time()
    if err then
        return string.format('error updating update time: %s', err)
    end
    
    return nil
end

-- Rerender only some specified posts. The posts are specified by the
-- update_ns argument, which is a list of the indices of the identifiers
-- in the post_order argument of the posts that should be updated.
-- This will also update pages with links to those posts: the ones
-- bracketing each of them chronologically, as well as the index and
-- history pages.
modt.update_some = function(posts, post_order, update_ns)
    local update_index = false
    local to_update = {}
    
    for _, n in ipairs(update_ns) do
        local k = post_order[n]
        if k then
            to_update[k] = true
            if n <= index_previews then update_index = true end
            local pk = post_order[n-1]
            if pk then to_update[pk] = true end
            pk = post_order[n+1]
            if pk then to_update[pk] = true end
        end
    end
    
    for n, tag in ipairs(post_order) do
        if to_update[tag] then
            local prevp = posts[post_order[n+1]]
            local nextp = posts[post_order[n-1]]
            local p = posts[tag]
            
            local err = modt.render_post(p, prevp, nextp)
            if err then
                errz.warn(' error rendering post "%s": %s',
                          p.filename, err)
            end
        end
    end
    
    if update_index then
        local err = modt.write_index(posts, post_order)
        if err then
            return string.format('error writing index file: %s', err)
        end
    end
    
    local err = modt.write_history(posts, post_order)
    if err then
        return string.format('error writing history file: %s', err)
    end
    
    return nil
end

-- Update all the posts whose "posts/identifier.md" files have been modified
-- since the last call of "-u" or "-f". Also updates neighboring posts and
-- index and history.
modt.update_by_time = function(posts, post_order)
    local last_update_time, err = get_update_time()
    if not last_update_time then
        errz.warn('unable to read time of last update: %s\nupdating all...',
                  err)
        return modt.update_all(posts, post_order)
    end
    
    local update_ns = {}
    for n, tag in ipairs(post_order) do
        local p = posts[tag]
        if p then
            local put, err = util.last_modified(p.filename)
            if err then
                errz.warn('unable to determine modification time of "%s": %s',
                          p.filename, err)
                table.insert(update_ns, n)
            elseif put > last_update_time then
                table.insert(update_ns, n)
            end
        end
    end
    
    local css_files, err = util.ls('./', '*.css')
    if err then
        errz.warn('WARNING: error listing CSS files: %s', err)
    else
        for _, fname in ipairs(css_files) do
            local fut, err = util.last_modified(fname)
            if fut and fut <= last_update_time then
                -- Don't do anything.
            else
                if err then
                    errz.warn('unable to determine modification time of "%s": %s',
                              fname, err)
                end
                local cmd = string.format('cp %s %s', fname, http_dir)
                err = os.execute(cmd)
                if err ~= 0 then
                    errz.warn('WARNING: error copying file "%s"', fname)
                end
            end
        end
    end
    
    err = modt.update_some(posts, post_order, update_ns)
    if err then
        return err
    end
    err = set_update_time()
    if err then
        return string.format('error updating update time: %s', err)
    end
    return nil
end

-- Update specific posts as provided by arguments to "-u". Also updates
-- neighboring posts and index and history, but does NOT modify the last
-- update time, like a call to "-f" or "-u" without arguments does.
modt.update_by_token = function(posts, post_order, tokens)
    for tok, _ in pairs(tokens) do
        if not posts[tok] then
            errz.warn('WARNING: there is no post "%s".', tok)
        end
    end
    
    local update_ns = {}
    for n, tok in ipairs(post_order) do
        if tokens[tok] then table.insert(update_ns, n) end
    end
    
    local err = modt.update_some(posts, post_order, update_ns)
    if err then
        return err
    end
    return nil
end

return modt