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

define('project.libs.try_catch_finally', function(require, ...)
    local M = {}
    --default xpcall
    M.xpcall = _G.xpcall
    --default errorHandler
    M.errorHandler = function(info)
        local tbl = { info = info, traceback = debug.traceback() }
        local str = tostring(tbl)
        return setmetatable(tbl, { __tostring = function(t)
            return str .. '(use ex.info & ex.traceback to view detail)'
        end })
    end

    function M.try(block)
        local main = block[1]
        local catch = block.catch
        local finally = block.finally
        assert(main, 'main function not found')
        -- try to call it
        local ok, errors = M.xpcall(main, M.errorHandler)
        if not ok then
            -- run the catch function
            if catch then
                catch(errors)
            end
        end

        -- run the finally function
        if finally then
            finally(ok, errors)
        end

        -- ok?
        if ok then
            return errors
        end
    end
    return M
end)

define('project.libs.coxpcall', function(require, ...)
    local copcall
    local coxpcall

    local function isCoroutineSafe(func)
        local co = coroutine.create(function()
            return func(coroutine.yield, function()
            end)
        end)

        coroutine.resume(co)
        return coroutine.resume(co)
    end

    -- No need to do anything if pcall and xpcall are already safe.
    if isCoroutineSafe(pcall) and isCoroutineSafe(xpcall) then
        copcall = pcall
        coxpcall = xpcall
        return { pcall = pcall, xpcall = xpcall, running = coroutine.running }
    end

    -------------------------------------------------------------------------------
    -- Implements xpcall with coroutines
    -------------------------------------------------------------------------------
    local performResume, handleReturnValue
    local oldpcall, oldxpcall = pcall, xpcall
    local pack = table.pack or function(...)
        return { n = select("#", ...), ... }
    end
    local unpack = table.unpack or unpack
    local running = coroutine.running
    local coromap = setmetatable({}, { __mode = "k" })

    handleReturnValue = function(err, co, status, ...)
        if not status then
            return false, err(debug.traceback(co, (...)), ...)
        end
        if coroutine.status(co) == 'suspended' then
            return performResume(err, co, coroutine.yield(...))
        else
            return true, ...
        end
    end

    performResume = function(err, co, ...)
        return handleReturnValue(err, co, coroutine.resume(co, ...))
    end

    local function id(trace, ...)
        return trace
    end

    function coxpcall(f, err, ...)
        local current = running()
        if not current then
            if err == id then
                return oldpcall(f, ...)
            else
                if select("#", ...) > 0 then
                    local oldf, params = f, pack(...)
                    f = function()
                        return oldf(unpack(params, 1, params.n))
                    end
                end
                return oldxpcall(f, err)
            end
        else
            local res, co = oldpcall(coroutine.create, f)
            if not res then
                local newf = function(...)
                    return f(...)
                end
                co = coroutine.create(newf)
            end
            coromap[co] = current
            return performResume(err, co, ...)
        end
    end

    local function corunning(coro)
        if coro ~= nil then
            assert(type(coro) == "thread", "Bad argument; expected thread, got: " .. type(coro))
        else
            coro = running()
        end
        while coromap[coro] do
            coro = coromap[coro]
        end
        if coro == "mainthread" then
            return nil
        end
        return coro
    end

    -------------------------------------------------------------------------------
    -- Implements pcall with coroutines
    -------------------------------------------------------------------------------

    function copcall(f, ...)
        return coxpcall(f, id, ...)
    end

    return { pcall = copcall, xpcall = coxpcall, running = corunning }
end)
define('project.src.async_await', function(require, ...)
    local Awaiter = require('src.Awaiter')
    local Task = require('src.Task')
    local try = require('libs.try_catch_finally').try
    local coroutine = _G.coroutine
    local setmetatable = _G.setmetatable
    local setfenv = _G.setfenv
    local type = _G.type
    local DEBUG_MODE = false
    local log = DEBUG_MODE and print or function()
    end
    log('DEBUG_MODE OPEN')

    local M = {}
    local m = {
        __call = function(t, ...)
            local params = { ... }
            log('async call: ', t, ...)
            --return a task
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
                        local baseResume = function(...)
                            log('sync resume: ', ...)
                            cache = { ... }
                        end
                        local proxyResume = function(...)
                            return baseResume(...)
                        end
                        name = name or ''
                        if (type(p) == 'table' and p.__type == 'Task') then
                            log('- await a taskTable -')
                            p = p
                        elseif (type(p) == 'function') then
                            log('- await a taskFunction -')
                            p = Task.new(p)
                        else
                            log('?')
                            return p
                        end
                        p:await(Awaiter.new {
                            onSuccess = proxyResume,
                            onError = error
                        })
                        if (cache ~= temp) then
                            return unpack(cache)
                        end
                        baseResume = function(...)
                            log('async resume: ', ...)
                            local result, msg = coroutine.resume(co, ...)
                            log('result: ', result, msg)
                        end
                        log('yield()')
                        return coroutine.yield('async-await')
                    end,
                }, { __index = _G }))
                co = coroutine.create(function()
                    try {
                        function()
                            log('child task start!')
                            local ret = func(unpack(params))
                            log('child task end!', 'result:(', ret, ')')
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
                            log('caught ex', ex)
                            awaiter:onError(ex)
                        end,
                        finally = function(_, _)
                            log('!!!!!!! finally !!!!!!')
                        end
                    }
                    return 'async-await'
                end)
                coroutine.resume(co)
            end)
        end
    }

    M.async = function(func)
        log('async')
        return setmetatable({ __type = 'asyncFunction', __ori = func }, m)
    end

    return M
end)
define('project.src.Task', function(require, ...)
    local Awaiter = require('src.Awaiter')
    local try = require('libs.try_catch_finally').try
    local Task
    Task = {
        __needRef = true,
        __call = function(t, awaiter)
            if (type(awaiter) == 'table' and awaiter.__type ~= 'Awaiter') then
                t.__ori(Awaiter.new(awaiter))
            end
            t.__ori(awaiter)
        end,
        await = function(t, awaiter)
            try {
                function()
                    t.__ori(awaiter)
                end,
                catch = function(ex)
                    print('task await ex')
                    awaiter:onError(ex)
                end
            }
        end,
        new = function(base)
            if (type(base) == 'table') then
                return base
            elseif (type(base) == 'function') then
                return setmetatable({ __ori = base, __type = 'Task' }, Task)
            else
                error(base)
            end
        end
    }
    Task.__index = Task
    return Task
end)
define('project.src.Awaiter', function(require, ...)
    return {
        new = function(tbl)
            if (tbl.__type == 'Awaiter') then
                return tbl
            end
            local obj
            obj = {
                __type = 'Awaiter',
                __needRef = true,
                onSuccess = function(_, o)
                    tbl.onSuccess(o)
                end,
                onError = function(_, e)
                    tbl.onError(e)
                end
            }
            return obj
        end
    }
end)
return (function(require, ...)
    require('libs.try_catch_finally').xpcall = require('project.libs.coxpcall').xpcall
    return {
        async = require('src.async_await').async,
        try = require('libs.try_catch_finally').try,
        Task = require('src.Task'),
        Awaiter = require('src.Awaiter'),
    }
end)(_require, unpack(args))
