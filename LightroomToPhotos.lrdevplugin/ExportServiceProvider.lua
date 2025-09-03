local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'

local HeicConverter = require 'HeicConverter'
local SourceSelector = require 'SourceSelector'
local logger = require 'Logger'

local provider = {}

-- Called when the Export dialog opens.
provider.startDialog = function(propertyTable)
    if propertyTable.convertToHEIC == nil then propertyTable.convertToHEIC = false end
    if propertyTable.heicQuality == nil then propertyTable.heicQuality = 0.95 end
    if propertyTable.albumName == nil then propertyTable.albumName = '/Lightroom/Review' end
    if propertyTable.preferCameraJPEG == nil then propertyTable.preferCameraJPEG = true end
    if propertyTable.forceCameraJPEGIfSibling == nil then propertyTable.forceCameraJPEGIfSibling = false end
    if propertyTable.debugAnnotateFilenames == nil then propertyTable.debugAnnotateFilenames = true end

    -- Encourage Lightroom to render to a temp location and not prompt on collisions
    if propertyTable.LR_export_destinationType == nil then propertyTable.LR_export_destinationType = 'temporary' end
    if propertyTable.LR_collisionHandling == nil then propertyTable.LR_collisionHandling = 'rename' end
end

-- Fields we may persist in presets later.
provider.exportPresetFields = {
    { key = 'convertToHEIC', default = false },
    { key = 'heicQuality', default = 0.95 },
    { key = 'albumName', default = '/Lightroom/Review' },
    { key = 'preferCameraJPEG', default = true },
    { key = 'forceCameraJPEGIfSibling', default = false },
    { key = 'debugAnnotateFilenames', default = true },
}

provider.sectionsForTopOfDialog = function(vf, propertyTable)
    local bind = LrView.bind
    return {
        {
            title = 'Lightroom to Photos – Wireframe',
            vf:column {
                spacing = vf:control_spacing(),

                vf:row { vf:checkbox { title = 'Prefer camera JPEG when no edits', value = bind 'preferCameraJPEG' } },
                vf:row { vf:checkbox { title = 'Force camera JPEG if sibling exists (debug)', value = bind 'forceCameraJPEGIfSibling' } },
                vf:spacer { height = 8 },

                vf:row {
                    vf:checkbox { title = 'Convert to HEIC (via sips)', value = bind 'convertToHEIC' },
                    vf:spacer { width = 12 },
                    vf:static_text { title = 'Quality' },
                    vf:slider { value = bind 'heicQuality', min = 0.6, max = 1.0 },
                    vf:static_text { title = bind({ key = 'heicQuality', transform = function(v) return string.format('%d%%', math.floor((tonumber(v) or 0.95)*100)) end }) },
                },

                vf:spacer { height = 6 },
                vf:row { vf:checkbox { title = 'Annotate filenames with source (debug)', value = bind 'debugAnnotateFilenames' } },
                vf:row { vf:static_text { title = 'Album (not used yet):', width_in_chars = 18, alignment = 'right' }, vf:edit_field { value = bind 'albumName', width_in_chars = 32 } },

                vf:spacer { height = 8 },
                vf:static_text { title = 'Wireframe: Export runs and optionally creates HEIC copies. Import to Photos is not implemented yet.' },
            },
        },
    }
end

-- Core export loop: renders using Lightroom; optionally converts to HEIC for testing.
provider.hideSections = { 'exportLocation', 'fileNaming', 'video', 'watermarking', 'postProcessing', 'outputSharpening' }

provider.processRenderedPhotos = function(functionContext, exportContext)
    local exportSession = exportContext.exportSession
    local props = exportContext.propertyTable or {}

    local finalPaths = {}
    local heicCount = 0
    local reusedCount = 0
    local renderedCount = 0
    local decisions = {}
    local renderItems = {}

    logger:info(string.format('Export started: preferCameraJPEG=%s forceCameraJPEGIfSibling=%s convertToHEIC=%s quality=%.2f annotate=%s',
        tostring(props.preferCameraJPEG), tostring(props.forceCameraJPEGIfSibling), tostring(props.convertToHEIC), tonumber(props.heicQuality or 0), tostring(props.debugAnnotateFilenames)))

    local function annotatedHeicPath(srcPath, tag)
        local tempDir = LrPathUtils.getStandardFilePath('temp')
        local leaf = LrPathUtils.leafName(srcPath or 'file')
        local stem = leaf:gsub('%.[^%.]+$', '')
        local function candidate(i)
            local suffix = (i and i > 0) and ('-' .. tostring(i)) or ''
            return LrPathUtils.child(tempDir, string.format('%s__%s%s.HEIC', stem, tag, suffix))
        end
        local i = 0
        local dest = candidate(i)
        while LrFileUtils.exists(dest) do
            i = i + 1
            dest = candidate(i)
        end
        return dest
    end

    local totalCount = 0
    local reuseItems = {}

    -- Pass 1: Decide per-photo and call skipRender() for any we will reuse,
    -- before starting any rendering via waitForRender().
    for _, rendition in exportContext:renditions { stopIfCanceled = true } do
        totalCount = totalCount + 1
        local photo = rendition.photo
        local choice = { useRendered = true }
        if props.preferCameraJPEG or props.forceCameraJPEGIfSibling then
            choice = SourceSelector.choose(photo, { forceIfSibling = props.forceCameraJPEGIfSibling, preferCameraJPEG = props.preferCameraJPEG })
        end

        local basePath = nil
        local srcTag = 'SRC-LR'
        if choice.useRendered then
            renderItems[#renderItems + 1] = { rendition = rendition, photo = photo, choice = choice }
        else
            logger:trace('Calling skipRender() before any rendering to reuse camera JPEG')
            rendition:skipRender()
            basePath = choice.sourcePath
            srcTag = 'SRC-CAM'
            reuseItems[#reuseItems + 1] = { photo = photo, basePath = basePath, srcTag = srcTag, choice = choice }
        end
    end

    -- Process reuse items now (no LR rendering involved).
    for _, item in ipairs(reuseItems) do
        local photo = item.photo
        local basePath = item.basePath
        local srcTag = item.srcTag
        local choice = item.choice
        if basePath then reusedCount = reusedCount + 1 end
        logger:info(string.format('Reused camera JPEG: file=%s path=%s reason=%s edited=%s format=%s sibling=%s',
            tostring(photo and photo:getFormattedMetadata('fileName') or '?'), tostring(basePath), tostring(choice.reason), tostring(choice.edited), tostring(choice.fileFormat), tostring(choice.siblingPath)))

        if basePath then
            local outPath = basePath
            if props.convertToHEIC then
                local dest = nil
                if props.debugAnnotateFilenames then
                    dest = annotatedHeicPath(basePath, srcTag)
                end
                local ok, heicPath = HeicConverter.convert(basePath, { quality = props.heicQuality, destPath = dest })
                if ok and heicPath then
                    outPath = heicPath
                    heicCount = heicCount + 1
                    logger:trace(string.format('Converted to HEIC: from=%s to=%s', tostring(basePath), tostring(outPath)))
                else
                    logger:warn(string.format('HEIC conversion failed rc or missing output: from=%s', tostring(basePath)))
                end
            end
            finalPaths[#finalPaths + 1] = outPath
            decisions[#decisions + 1] = string.format('%s: %s -> %s', (photo and photo:getFormattedMetadata('fileName') or '?'), srcTag, outPath)
        end
    end

    -- Pass 2: For the remaining items that need LR rendering, perform renders now.
    for _, item in ipairs(renderItems) do
        local rendition = item.rendition
        local photo = item.photo
        local choice = item.choice

        local success, pathOrMessage = rendition:waitForRender()
        if success and pathOrMessage then
            local basePath = pathOrMessage
            renderedCount = renderedCount + 1
            logger:trace(string.format('Rendered from LR: file=%s path=%s reason=%s edited=%s format=%s sibling=%s',
                tostring(photo and photo:getFormattedMetadata('fileName') or '?'), tostring(basePath), tostring(choice.reason), tostring(choice.edited), tostring(choice.fileFormat), tostring(choice.siblingPath)))

            local outPath = basePath
            if props.convertToHEIC then
                local dest = nil
                if props.debugAnnotateFilenames then
                    dest = annotatedHeicPath(basePath, 'SRC-LR')
                end
                local ok, heicPath = HeicConverter.convert(basePath, { quality = props.heicQuality, destPath = dest })
                if ok and heicPath then
                    outPath = heicPath
                    heicCount = heicCount + 1
                    logger:trace(string.format('Converted to HEIC: from=%s to=%s', tostring(basePath), tostring(outPath)))
                else
                    logger:warn(string.format('HEIC conversion failed rc or missing output: from=%s', tostring(basePath)))
                end
            end

            finalPaths[#finalPaths + 1] = outPath
            decisions[#decisions + 1] = string.format('%s: %s -> %s', (photo and photo:getFormattedMetadata('fileName') or '?'), 'SRC-LR', outPath)
        else
            rendition:skipRender()
            local msg = string.format('%s: render failed / skipped (edited=%s, fileFormat=%s, sibling=%s, reason=%s)', (photo and photo:getFormattedMetadata('fileName') or '?'), tostring(choice.edited), tostring(choice.fileFormat), tostring(choice.siblingPath), tostring(choice.reason))
            decisions[#decisions + 1] = msg
            logger:warn(msg)
        end
    end

    LrFunctionContext.postAsyncTaskWithContext('LTP_Wireframe_ExportDone', function()
        local summary = string.format('Processed %d photo(s). Rendered: %d, Reused JPEG: %d, HEIC conversions: %d.\nNote: This wireframe does not import to Photos yet.', totalCount, renderedCount, reusedCount, heicCount)
        logger:info('Export summary: ' .. summary)
        LrDialogs.message(
            'Lightroom to Photos – Export Complete',
            summary,
            'info'
        )
    end)
end

return provider
