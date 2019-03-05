local M = {}
local coroutine = _G.coroutine
local setmetatable = _G.setmetatable
local setfenv = _G.setfenv
local type = _G.type

local DEBUG_MODE = true
local log = DEBUG_MODE and _G.print
log('DEBUG_MODE OPEN')
local task_metatable = {
    __call = function(t, waiter)
        return t.__ori(waiter)
    end,
    wait = function(t, waiter)
        t.__ori(waiter)
    end
}
task_metatable.__index = task_metatable
local task = {
    new = function(func)
        return setmetatable({__ori = func, __type = 'task'},task_metatable)
    end
}
local m = {
    __call = function(t,value)
        --return a task
        return task.new(function(waiter)
            local co
            local resume = function(...)
                return coroutine.resume(co,...)
            end
            local func = t.__ori
            setfenv(func, setmetatable({
                await = function(p)
                    log("await co: ",co)
                    log(p)
                    if(type(p)=='table' and p.__type=='task')then
                        p:wait{
                            onSuccess = resume,
                            onError = function(e)
                                log("---")
                                log(e)
                                log("---")
                            end
                        }
                        return coroutine.yield()
                    else
                        return p
                    end
                end,
            },{__index = _G}))
            co = coroutine.create(function()
                log("child task start!")
                local ret = func(value)
                log('child task end!','result:(',ret,')')
                waiter.onSuccess(ret)
            end)
            resume()
        end)
    end
}

M.task = task

M.async = function(func)
    log('async')
    return setmetatable({__type = 'asyncfunction', __ori = func}, m)
end

M.await = function(task)
    task:wait{
        onSuccess = function(result)
            log('final result: ', result)
        end
    }
end
return M
