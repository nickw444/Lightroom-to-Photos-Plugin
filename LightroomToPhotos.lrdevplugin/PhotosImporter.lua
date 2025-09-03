local LrTasks = import 'LrTasks'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local logger = require 'Logger'

local M = {}

local function shell_quote(path)
    if not path then return "''" end
    return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

local function write_text_file(path, content)
    local f, err = io.open(path, 'w')
    if not f then return false, err end
    f:write(content)
    f:close()
    return true
end

local function runAppleScript(source)
    local tempDir = LrPathUtils.getStandardFilePath('temp')
    local path = LrPathUtils.child(tempDir, string.format('ltp-%d.applescript', math.random(1, 10^9)))
    local ok, err = write_text_file(path, source)
    if not ok then
        logger:warn('Failed to write AppleScript: ' .. tostring(err))
        return false, 'Failed to write AppleScript file: ' .. tostring(err)
    end
    local cmd = '/usr/bin/osascript ' .. shell_quote(path)
    logger:trace('PhotosImporter osascript: ' .. cmd)
    local rc = LrTasks.execute(cmd)
    if LrFileUtils.exists(path) then
        LrFileUtils.delete(path)
    end
    return rc == 0, rc
end

function M.ensureAutomationPermission()
    return runAppleScript([[tell application "Photos" to activate]])
end

-- Import a list of POSIX paths (strings) into Photos, optionally to an album.
function M.import(paths, albumName)
    if not paths or #paths == 0 then
        return false, 'No paths provided'
    end

    local items = {}
    for i = 1, #paths do
        items[#items + 1] = 'POSIX file ' .. string.format('%q', paths[i])
    end
    local listLiteral = '{ ' .. table.concat(items, ', ') .. ' }'

    local albumLiteral = 'missing value'
    if albumName and albumName ~= '' then
        albumLiteral = string.format('%q', albumName)
    end

    local script = [[
        on ensure_album(albumName)
            tell application "Photos"
                if albumName is missing value then return missing value
                set targetAlbum to missing value
                repeat with a in albums
                    if name of a is albumName then set targetAlbum to a
                end repeat
                if targetAlbum is missing value then set targetAlbum to make new album named albumName
                return targetAlbum
            end tell
        end ensure_album

        tell application "Photos"
            activate
            set targetAlbum to my ensure_album(ALBUM_NAME)
            set theFiles to FILE_LIST
            repeat with f in theFiles
                try
                    set mediaItems to import f skip check duplicates false
                    if targetAlbum is not missing value then add mediaItems to targetAlbum
                on error errMsg
                    -- ignore per-file error
                end try
            end repeat
        end tell
    ]]

    script = script:gsub('ALBUM_NAME', albumLiteral):gsub('FILE_LIST', listLiteral)
    local ok, rc = runAppleScript(script)
    logger:info('Photos import rc=' .. tostring(rc) .. ' ok=' .. tostring(ok) .. ' count=' .. tostring(#paths) .. ' album=' .. tostring(albumName))
    return ok, rc
end

-- Attempts to reveal the given album in Photos. Creates it if missing.
function M.showAlbum(albumName)
    if not albumName or albumName == '' then return false, 'No album name' end
    local script = [[
        on ensure_album(albumName)
            tell application "Photos"
                if albumName is missing value then return missing value
                set targetAlbum to missing value
                repeat with a in albums
                    if name of a is albumName then set targetAlbum to a
                end repeat
                if targetAlbum is missing value then set targetAlbum to make new album named albumName
                return targetAlbum
            end tell
        end ensure_album

        tell application "Photos"
            activate
            set targetAlbum to my ensure_album(ALBUM_NAME)
            try
                reveal targetAlbum
            on error
                -- Best effort only; some Photos versions may not support reveal
            end try
        end tell
    ]]
    script = script:gsub('ALBUM_NAME', string.format('%q', albumName))
    local ok, rc = runAppleScript(script)
    logger:info('Photos showAlbum rc=' .. tostring(rc) .. ' ok=' .. tostring(ok) .. ' album=' .. tostring(albumName))
    return ok, rc
end

return M

