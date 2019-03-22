local Awaiter = require('src.Awaiter')
local Task = require('src.Task')
local try = require('libs.tryCatchFinally').try
local coroutine = _G.coroutine
local setmetatable = _G.setmetatable
local setfenv = _G.setfenv
local type = _G.type
local DEBUG_MODE = false
local log = DEBUG_MODE and print or function() end
log('DEBUG_MODE OPEN')

local M = {}
local m = {
    __call = function(t,...)
        local params = {...}
        log('async call: ',t,...)
        --return a task
        local func = t.__ori
        return Task.new(function(awaiter)
            local co
			local deferList = {}
            setfenv(func, setmetatable({
				defer = function(func)
					deferList[#deferList+1] = func
				end,
                await = function(p,name)
                    local temp = {}
                    local cache = temp
                    local baseResume = function(...)
                        log('sync resume: ',...)
                        cache = {...}
                    end
                    local proxyResume = function(...)
                        return baseResume(...)
                    end
                    name = name or ''
                    if(type(p)=='table' and p.__type=='Task')then
                        log('- await a taskTable -')
                        p = p
                    elseif(type(p)=='function')then
                        log('- await a taskFunction -')
                        p = Task.new(p)
                    else
                        log('?')
                        return p
                    end
                    p:await(Awaiter.new{
                        onSuccess = proxyResume,
                        onError = function(e)
                            --if(onError)then
                            --    onError(e)
                            --end
                            print('???',name,e)
                            --awaiter:onError(e)
                            error(e)
                        end
                    })
                    if(cache~=temp)then
                        return unpack(cache)
                    end
                    baseResume = function(...)
                        log('async resume: ',...)
                        local result, msg = coroutine.resume(co,...)
                        log('result: ',result, msg)
                    end
                    log('yield()')
                    return coroutine.yield('async-await')
                end,
            },{__index = _G}))
            co = coroutine.create(function()
                try{
                    function()
                        log('child task start!')
                        local ret = func(unpack(params))
                        log('child task end!','result:(',ret,')')
                        try{
                            function()
                                for i = #deferList,1,-1 do
                                    deferList[i]()	
                                end
                                deferList = {}
                            end
                        }
                        awaiter:onSuccess(ret)
                    end,
                    catch = function(ex)
                        try{
                            function()
                                for i = #deferList,1,-1 do
                                    deferList[i]()	
                                end		
								deferList = {}
                            end
                        }
                        log('caught ex', ex)
                        awaiter:onError(ex)
                    end,
					finally = function(ok,ex)
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
    return setmetatable({__type = 'asyncFunction', __ori = func}, m)
end

M.await = function(base, onSuccess, onError)
    if(type(base)=='table' and base.__type=='Task')then
        log('- task -')
        base = base
    elseif(type(base)=='function')then
        log('- taskFunction -')
        base = Task.new(base)
    else
        error('must be task or taskFunction')
    end
    base:await(Awaiter.new{
        onSuccess = onSuccess or function(result)
            -- do nothing
        end,
        onError = onError or error
    })
end
return M
