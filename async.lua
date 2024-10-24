local dev = false
-- dev = true
local function dev_print(...)
    if dev then print(...) end
end

---@class Promise
---@field state "pending" | "fulfilled" | "rejected"
---@field thread thread
---@field value any


local function sync(func)
    local thread = coroutine.create(func)
    -- skip async function announcment
    coroutine.resume(thread)
    -- get async promise
    local _, promise = coroutine.resume(thread)
    -- start thread and run to completion
    while true do
        if coroutine.status(promise.thread) == "dead" then
            break
        end
        coroutine.resume(promise.thread)
    end
end

---@generic T
---@generic K
---@param func fun(...: T): K?
---@param manual? boolean
---@return fun(...: T): Promise<K>
local function async(func, manual)
    return function (...)
        dev_print("Async function called!")
        local params = {...}
        local sync_wrapper = function () return func(unpack(params)) end
        local sync_thread = coroutine.create(sync_wrapper)

        if manual then
            ---@type Promise
            local promise = {
                state = "pending",
                thread = sync_thread
            }
            coroutine.yield(promise, "async")
            return promise
        end

        local function async_controller()
            dev_print("Starting async function controller...")

            ---@type table<thread, Promise>
            local promises = {}
            ---@type thread[]
            local pending = {}
            local awaited = nil
            local toreturn = nil
            ::resumesync::
            while true do
                dev_print("Resuming synchronous code...")
                local yielded = { coroutine.resume(sync_thread, toreturn and unpack(toreturn)) }
                dev_print("Yield happened!")
                local status = table.remove(yielded, 1)
                if not status then print("a error (sync): " .. yielded[1]) end

                if coroutine.status(sync_thread) == "dead" then
                    dev_print("Sync code returned!")
                    return unpack(yielded)
                end
                ---@type Promise
                local promise = table.remove(yielded, 1)
                local message = table.remove(yielded, 1)

                if toreturn ~= nil then toreturn = nil end

                if message == "async" then
                    dev_print("Recieved async function!")
                    table.insert(pending, promise.thread)
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
                    dev_print("something else returned. what the fuck")
                end
            end
            dev_print("Running promise threads...")
            while #pending > 0 do
                local toremove = nil
                for i = 1, #pending do
                    local thread = pending[i]
                    local yielded = { coroutine.resume(thread) }
                    dev_print("Promise thread yielded...")
                    local status = table.remove(yielded, 1)
                    if not status then print("a error (async): " .. yielded[1]) end

                    if coroutine.status(thread) == "dead" then
                        dev_print("Promise fulfilled.")
                        local promise = promises[thread]
                        promise.state = "fulfilled"
                        promise.value = yielded
                        if awaited and promise == awaited then
                            dev_print("Awaited promise fulfilled!")
                            table.remove(pending, i)
                            awaited = nil
                            toreturn = yielded
                            goto resumesync
                        end
                        toremove = i
                    end
                end
                if toremove then table.remove(pending, toremove) end
                coroutine.yield()
            end
        end
        local async_thread = coroutine.create(async_controller)
        ---@type Promise
        local promise = {
            state = "pending",
            thread = async_thread
        }
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

return {
    async = async,
    await = await,
    sync = sync
}
