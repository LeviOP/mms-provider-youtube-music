local posix = require("posix")
local async_lib = require("async")
local async = async_lib.async
local await = async_lib.await
local Promise = async_lib.Promise

local inspect = require("inspect")

local util = require("utilities")
local pipe = util.pipe;
local fork_execp_piped = util.fork_execp_piped;

local function readout_file(fd)
    local promise = Promise:new(function (resolve)
        local chunks = {}
        local fds = { [fd] = { events = { IN = true } } }
        print("reading out!", fd)
        while true do
            local events = posix.poll(fds, 10)
            -- posix.nanosleep(10000000)
            -- print("reading out!", fd, events
            --     -- ,inspect(fds[fd])
            -- )
            if events > 0 then
                if fds[fd].revents.IN then
                    local chunk = posix.read(fd, 1024)
                    chunks[#chunks + 1] = chunk
                elseif fds[fd].revents.HUP then
                    return resolve(table.concat(chunks))
                elseif fds[fd].revents.NVAL then
                    print("We are reading from an invalid file descriptor:", fd, #chunks)
                    return resolve(table.concat(chunks))
                end
            else
                coroutine.yield()
            end
        end
    end, "readout_file")
    coroutine.yield(promise, "async")
    return promise
end

local function async_wait(pid)
    local promise = Promise:new(function (resolve)
        while true do
            local _, _, status = posix.wait(pid, posix.WNOHANG)
            if status == nil then
                coroutine.yield()
            else
                return resolve(status)
            end
        end
    end, "async_wait")
    coroutine.yield(promise, "async")
    return promise
end

---@param id string
---@return string|nil
local download_video = async(function(id)
    local yt_dlp_to_ffmpeg_pipe = pipe()
    local yt_dlp_stderr_pipe = pipe()

    local yt_dlp = fork_execp_piped("yt-dlp", {"-f", "bestaudio", "-o", "-", id}, yt_dlp_to_ffmpeg_pipe[2], yt_dlp_stderr_pipe[2])
    posix.close(yt_dlp_to_ffmpeg_pipe[2])
    posix.close(yt_dlp_stderr_pipe[2])

    -- print(inspect(yt_dlp_stderr_pipe))
    local yt_dlp_stderr = readout_file(yt_dlp_stderr_pipe[1])

    local ffmpeg_stdout_pipe = pipe()
    local ffmpeg_stderr_pipe = pipe()

    local ffmpeg = fork_execp_piped("ffmpeg", {"-i", "pipe:0", "-acodec", "copy", "-f", "ogg", "pipe:1"}, ffmpeg_stdout_pipe[2], ffmpeg_stderr_pipe[2], yt_dlp_to_ffmpeg_pipe[1])
    posix.close(ffmpeg_stdout_pipe[2])
    posix.close(ffmpeg_stderr_pipe[2])

    -- print(inspect(ffmpeg_stdout_pipe))
    local ffmpeg_stdout = readout_file(ffmpeg_stdout_pipe[1])
    -- print(inspect(ffmpeg_stderr_pipe))
    local ffmpeg_stderr = readout_file(ffmpeg_stderr_pipe[1])

    local yt_dlp_status = await(async_wait(yt_dlp))
    posix.close(yt_dlp_stderr_pipe[1])
    if yt_dlp_status ~= 0 then
        print("yt-dlp exited with status " .. yt_dlp_status .. ". stderr:\n" .. await(yt_dlp_stderr))
        return
    end

    local ffmpeg_status = await(async_wait(ffmpeg))
    posix.close(ffmpeg_stdout_pipe[1])
    posix.close(ffmpeg_stderr_pipe[1])


    if ffmpeg_status ~= 0 then
        print("ffmpeg exited with status " .. ffmpeg_status .. ". stderr:\n" .. await(ffmpeg_stderr))
        return
    end

    print("finished downloading "..id)
    return await(ffmpeg_stdout)
end, "download_video")

---@generic T
---@generic R
---@param tbl `T`[]
---@param f fun(T): `R`
---@return R
local function map(tbl, f)
    local t = {}
    for k, v in pairs(tbl) do
        t[k] = f(v)
    end
    return t
end

local main = async(function ()
    local get_playlist = require("playlist")

    local playlist = get_playlist("OLAK5uy_n9ySxVzjUiRuj6D1p78Icw3Od_yzjZM_4")

    if playlist == nil then
        print("Error getting playlist")
        return
    end

    print("Successfully loaded playlist")

    local videos = map(playlist.entries, async(function (entry)
        local video = await(download_video(entry.id))
        if video == nil then
            print("Something went wrong while downloading \"" .. entry.title .. "\"")
            return
        end
        local filename = entry.title .. ".opus"
        local file, err = io.open("output/" .. filename, "w")
        if file == nil then
            print("Failed to open file: " .. err)
            return
        end
        file:write(video)
        if file:close() then
            print("Successfully wrote " .. filename .. "!")
        else
            print("Couldn't write for some reason :(")
        end
    end))

    map(videos, function (promise)
        return await(promise)
    end)

    -- local entry = playlist.entries[1]
    -- local video = await(download_video(entry.id))
end, "main")

async_lib.sync(main)

-- for _, entry in ipairs(playlist.entries) do
--     local video = download_video(entry.id)
--     if video == nil then
--         print("Something went wrong while downloading \"" .. entry.title .. "\"")
--         goto continue
--     end
--     local file, err = io.open("output/" .. entry.title .. ".opus", "w")
--     if file == nil then
--         print("Failed to open file: " .. err)
--         goto continue
--     end
--     file:write(video)
--     if file:close() then
--         print("Successfully wrote file!")
--     else
--         print("Couldn't write for some reason :(")
--     end
--     ::continue::
-- end
