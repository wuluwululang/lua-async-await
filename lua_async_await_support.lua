local M = {}
local DEBUG_MODE = false
local log = function(...)
    if(DEBUG_MODE)then
        print(...)
    end
end
M.async = function(func)
    return function(value)
        return function(waiter)
            local co
            local resume = function(...)
                return coroutine.resume(co,...)
            end
            setfenv(func, setmetatable({
                await = function(p)
                    log("await co: ",co)
                    log(p)
                    if(type(p)=='function')then
                        p{
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
        end
    end
end

M.await = function(task)
    task{
        onSuccess = function(result)
            log('final result: ', result)
        end
    }
end