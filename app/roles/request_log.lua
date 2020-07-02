local clock = require('clock')


local request_log = {
    init = function()
        box.schema.space.create('request_log')
        box.space.request_log:format({
            {name = "time", type = "number"},
        })
        box.space.request_log:create_index(
            'primary', {type = 'tree', parts = {'time'}}
        )
    end,

    log = function()
        local time = clock.time64()
        box.space.request_log:put{time}
    end,

    rps_limit = 5,

    check_rps = function()
        local time = clock.time64()
        return box.space.request_log:count(time - 10^9, 'GE') <= 5
    end
}

return request_log
