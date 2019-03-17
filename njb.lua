#!/usr/bin/lua

--[[
    njb (.lua)
    
    New-Jersey-style Blogging software
    
    by Dan Hill
    
    last update: 2019-03-07
--]]

-- local NJB_MODS_DIR = '/usr/local/etc/njb/njb_mods/?.lua'
local NJB_MODS_DIR = '/home/dan/dev/njb/njb_mods/?.lua'

if NJB_MODS_DIR then
    package.path = package.path .. ';' .. NJB_MODS_DIR
end

local cfgt = require 'njb_config'
local errz = require 'njb_errors'
local argzt = require 'dargs'

local action = 'help'
local tokens = {}

do
    if argzt['i'] or argzt['install'] then
        action = 'install'
    elseif argzt['n'] or argzt['new'] then
        action = 'new'
    elseif argzt['f'] or argzt['force'] then
        action = 'force'
    elseif argzt['u'] or argzt['update'] then
        action = 'update'
        for _, token in pairs(argzt) do
            if #token > 0 then tokens[token] = true end
        end
    elseif argzt['l'] or argzt['list'] then
        action = 'list'
    end
end

if action == 'install' then
    local cfg_fname = os.getenv('PWD') .. '/njb.cfg'
    local f = io.open(cfg_fname, 'r')
    if f then
        f:close()
        errz.die(
[[njb is already installed in this directory. To overwrite your current
installation, remove the file njb.cfg and run njb -i again.]])
    end
    
    local install = require 'njb_install'
    local err = install.copy(cfgt)

elseif action == 'new' then
    local key = argzt['n'] or argzt['new']
    if not key:match('%S') then
        errz.die('You must provide a post token for your new post.')
    end
    local posts = require 'njb_post'
    local err = posts.init(cfgt)
    if err then
        errz.die('Error setting up: %s', err)
    end
    err = posts.new_post(key)
    if err then
        errz.die('Error creating new post: %s', err)
    end

elseif action == 'list' then
    local posts = require 'njb_post'
    local err = posts.init(cfgt)
    if err then
        errz.die('Error setting up: %s', err)
    end
    
    local post_tabs = posts.get_posts()
    if not post_tabs then
        errz.die('Unable to read post files.')
    end
    
    local post_keys = posts.post_order(post_tabs)
    if cfgt.list_with_column then
        local cold = '\205\173' -- some obscure combining diacritic
        local cpipe, err = io.popen('column -s ' .. cold .. ' -t', 'w')
        if not cpipe then
            errz.die('Error opening `column` for output: %s', err)
        end
        for _, k in ipairs(post_keys) do
            local p = post_tabs[k]
            local tstr = '                   '
            if p.time then tstr = os.date(posts.INTERNAL_TIME, p.time) end
            local chunk = string.format('%s%s%s%s%s\n',
                k, cold, tstr, cold, p['title'] or ' ')
            cpipe:write(chunk)
        end
        cpipe:close()
    else
        for _, k in ipairs(post_keys) do
            local p = post_tabs[k]
            local tstr = '                   '
            if p.time then tstr = os.date(posts.INTERNAL_TIME, p.time) end
            local chunk = string.format('%s\t%s\t%s\n',
                k, tstr, p['title'] or ' ')
            io.stdout:write(chunk)
        end
    end

elseif action == 'force' then
    local posts = require 'njb_post'
    local err = posts.init(cfgt)
    if err then
        errz.die('Error setting up: %s', err)
    end
    
    local post_tabs = posts.get_posts()
    if not post_tabs then
        errz.die('Unable to read post files.')
    end
    
    local post_keys = posts.post_order(post_tabs)
    err = posts.update_all(post_tabs, post_keys)
    if err then
        errz.die('Error updating: %s', err)
    end

elseif action == 'update' then
    local posts = require 'njb_post'
    local err = posts.init(cfgt)
    if err then
        errz.die('Error setting up: %s', err)
    end
    
    local post_tabs = posts.get_posts()
    if not post_tabs then
        errz.die('Unable to read post files.')
    end
    
    local post_keys = posts.post_order(post_tabs)
    
    local n_tokens = 0
    for _, _ in pairs(tokens) do n_tokens = n_tokens + 1 end
    
    if n_tokens == 0 then
        err = posts.update_by_time(post_tabs, post_keys)
        if err then
            errz.die('Error updating: %s', err)
        end
    else
        err = posts.update_by_token(post_tabs, post_keys, tokens)
        if err then
            errz.die('Error updating: %s', err)
        end
    end

else
    print([[
usage: njb OPTION [ TOKEN ] [ ADD'L TOKENS ... ]

where OPTION is one of

    -i, --install
        install a new blog in the current location

    -l, --list
        list all posts, titles, and times

    -n TOKEN, --new TOKEN
    	create a new post
    
    -u, --update
        update all posts modified since the last update
    
    -u TOKENS, --update TOKENS
        update all posts represented by the given tokens
    
    -f, --force
        force the update and rerendering of the entire blog

]])
end