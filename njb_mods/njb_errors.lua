--[[
    njb_errors.lua
    
    This module gets loaded when something goes wrong and an error message
    needs to be shown.
    
    updated 2019-03-03
--]]

local modt = {}

modt.die = function (fmtstr, ...)
    local msg = string.format(fmtstr, unpack(arg))
    io.stderr:write(msg)
    io.stderr:write('\n')
    os.exit(1)
end

modt.warn = function(fmtstr, ...)
    local msg = string.format(fmtstr, unpack(arg))
    io.stderr:write(msg)
    io.stderr:write('\n')
end

return modt