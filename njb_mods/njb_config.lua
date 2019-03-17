--[[
    njb_config.lua
    
    njb installation-specific configuration data
    
    After pointing your NJB_MODS_DIR (in the main njb.lua file) to the
    directory where this file is, you set all the installation-specific
    options in the table below that gets returned.
    
    updated 2019-03-17
--]]

local cfg_t = {
    -- These three are files/directories included with the distribution.
    ['default_template_dir'] = '/home/dan/dev/njb/default_templates/',
    ['default_css_file']     = '/home/dan/dev/njb/style.css',
    ['config_file_template'] = '/home/dan/dev/njb/config.template',
    -- If you have some different markdown renderer on your system and want
    -- to use it by default instead of cmark. This is especially useful if
    -- you have also installed njbrender.
    ['markdown_render_cmd']  = '/usr/local/bin/cmark --smart',
    -- Whether the utility column(1) should be used to format the output
    -- of njb -l / --list.
    ['list_with_column']     = true,
}

return cfg_t
