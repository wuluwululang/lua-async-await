local Awaiter = require('src.Awaiter')
local Task = require('src.Task')
local try = require('libs.try_catch_finally').try

local _G = _G
local coroutine = _G.coroutine
local setmetatable = _G.setmetatable
local setfenv = _G.setfenv
local type = _G.type
local error = _G.error
local unpack = _G.unpack

local M = {}
local m = {
    __call = function(t, ...)
        local params = { ... }
        local func = t.__ori
        return Task.new(function(awaiter)
            local co
            local deferList = {}
            setfenv(func, setmetatable({
                defer = function(deferFunc)
                    deferList[#deferList + 1] = deferFunc
                end,
                await = function(p, name)
                    local temp = {}
                    local cache = temp
                    local baseResume = function(ret, err)
                        cache = { ret = ret, err = err }
                    end
                    local proxyResume = function(ret, err)
                        return baseResume(ret, err)
                    end
                    name = name or ''
                    if type(p) == 'table' then
                        p = p
                    elseif type(p) == 'function' then
                        p = Task.new(p)
                    else
                        return p
                    end
                    p:await(Awaiter.new {
                        onSuccess = function(o)
                            proxyResume(o)
                        end,
                        onError = function(e)
                            proxyResume(nil, e)
                        end,
                    })
                    if cache ~= temp then
                        if cache.err ~= nil then
                            error(cache.err)
                        end
                        return cache.ret
                    end
                    baseResume = function(ret, err)
                        coroutine.resume(co, ret, err)
                    end
                    local ret, err = coroutine.yield()
                    if err then
                        error(err)
                    end
                    return ret
                end,
            }, { __index = _G }))
            co = coroutine.create(function()
                try {
                    function()
                        local ret = func(unpack(params))
                        try {
                            function()
                                for i = #deferList, 1, -1 do
                                    deferList[i]()
                                end
                                deferList = {}
                            end
                        }
                        awaiter:onSuccess(ret)
                    end,
                    catch = function(ex)
                        try {
                            function()
                                for i = #deferList, 1, -1 do
                                    deferList[i]()
                                end
                                deferList = {}
                            end
                        }
                        awaiter:onError(ex)
                    end,
                    finally = function(ok, ex)
                    end
                }
                return 'async-await'
            end)
            coroutine.resume(co)
        end)
    end
}

M.async = function(func)
    return setmetatable({ __type = 'asyncFunction', __ori = func }, m)
end

return M
