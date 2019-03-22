local AsyncAwaitLib = require('src.AsyncAwait')
_G.async = AsyncAwaitLib.async
_G.await = AsyncAwaitLib.await
local TryCatchLib = require('libs.tryCatchFinally')
TryCatchLib.xpcall = require('libs.coxpcall').xpcall
local try = TryCatchLib.try

-- replace delay-func of your platform here
local timer_performWithDelay = function(ms,callback,count)
    -- such as I implement it on coronaSdk:
    timer.performWithDelay(ms,callback,count)
end
local function delay(ms)
    return function(awaiter)
        timer_performWithDelay(ms, function(_)
            awaiter:onSuccess('delay result')
        end)
    end
end

local func_0 = async(function()
    print('[func_0]', 'delay 0.5s start!')
    await(delay(500))
    print('[func_0]', 'delay 0.5s end!')
    defer(function()
        print('--- defer ---')
    end)
    return 1000
end)

local func_1 = async(function(...)
    try{
        function()
            local delayTime = await(func_0())
            print('delay: ',delayTime,'ms')
            error('throw a exception in try-catch')
            await(delay(delayTime))
        end,
        catch = function(e)
            print('ex caught!',e)
        end
    }
    return "I'm async-function"
end)
local func_2 = async(function(name)
    print('input: ', name)
    return "I'm sync-function"
end)

await(func_2('cwd'),print,print)
print('-------------------------------------')
await(func_1('cwd'),print,print)
-- await(func_2('cwd'))
-- print('-------------------------------------')
-- await(func_0('cwd'))
