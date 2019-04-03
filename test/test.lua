local lib = require('build.asynclib')
local try = lib.try
_G.async = lib.async
local Task = lib.Task
local Awaiter = lib.Awaiter

-- replace delay-func of your platform here
local timer_performWithDelay = function(ms, callback, count)
    -- implementing it on coronaSdk:
    timer.performWithDelay(ms, callback, count)
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
    try {
        function()
            local delayTime = await(func_0())
            print('delay: ', delayTime, 'ms')
            error('throw a exception in try-catch')
            await(delay(delayTime))
        end,
        catch = function(e)
            print('ex caught!', e)
        end
    }
    return "I'm async-function"
end)
local func_2 = async(function(name)
    print('input: ', name)
    return "I'm sync-function"
end)

func_2('cwd'):await(Awaiter.new { onSuccess = print, onError = print })
print('-------------------------------------')
func_1('cwd'):await(Awaiter.new { onSuccess = print, onError = print })
-- await(func_2('cwd'))
-- print('-------------------------------------')
-- await(func_0('cwd'))
