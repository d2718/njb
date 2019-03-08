#!/usr/bin/lua

--[[ templater.lua

    a module for processing text templates
    
    2019-03-02
--]]

local modt = {}

-- If you change the default pattern, make sure there are TWO sets of
-- parentheses, including one around the whole pattern.
modt.pattern = '(<!%-%- ##(.-)## %-%->)'
modt.separator = ':'

-- Whether error messages should be written to stderr. (If false they
-- remain silent.)
modt.errors  = true

local function rpt(fmtstr, ...)
    local msg = string.format(fmtstr, unpack(arg))
    local msglen = #msg
    io.stderr:write(msg)
    if msg:sub(msglen, msglen) ~= '\n' then
        io.stderr:write('\n')
    end
end

local function sub_aux(tab, chunk)
    -- rpt('sub_aux(..., %q) called', chunk)
    local v = tab[chunk]
    if type(v) == 'string' then
        -- rpt('    tab[%q] is a string: %q', chunk, v)
        return v
    elseif type(v) == 'function' then
        -- rpt('   tab[%q] is a function', chunk)
        return v(chunk)
    elseif type(v) == 'nil' then
        -- rpt('   tab[%q] is nil', chunk)
        return nil
    else
        if modt.errors then
            io.stderr:write('templater: non-supported type found in sub table')
        end
        return nil
    end
end

modt.string = function(s, tab, pat)
    local p = pat or modt.pattern
    -- rpt('pattern is |%s|', p)
    
    local function f(all, part)
        r = sub_aux(tab, part)
        return r or all
    end
    
    return s:gsub(p, f)
end

modt.file_lines = function(fname, tab, pat)
    local p = pat or modt.pattern
    
    local f = io.open(fname, 'r')
    if not f then
        if modt.errors then
            io.stderr:write(string.format(
                'templater: file "%s" cannot be opened', fname))
        end
        return nil
    end
    
    local chunks = {}
    
    for line in f:lines() do
        local s = modt.string(line, tab, p)
        table.insert(chunks, s)
    end
    f:close()
    
    return chunks
end

modt.file = function(fname, tab, pat)
    local chunks = modt.file_lines(fname, tab, pat)
    return table.concat(chunks, '\n')
end

local function asub_aux(tab, chunk, sep)
    local sepp = '([^' .. sep .. ']+):(.*)'
    
    local t_key, f_arg = chunk:match(sepp)
    if t_key then
        local f = tab[t_key]
        if f then return f(f_arg) end
    else
        return tab[chunk]
    end
end

modt.astring = function(s, tab, sep, pat)
    local p = pat or mod.pattern
    local v = sep or mod.separator
    
    local function f(all, part)
        r = sub_aux(tab, part, v)
        return r or all
    end
    
    return s:gsub(f, p)
end

local function afsub_aux(tab, chunk, sepp)
    local t_key, f_arg = chunk:match(sepp)
    if t_key then
        local f = tab[t_key]
        if f then
            return f(f_arg)
        else
            return nil
        end
    else
        return tab[chunk]
    end
end

modt.afile_lines = function(fname, tab, sep, pat)
    local p = pat or modt.pattern
    local v = sep or modt.separator
    local vp = '([^' .. v .. ']+):(.*)'
    
    local function subf(fall, part)
        r = afsub_aux(tab, part, vp)
        return r or all
    end
    
    local f, err = io.open(fname, 'r')
    if not f then
        if modt.errors then
            io.stderr:write(string.format('templater: file "%s" cannot be opened\n', fname))
        end
        return nil
    end
    
    local line_chunks = {}
    for line in f:lines() do
        local s = line:gsub(p, subf)
        if s then table.insert(line_chunks, s) end
    end
    
    f:close()
    return line_chunks
end

modt.afile = function(fname, tab, sep, pat)
    local chunks = modt.afile_lines(fname, tab, sep, pat)
    if chunks then
        return table.concat(chunks, '\n')
    else
        return nil
    end
end

modt.afile_iter = function(fname, tab, sep, pat)
    local p = pat or modt.pattern
    local v = sep or modt.separator
    local vp = '([^' .. v .. ']+):(.*)'
    
    local function subf(all, part)
        r = afsub_aux(tab, part, vp)
        return r or all
    end
    
    local f, err = io.open(fname, 'r')
    if not f then
        if modt.errors then
            local msg = string.format('templater: file "%s" cannot be opened\n',
                                      fname)
            io.stderr:write(msg)
        end
        return nil
    end
    
    return function()
        local line = f:read('*line')
        if line then
            return line:gsub(p, subf)
        else
            f:close()
            return nil
        end
    end
end

return modt
