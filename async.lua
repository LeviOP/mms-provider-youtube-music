local inspect = require("inspect")
local dev = false
-- dev = true
local function dev_print(...)
    if dev then print(...) end
end

-- local dbg = require("debugger")

local function sync(func)
    local thread = coroutine.create(func)
    -- skip async function announcment
    coroutine.resume(thread)
    -- get async promise
    ---@type boolean, Promise
    local _, promise = coroutine.resume(thread)
    -- start thread and run to completion
    while true do
        if coroutine.status(promise.thread) == "dead" then
            break
        end
        local status, error = coroutine.resume(promise.thread, function (...)
            promise.state = "fulfilled"
            promise.value = ...
            coroutine.yield()
        end)
        if not status then print("A error happened at the top level: " .. error) end
    end
end

---@class Promise
---@field state "pending" | "fulfilled" | "rejected"
---@field thread thread
---@field value any
---@field name string?
local Promise = {}
Promise.__index = Promise

---@param func fun(resolve: function): Promise
function Promise:new(func, name)
    local promise = {}
    setmetatable(promise, Promise)
    promise.state = "pending"
    promise.thread = coroutine.create(func)
    promise.name = name
    return promise
end

---@generic T
---@generic K
---@param func fun(...: T): K?
---@return fun(...: T): Promise<K>
local function async(func, name)
    return function (...)
        dev_print("Async function called!")
        local params = {...}
        local sync_wrapper = function () return func(unpack(params)) end
        local sync_thread = coroutine.create(sync_wrapper)

        local function async_controller(resolve)
            dev_print("Starting async function controller...")

            ---@type table<thread, Promise>
            local promises = {}
            ---@type thread[]
            local running = {}
            local awaited = nil
            local toreturn = nil
            ::resumesync::
            while true do
                dev_print("Resuming synchronous code...")
                local yielded = { coroutine.resume(sync_thread, toreturn) }
                dev_print("Yield happened!")
                local status = table.remove(yielded, 1)
                if not status then print("a error (sync): " .. yielded[1]) end

                if coroutine.status(sync_thread) == "dead" then
                    dev_print("Sync code returned!")
                    resolve(unpack(yielded))
                    break
                end
                ---@type Promise
                local promise = table.remove(yielded, 1)
                local message = table.remove(yielded, 1)

                if toreturn ~= nil then toreturn = nil end

                if message == "async" then
                    dev_print("Recieved async function!")
                    table.insert(running, promise.thread)
                    promises[promise.thread] = promise
                elseif message == "await" then
                    dev_print("Received await! Promise: ", promise.state)
                    if promise.state == "fulfilled" then
                        dev_print("Awaited promise has already been fulfilled!")
                        toreturn = promise.value
                        goto resumesync
                    end
                    awaited = promise
                    break
                else
                    dev_print("something else returned. what the fuck:", message)
                end
            end
            dev_print("Running promise threads...")
            while #running > 0 do
                -- Terible hack that I hate
                local removed = 0
                for i = 1, #running do
                    local thread = running[i-removed]
                    local promise = promises[thread]
                    dev_print("Running promise thread:", promise.name)

                    local r = function (...)
                        dev_print("I am resolving.", promise.name)
                        promise.state = "fulfilled"
                        promise.value = ...
                        coroutine.yield()
                    end
                    local yielded = { coroutine.resume(thread, r) }
                    if coroutine.status(thread) == "dead" then
                        dev_print("Promise thread is dead")
                        table.remove(running, i-removed)
                        removed = removed + 1
                    end

                    dev_print("Promise thread yielded...")
                    local status = table.remove(yielded, 1)
                    if not status then print("a error (async): " .. yielded[1], promise.name) end

                    if awaited and promise.state == "fulfilled" and promise == awaited then
                        dev_print("Awaited promise is fulfilled!")
                        awaited = nil
                        toreturn = promise.value
                        goto resumesync
                    end

                end
                coroutine.yield()
            end
        end
        local promise = Promise:new(async_controller, name)
        coroutine.yield(promise, "async")
        return promise
    end
end


---@generic T
---@param promise Promise<`T`>
---@return T
local function await(promise)
    return coroutine.yield(promise, "await")
end

-- local function await_all(promises)
--     for _, value in pairs(promises) do
--         await(promise)
--     end
-- end

return {
    async = async,
    await = await,
    sync = sync,
    Promise = Promise
}
