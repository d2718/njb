--[[
    njb_install.lua
    
    Module for installing njb.
    
    updated 2019-03-06
--]]

local errz = require 'njb_errors'
local util = require 'njb_utils'
local templater = require 'templater'
templater.errors = false

local modt = {}

function modt.copy(cfgt)
    local temp_src   = cfgt['default_template_dir']
    local css_src    = cfgt['default_css_file']
    local config_src = cfgt['config_file_template']
    local pwd = os.getenv('PWD')
    local temp_tgt   = pwd .. '/templates/'
    local post_dir   = pwd .. '/posts/'
    local css_tgt    = string.format('%s/%s.%s', pwd,
                                     util.fbase_extract(css_src),
                                     util.file_extension(css_src))
    local config_tgt = pwd .. '/njb.cfg'
    
    if not util.dir_exists(temp_tgt) then
        local cmd = string.format('mkdir %s', temp_tgt)
        local err = os.execute(cmd)
        if err ~= 0 then
            errz.die('unable to create directory %q: %s', temp_tgt, err)
        end
    end
    
    cmd = string.format('cp %s %s', css_src, css_tgt)
    err = os.execute(cmd)
    if err ~= 0 then
        errz.die('unable to copy file %q to %q: %s',
                 css_src, css_tgt, err)
    end
    
    local modpaths, err = util.ls(temp_src)
    if err then
        errz.die('unable to list files in %q: %s', temp_src, err)
    end
    for _, path in ipairs(modpaths) do
        local cmd = string.format('cp %q %q', path, temp_tgt)
        local err = os.execute(cmd)
        if err ~= 0 then
            errz.die('unable to copy file %q to %q: %s', path, temp_tgt, err)
        end
    end
    
    if not util.dir_exists(post_dir) then
        cmd = string.format('mkdir %q', post_dir)
        err = os.execute(cmd)
        if err ~= 0 then
            errz.die('unable to create directory %q: %s', post_dir, err)
        end
    end
    
    local config_table = {['MARKDOWN_COMMAND'] = cfgt['markdown_render_cmd']}
    
    local temp_txt = templater.file(config_src, config_table)
    
    local f, err = io.open(config_tgt, 'w')
    if not f then
        errz.die('unable to create config file %q: %s', config_tgt, err)
    end
    f:write(temp_txt)
    f:write('\n')
    f:close()
end

return modt