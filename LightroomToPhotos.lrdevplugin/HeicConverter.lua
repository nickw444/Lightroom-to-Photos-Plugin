local LrTasks = import 'LrTasks'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local logger = require 'Logger'

local M = {}

local function shell_quote(s)
    if s == nil then return "''" end
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function ensure_dest_path(destPath)
    if not destPath then return nil end
    local parent = LrPathUtils.parent(destPath)
    if parent and not LrFileUtils.exists(parent) then
        LrFileUtils.createAllDirectories(parent)
    end
    return destPath
end

-- Convert an input image to HEIC using macOS sips.
-- opts = { quality = 0.75, destPath = optional }
function M.convert(srcPath, opts)
    opts = opts or {}
    local q = tonumber(opts.quality) or 0.75
    if q < 0 then q = 0 end
    if q > 1 then q = 1 end

    local destPath = ensure_dest_path(opts.destPath)
    if not destPath then
        local base = LrPathUtils.leafName(srcPath or 'file')
        local stem = base:gsub('%.[^%.]+$', '')
        local dir = LrPathUtils.parent(srcPath) or LrPathUtils.getStandardFilePath('temp')
        destPath = LrPathUtils.child(dir, stem .. '.HEIC')
    end

    local percent = math.floor(q * 100 + 0.5)
    if percent < 1 then percent = 1 end
    if percent > 100 then percent = 100 end

    local cmd = "/usr/bin/sips -s format heic -s formatOptions " .. tostring(percent) ..
        " " .. shell_quote(srcPath) .. " --out " .. shell_quote(destPath)

    logger:trace('HeicConverter: ' .. cmd)
    local rc = LrTasks.execute(cmd)
    if rc == 0 and LrFileUtils.exists(destPath) then
        logger:trace('HeicConverter: success -> ' .. tostring(destPath))
        return true, destPath
    else
        logger:warn('HeicConverter: failed rc=' .. tostring(rc))
        return false, 'sips failed rc=' .. tostring(rc)
    end
end

return M
