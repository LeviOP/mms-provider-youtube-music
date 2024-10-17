local json = require("json")

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

---@class Playlist
---@field entries Entry[]

---@class Entry
---@field id string

---@param id string
---@return Playlist|nil
local function get_playlist(id)
    local yt_dlp, err = io.popen("yt-dlp -J --flat-playlist \"https://www.youtube.com/playlist?list=\"" .. id, "r")
    if err ~= nil then
        print("There was an error!: " .. err)
        return
    end
    if yt_dlp == nil then
        print("yt_dlp fd was null")
        return
    end

    local output = yt_dlp:read("*a")
    yt_dlp:close()

    local playlist = json.parse(output)
    if playlist == nil then
        print("playlist is nil")
        return
    end
    return playlist ---@diagnostic disable-line
end

local playlist = get_playlist("OLAK5uy_mbt8jYUHkYtq1tRRs1JcX-TjXJ4Fjj4wA")

if playlist == nil then
    print("Error getting playlist")
    return
end

for _, video in ipairs(playlist.entries) do
    print(video.id)
end

local command, err = io.popen("yt-dlp -f bestaudio -o - " .. playlist.entries[1].id .. " | ffmpeg -i pipe:0 -acodec copy -f ogg pipe:1", "r")
if command == nil then
    print("yt-dlp to ffmpeg pipe fd was nil")
    return
end
if err ~= nil then
    print("There was an error!: " .. err)
    return
end

local audio = command:read("*a")
local file = io.open("test.opus", "w")
if file == nil then
    print("Test output fill fd was nil")
    return
end
file:write(audio)
local success = file:close();
if success then
    print("Successfully wrote file!")
else
    print("Couldn't write for some reason :(")
end

-- print("Playlist:" .. dump(playlist))

