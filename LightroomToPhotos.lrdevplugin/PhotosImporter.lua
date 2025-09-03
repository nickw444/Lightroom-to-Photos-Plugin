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

-- Import a list of POSIX paths (strings) into Photos, optionally to an album path like 'Lightroom/Edited'.
function M.import(paths, albumPath)
    if not paths or #paths == 0 then
        return false, 'No paths provided'
    end

    local items = {}
    for i = 1, #paths do
        items[#items + 1] = 'POSIX file ' .. string.format('%q', paths[i])
    end
    local listLiteral = '{ ' .. table.concat(items, ', ') .. ' }'

    local albumPathLiteral = 'missing value'
    if albumPath and albumPath ~= '' then
        albumPathLiteral = string.format('%q', albumPath)
    end

    local script = [[
        on ensure_album_path(albumPath)
            tell application "Photos"
                if albumPath is missing value then return missing value
                set AppleScript's text item delimiters to "/"
                set parts to text items of albumPath
                set AppleScript's text item delimiters to ""
                if (count of parts) is 0 then return missing value
                -- locate first non-empty as root
                set idx to 1
                repeat while idx ≤ (count of parts) and (item idx of parts) is ""
                    set idx to idx + 1
                end repeat
                if idx > (count of parts) then return missing value
                set rootName to item idx of parts
                set idx to idx + 1

                -- find or create top-level folder
                set targetFolder to missing value
                try
                    repeat with f in folders
                        if name of f is rootName then set targetFolder to f
                    end repeat
                end try
                if targetFolder is missing value then set targetFolder to make new folder named rootName

                -- traverse middle folders
                set lastIndex to (count of parts)
                repeat while idx < lastIndex
                    set partName to item idx of parts
                    if partName is not "" then
                        set nextFolder to missing value
                        try
                            repeat with f in (folders of targetFolder)
                                if name of f is partName then set nextFolder to f
                            end repeat
                        end try
                        if nextFolder is missing value then
                            try
                                set nextFolder to make new folder named partName in targetFolder
                            on error
                                set nextFolder to make new folder named partName
                            end try
                        end if
                        set targetFolder to nextFolder
                    end if
                    set idx to idx + 1
                end repeat

                -- final part is the album name
                set albumName to item lastIndex of parts
                if albumName is "" then return missing value
                set targetAlbum to missing value
                try
                    repeat with a in (albums of targetFolder)
                        if name of a is albumName then set targetAlbum to a
                    end repeat
                end try
                if targetAlbum is missing value then
                    try
                        set targetAlbum to make new album named albumName in targetFolder
                    on error
                        set targetAlbum to make new album named albumName
                    end try
                end if
                return targetAlbum
            end tell
        end ensure_album_path

        tell application "Photos"
            activate
            set targetAlbum to my ensure_album_path(ALBUM_PATH)
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

    script = script:gsub('ALBUM_PATH', albumPathLiteral):gsub('FILE_LIST', listLiteral)
    local ok, rc = runAppleScript(script)
    logger:info('Photos import rc=' .. tostring(rc) .. ' ok=' .. tostring(ok) .. ' count=' .. tostring(#paths) .. ' albumPath=' .. tostring(albumPath))
    return ok, rc
end

-- Attempts to reveal the given album in Photos. Creates it if missing.
function M.showAlbum(albumPath)
    if not albumPath or albumPath == '' then return false, 'No album path' end
    local script = [[
        on ensure_album_path(albumPath)
            tell application "Photos"
                if albumPath is missing value then return missing value
                set AppleScript's text item delimiters to "/"
                set parts to text items of albumPath
                set AppleScript's text item delimiters to ""
                if (count of parts) is 0 then return missing value
                set idx to 1
                repeat while idx ≤ (count of parts) and (item idx of parts) is ""
                    set idx to idx + 1
                end repeat
                if idx > (count of parts) then return missing value
                set rootName to item idx of parts
                set idx to idx + 1
                set targetFolder to missing value
                try
                    repeat with f in folders
                        if name of f is rootName then set targetFolder to f
                    end repeat
                end try
                if targetFolder is missing value then set targetFolder to make new folder named rootName
                set lastIndex to (count of parts)
                repeat while idx < lastIndex
                    set partName to item idx of parts
                    if partName is not "" then
                        set nextFolder to missing value
                        try
                            repeat with f in (folders of targetFolder)
                                if name of f is partName then set nextFolder to f
                            end repeat
                        end try
                        if nextFolder is missing value then
                            try
                                set nextFolder to make new folder named partName in targetFolder
                            on error
                                set nextFolder to make new folder named partName
                            end try
                        end if
                        set targetFolder to nextFolder
                    end if
                    set idx to idx + 1
                end repeat
                set albumName to item lastIndex of parts
                if albumName is "" then return missing value
                set targetAlbum to missing value
                try
                    repeat with a in (albums of targetFolder)
                        if name of a is albumName then set targetAlbum to a
                    end repeat
                end try
                if targetAlbum is missing value then
                    try
                        set targetAlbum to make new album named albumName in targetFolder
                    on error
                        set targetAlbum to make new album named albumName
                    end try
                end if
                return targetAlbum
            end tell
        end ensure_album_path

        tell application "Photos"
            activate
            set targetAlbum to my ensure_album_path(ALBUM_PATH)
            try
                reveal targetAlbum
            on error
            end try
        end tell
    ]]
    script = script:gsub('ALBUM_PATH', string.format('%q', albumPath))
    local ok, rc = runAppleScript(script)
    logger:info('Photos showAlbum rc=' .. tostring(rc) .. ' ok=' .. tostring(ok) .. ' albumPath=' .. tostring(albumPath))
    return ok, rc
end

return M
