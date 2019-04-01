local lfs = require('lfs')
--获取路径
local function stripfilename(filepath)
    return string.match(filepath, "(.+)/[^/]*%.%w+$") --*nix system
    --return string.match(filepath, “(.+)\\[^\\]*%.%w+$”) — windows
end

--获取文件名
local function strippath(filepath)
    return string.match(filepath, ".+/([^/]*%.%w+)$") -- *nix system
    --return string.match(filepath, “.+\\([^\\]*%.%w+)$”) — *nix system
end

--去除扩展名
local function stripextension(filepath)
    local idx = filepath:match(".+()%.%w+$")
    if (idx) then
        return filepath:sub(1, idx - 1)
    else
        return filepath
    end
end

--获取扩展名
local function getextension(filepath)
    return filepath:match(".+%.(%w+)$")
end

local replSep = function(s)
    return (string.gsub(s, "/", "."))
end

local readfile = function(filepath)
    local file, err = io.open(filepath, 'r')
    assert(file, err)
    local str, e = file:read('*a')
    assert(str, e)
    file:close()
    return str
end
local attrDir
attrDir = function(path, func)
    for file in lfs.dir(path) do
        if file ~= "." and file ~= ".." then
            --过滤linux目录下的"."和".."目录
            local f = path .. '/' .. file
            local attr = lfs.attributes(f)
            if attr.mode == "directory" then
                attrDir(f, func)                          --如果是目录，则进行递归调用
            else
                func(f)
            end
        end
    end
end
print('start!')
local currentdir = lfs.currentdir()
local config = {
    entrance = 'export',
    workdir = '../project',
    export = '/../build/asynclib.lua',
}
local mergefile, err = io.open(currentdir .. (config.export), 'w+')
assert(mergefile, err)
config.mergefile = mergefile
local mergefilestr = [[
local args = { ... }
local oriRequire = require
local preload = {}
local loaded = {}
local _require = function(path, ...)
    if loaded[path] then
        return loaded[path]
    end
    if preload[path] then
        local func = preload[path]
        local mod = func(...) or true
        loaded[path] = mod
        return mod
    end
    return oriRequire(path, ...)
end
local define = function(path, factory)
    preload[path] = factory
end


]]
attrDir(config.workdir, function(filepath)
    if getextension(filepath) == 'lua' then
        local route = filepath:sub(#config.workdir + 2, -5)
        route = replSep(route)
        print('register:', route)
        mergefilestr = mergefilestr .. ([[define(']] .. route .. [[', function(require, ...)]])
        mergefilestr = mergefilestr .. ('\n')
        mergefilestr = mergefilestr .. (readfile(filepath))
        mergefilestr = mergefilestr .. ('\n')
        mergefilestr = mergefilestr .. ([[end)]])
        mergefilestr = mergefilestr .. ('\n')
        mergefilestr = mergefilestr .. ('\n')
    end
end)
mergefilestr = mergefilestr .. ([[return _require(']] .. config.entrance .. [[', unpack(args))]])
config.mergefile:write(mergefilestr)
config.mergefile:close()
print('done!')