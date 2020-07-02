local cartridge = require('cartridge')
local log = require('log')
local json = require('json')
local rlog = require('app.roles.request_log')


local function api_error(status_code, message)
    log.error(message)
    return {
        status = status_code,
        body = string.format('{"error": "%s"}', message)
    }
end


local function add_value(request)
    rlog.log()
    if not rlog.check_rps() then
        return api_error(429, 'Rate limit exceeded')
    end

    local ok, data = pcall(request.json, request)
    if not ok or data.key == nil or data.value == nil then
        return api_error(400, 'Invalid JSON')
    end
    if type(data.key) ~= 'string' then
        return api_error(400, 'Invalid key')
    end
    ok, data = pcall(box.space.items.insert, box.space.items, {data.key, json.encode(data.value)})
    if not ok then
        return api_error(409, 'Already exists')
    end
    log.info(string.format('Item added. Key: %s, value: %s', data.key, data.value))
    return {
        status = 201,
        body = ''
    }
end

local function edit_value(request)
    rlog.log()
    if not rlog.check_rps() then
        return api_error(429, 'Rate limit exceeded')
    end

    local key = request:stash('key')
    local ok, data = pcall(request.json, request)
    if not ok or data.value == nil then
        return api_error(400, 'Invalid JSON')
    end
    ok, data = pcall(box.space.items.update, box.space.items, key, { {"=", 2, json.encode(data.value)}})
    if data == nil then
        return api_error(404, 'Not found')
    end
    log.info(string.format('Item edited. Key: %s, value: %s', key, data.value))
    return {
        status = 201,
        body = ''
    }
end

local function get_value(request)
    rlog.log()
    if not rlog.check_rps() then
        return api_error(429, 'Rate limit exceeded')
    end

    local key = request:stash('key')
    local ok, item = pcall(box.space.items.get, box.space.items, key)
    if item == nil then
        return api_error(404, 'Not found')
    end
    log.info(string.format('Item requested. Key: %s, value: %s', key, item[2]))
    return {
        status = 200,
        body = item[2]
    }
end

local function delete_value(request)
    rlog.log()
    if not rlog.check_rps() then
        return api_error(429, 'Rate limit exceeded')
    end

    local key = request:stash('key')
    local ok, item = pcall(box.space.items.delete, box.space.items, key)
    if item == nil then
        return api_error(404, 'Not found')
    end
    log.info(string.format('Item deleted. Key: %s, value: %s', key, item[2]))
    return {
        status = 200,
        body = ''
    }
end


local function init(opts) -- luacheck: no unused args

    box.once('init', function()
            box.schema.space.create('items')
            box.space.items:format({
                {name = "key", type = "string"},
                {name = "value", type = "string"},
            })
            box.space.items:create_index(
                'primary', {type = 'hash', parts = {'key'}}
            )

            request_log:init()
    end)

    local httpd = cartridge.service_get('httpd')
    httpd:route(
        {method = 'POST', path = '/kv'}, add_value
    )
    httpd:route(
        {method = 'PUT', path = '/kv/:key'}, edit_value
    )
    httpd:route(
        {method = 'GET', path = '/kv/:key'}, get_value
    )
    httpd:route(
        {method = 'DELETE', path = '/kv/:key'}, delete_value
    )

    return true
end

return {
    role_name = 'app.roles.api',
    init = init
}
