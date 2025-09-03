local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'
local logger = require 'Logger'

local M = {}

local function nonzero(v)
    return type(v) == 'number' and math.abs(v) > 1e-7
end

local function safe_has_develop_adjustments(photo)
    if not photo then return false end
    -- Primary checks that Lightroom provides.
    local ok, val = LrTasks.pcall(function() return photo:hasDevelopAdjustments() end)
    if ok and type(val) == 'boolean' then return val end
    ok, val = LrTasks.pcall(function() return photo:getRawMetadata('hasDevelopAdjustments') end)
    if ok and type(val) == 'boolean' then return val end

    -- Heuristic fallback: inspect develop settings for obvious non-defaults.
    local okDS, ds = LrTasks.pcall(function() return photo:getDevelopSettings() end)
    if okDS and type(ds) == 'table' then
        -- White balance: any mode other than 'As Shot' implies an edit
        local wb = ds.WhiteBalance
        if type(wb) == 'string' and wb ~= 'As Shot' then
            logger:trace('Heuristic: treat as edited due to WhiteBalance=' .. tostring(wb))
            return true
        end
        -- Cropping: only treat as edited if explicit HasCrop true, or angle non-zero,
        -- or crop bounds differ from defaults (0,0,1,1) by a meaningful margin.
        local hasCrop = (type(ds.HasCrop) == 'boolean' and ds.HasCrop == true)
        local angle = tonumber(ds.CropAngle)
        local left = tonumber(ds.CropLeft) or 0
        local top = tonumber(ds.CropTop) or 0
        local right = tonumber(ds.CropRight) or 1
        local bottom = tonumber(ds.CropBottom) or 1
        local cropDiffers = (left > 1e-6) or (top > 1e-6) or (right < 1 - 1e-6) or (bottom < 1 - 1e-6)
        if hasCrop or nonzero(angle) or cropDiffers then
            logger:trace(string.format('Heuristic: treat as edited due to crop (HasCrop=%s angle=%s LTRB=%.6f,%.6f,%.6f,%.6f)', tostring(hasCrop), tostring(angle), left, top, right, bottom))
            return true
        end
        -- Common tone and presence adjustments.
        -- Note: Ignore default sharpening/noise reduction baselines (e.g., Sharpness=40, ColorNoiseReduction=25)
        -- which are applied to many RAW files by default and should not count as edits.
        local keys = {
            'Exposure2012','Contrast2012','Highlights2012','Shadows2012','Whites2012','Blacks2012',
            'Clarity2012','Texture','Dehaze','Vibrance','Saturation',
            -- exclude 'Sharpness', 'ColorNoiseReduction'
            'LuminanceSmoothing', 'GrainAmount','PostCropVignetteAmount'
        }
        for _, k in ipairs(keys) do
            local v = tonumber(ds[k])
            if nonzero(v) then
                logger:trace('Heuristic: treat as edited due to nonzero ' .. k .. '=' .. tostring(v))
                return true
            end
        end
        -- Special-case known defaults: ignore Sharpness<=40, ColorNoiseReduction<=25
        local sharp = tonumber(ds.Sharpness) or 0
        local cnr = tonumber(ds.ColorNoiseReduction) or 0
        if (sharp > 40 + 1e-6) or (cnr > 25 + 1e-6) then
            logger:trace(string.format('Heuristic: treat as edited due to non-default sharpening/noise (Sharpness=%.1f, ColorNR=%.1f)', sharp, cnr))
            return true
        end
    end
    return false
end

local function sibling_jpeg_for(path, dir, stem)
    local s
    if path then
        s = path:gsub('%.[^%.]+$', '')
    else
        if not (dir and stem) then return nil end
        s = LrPathUtils.child(dir, stem)
    end

    local cand1 = s .. '.JPG'
    local cand2 = s .. '.jpg'
    local cand3 = s .. '.JPEG'
    local cand4 = s .. '.jpeg'
    if LrFileUtils.exists(cand1) then return cand1 end
    if LrFileUtils.exists(cand2) then return cand2 end
    if LrFileUtils.exists(cand3) then return cand3 end
    if LrFileUtils.exists(cand4) then return cand4 end
    return nil
end

local function get_dir_and_stem(photo)
    local okPath, origPath = LrTasks.pcall(function() return photo:getRawMetadata('path') end)
    if okPath and origPath and LrFileUtils.exists(origPath) then
        local dir = LrPathUtils.parent(origPath)
        local leaf = LrPathUtils.leafName(origPath)
        local stem = leaf:gsub('%.[^%.]+$', '')
        return dir, stem, origPath
    end

    local okFolder, folder = LrTasks.pcall(function() return photo:getRawMetadata('folder') end)
    local okName, fileName = LrTasks.pcall(function() return photo:getFormattedMetadata('fileName') end)
    if okFolder and folder and okName and fileName then
        local dir = folder:getPath()
        local stem = fileName:gsub('%.[^%.]+$', '')
        return dir, stem, origPath
    end
    return nil, nil, origPath
end

-- Decide whether to render from Lightroom or reuse camera JPEG.
-- Returns table: { useRendered = boolean, sourcePath = string|nil, edited, fileFormat, origPath, siblingPath, reason }
function M.choose(photo, opts)
    opts = opts or {}
    if not photo then return { useRendered = true, reason = 'no photo' } end

    local edited = safe_has_develop_adjustments(photo)
    local okFmt, fileFormat = LrTasks.pcall(function() return photo:getRawMetadata('fileFormat') end)
    local dir, stem, origPath = get_dir_and_stem(photo)
    local sibling = sibling_jpeg_for(origPath, dir, stem)
    local okName, fileName = LrTasks.pcall(function() return photo:getFormattedMetadata('fileName') end)

    logger:trace(string.format(
        'SourceSelector.choose: file=%s edited=%s fileFormat=%s origPath=%s dir=%s stem=%s sibling=%s preferCameraJPEG=%s forceIfSibling=%s',
        tostring(okName and fileName or '?'), tostring(edited), tostring(okFmt and fileFormat or '?'), tostring(origPath), tostring(dir), tostring(stem), tostring(sibling), tostring(opts.preferCameraJPEG), tostring(opts.forceIfSibling)
    ))

    -- For unedited images, prefer camera JPEG if available.
    if not edited then
        if okFmt and fileFormat == 'JPEG' and origPath and LrFileUtils.exists(origPath) then
            local result = { useRendered = false, sourcePath = origPath, edited = edited, fileFormat = fileFormat, origPath = origPath, siblingPath = sibling, reason = 'catalog JPEG (no edits)' }
            logger:info(string.format('SourceSelector.decision: file=%s useRendered=%s source=%s reason=%s', tostring(okName and fileName or '?'), tostring(result.useRendered), tostring(result.sourcePath), tostring(result.reason)))
            return result
        end
        if sibling then
            local result = { useRendered = false, sourcePath = sibling, edited = edited, fileFormat = fileFormat, origPath = origPath, siblingPath = sibling, reason = 'sibling JPEG (no edits)' }
            logger:info(string.format('SourceSelector.decision: file=%s useRendered=%s source=%s reason=%s', tostring(okName and fileName or '?'), tostring(result.useRendered), tostring(result.sourcePath), tostring(result.reason)))
            return result
        end
    end

    -- Debug/override: force sibling JPEG regardless of edits if present.
    if opts.forceIfSibling and sibling then
        local result = { useRendered = false, sourcePath = sibling, edited = edited, fileFormat = fileFormat, origPath = origPath, siblingPath = sibling, reason = 'forced sibling JPEG' }
        logger:info(string.format('SourceSelector.decision: file=%s useRendered=%s source=%s reason=%s', tostring(okName and fileName or '?'), tostring(result.useRendered), tostring(result.sourcePath), tostring(result.reason)))
        return result
    end

    local result = { useRendered = true, edited = edited, fileFormat = fileFormat, origPath = origPath, siblingPath = sibling, reason = edited and 'edited' or 'no sibling JPEG' }
    logger:trace(string.format(
        'SourceSelector.decision: file=%s useRendered=%s source=%s reason=%s',
        tostring(okName and fileName or '?'), tostring(result.useRendered), tostring(result.sourcePath), tostring(result.reason)
    ))
    return result
end

return M
