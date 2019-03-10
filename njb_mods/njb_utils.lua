--[[
    njb_utils.lua
    
    Utility functions for njb, for use with both njb_install and njb_post.
    
    updated 2019-03-08
--]]

local modt = {}

-- Returns a list of filenames in the given directory. If the second
-- argument is supplied, it will call "ls dirpath/wildcard" so you can
-- do stuff like call
--
-- ls('frogs', '*.txt')
--
-- To return all the .txt files in the frogs directory.
modt.ls = function(dirpath, wildcard)
    local path = dirpath
    if path:sub(#path, #path) ~= '/' then
        path = path .. '/'
    end

    local cmd = string.format('ls %s', path)
    if wildcard then
        cmd = cmd .. wildcard
    end
    
    local p, err = io.popen(cmd)
    if err then return nil, err end
    local paths = {}
    for line in p:lines() do
        table.insert(paths, path .. line)
    end
    
    return paths, nil
end

-- Checks to see if the provided path (file or directory) exists and is
-- writable by the current user.
modt.exists = function(path)
    local ok = os.rename(path, path)
    return ok
end

-- Checks to see if the provided path is an extant directory writable by
-- the current user.
modt.dir_exists = function(dirpath)
    local path = dirpath
    if path:sub(#path, #path) ~= '/' then
        path = path .. '/'
    end
    return modt.exists(path)
end

-- Returns the *nixy time of the last modification of the provided file.
modt.last_modified = function(path)
    local cmd = string.format('stat -c %%Y "%s"', path)
    local p, err = io.popen(cmd, 'r')
    if not p then return nil, 'unable to open call to stat' end
    local n = p:read('*number')
    p:close()
    if not n then return nil, 'call to stat failed to return number' end
    return n, nil
end

-- Given a path, it returns just the filename with the extension stripped.
modt.fbase_extract = function(fstr)
    return fstr:match('([^/]+)%.[^.]+$')
end

-- Returns the file extension of the provided path.
modt.file_extension = function(path)
    return path:match('%.([^.]*)$')
end

-- If a string is longer than the provided length, truncates it and appends
-- an ellipsis; otherwise, it just returns the string.
modt.string_limit = function(s, max_len)
    if #s > max_len then
        return s:sub(1, max_len) .. '...'
    else
        return s
    end
end

return modt