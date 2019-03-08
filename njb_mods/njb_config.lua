--[[
    njb_config.lua
    
    njb installation-specific configuration data
    
    After pointing your NJB_MODS_DIR (in the main njb.lua file) to the
    directory where this file is, you set all the installation-specific
    options in the table below that gets returned.
    
    updated 2019-03-06
--]]

local cfg_t = {
    ['default_template_dir'] = '/home/dan/dev/njb/default_templates/',
    ['default_css_file']     = '/home/dan/dev/njb/style.css',
    ['config_file_template'] = '/home/dan/dev/njb/config.template',
    ['markdown_render_cmd']  = '/usr/local/bin/cmark --smart',
}

return cfg_t
