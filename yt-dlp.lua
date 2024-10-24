local json = require("json")
local posix = require("posix")

--[[ local function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end ]]

local function fork_execp_piped(command, args, stdout_fd, stderr_fd, stdin_fd)
    local pid = posix.fork()
    if pid == 0 then
        if stdout_fd then
            posix.dup2(stdout_fd, posix.STDOUT_FILENO)
            posix.close(stdout_fd)
        end
        if stderr_fd then
            posix.dup2(stderr_fd, posix.STDERR_FILENO)
            posix.close(stderr_fd)
        end
        if stdin_fd then
            posix.dup2(stdin_fd, posix.STDIN_FILENO)
            posix.close(stdin_fd)
        end

        -- Replace the child process with the command
        posix.execp(command, args)
        print("THERE HAS BEEN A TERRIBLE FAILURE! KILLING FORK...")
        posix._exit(1)
    end
    return pid
end

local function pipe()
    local pipe_r, pipe_w = posix.pipe()
    return { pipe_r, pipe_w }
end

local function readout_file(fd)
    local output = {}
    while true do
        local chunk = posix.read(fd, 1024)
        if not chunk or #chunk == 0 then break end
        output[#output + 1] = chunk
    end
    return table.concat(output)
end

---@param id string
---@return string|nil
local function download_video(id)
    local yt_dlp_to_ffmpeg_pipe = pipe()
    local yt_dlp_stderr_pipe = pipe()

    local yt_dlp = fork_execp_piped("yt-dlp", {"-f", "bestaudio", "-o", "-", id}, yt_dlp_to_ffmpeg_pipe[2], yt_dlp_stderr_pipe[2])
    posix.close(yt_dlp_to_ffmpeg_pipe[2])
    posix.close(yt_dlp_stderr_pipe[2])

    local ffmpeg_stdout_pipe = pipe()
    local ffmpeg_stderr_pipe = pipe()

    local ffmpeg = fork_execp_piped("ffmpeg", {"-i", "pipe:0", "-acodec", "copy", "-f", "ogg", "pipe:1"}, ffmpeg_stdout_pipe[2], ffmpeg_stderr_pipe[2], yt_dlp_to_ffmpeg_pipe[1])
    posix.close(ffmpeg_stdout_pipe[2])
    posix.close(ffmpeg_stderr_pipe[2])

    local ffmpeg_stdout = readout_file(ffmpeg_stdout_pipe[1])
    posix.close(ffmpeg_stdout_pipe[1])

    local _, _, yt_dlp_status = posix.wait(yt_dlp)
    local yt_dlp_stderr = readout_file(yt_dlp_stderr_pipe[1])
    posix.close(yt_dlp_stderr_pipe[1])
    if yt_dlp_status ~= 0 then
        print("yt-dlp exited with status " .. yt_dlp_status .. ". stderr:\n" .. yt_dlp_stderr)
        return
    end

    local _, _, ffmpeg_status = posix.wait(ffmpeg)
    local ffmpeg_stderr = readout_file(ffmpeg_stderr_pipe[1])
    posix.close(ffmpeg_stderr_pipe[1])

    if ffmpeg_status ~= 0 then
        print("ffmpeg exited with status " .. ffmpeg_status .. ". stderr:\n" .. ffmpeg_stderr)
        return
    end

    return ffmpeg_stdout
end

---@class Playlist
---@field entries Entry[]

---@class Entry
---@field id string
---@field title string

---@param id string
---@return Playlist|nil
local function get_playlist(id)
    local stdout_pipe = pipe()
    local stderr_pipe = pipe()

    local yt_dlp = fork_execp_piped("yt-dlp", {"-J", "--flat-playlist", "https://www.youtube.com/playlist?list=" .. id}, stdout_pipe[2], stderr_pipe[2])
    posix.close(stdout_pipe[2])
    posix.close(stderr_pipe[2])

    local _, _, status = posix.wait(yt_dlp)
    local stdout = readout_file(stdout_pipe[1])
    posix.close(stdout_pipe[1])
    local stderr = readout_file(stderr_pipe[1])
    posix.close(stderr_pipe[1])

    if status ~= 0 then
        print("yt-dlp errored while fetching playlist data:\n" .. stderr)
    end

    ---@type Playlist|nil
    local playlist = json.parse(stdout) ---@diagnostic disable-line
    if playlist == nil then
        print("playlist is nil")
        return
    end

    return playlist
end

local playlist = get_playlist("OLAK5uy_n9ySxVzjUiRuj6D1p78Icw3Od_yzjZM_4")

if playlist == nil then
    print("Error getting playlist")
    return
end

for _, entry in ipairs(playlist.entries) do
    local video = download_video(entry.id)
    if video == nil then
        print("Something went wrong while downloading \"" .. entry.title .. "\"")
        goto continue
    end
    local file, err = io.open("output/" .. entry.title .. ".opus", "w")
    if file == nil then
        print("Failed to open file: " .. err)
        goto continue
    end
    file:write(video)
    if file:close() then
        print("Successfully wrote file!")
    else
        print("Couldn't write for some reason :(")
    end
    ::continue::
end
