local coxpcall = require('libs.coxpcall')

return function (block)
    local main = block[1]
    local catch = block.catch
    local finally = block.finally
    assert(main,'main function not found')
    -- try to call it
    local ok, errors = coxpcall.xpcall(main, function(ex)
        local trace -- = debug.traceback()
        ex = type(ex)=='table' and ex or {}
        return { code = ex.code or -1, level= ex.level or 2, type= ex.type or 'unknown', msg = ex.msg or 'unknown error', trace = trace}
    end)
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

