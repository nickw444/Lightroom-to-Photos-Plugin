local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'

local HeicConverter = require 'HeicConverter'
local SourceSelector = require 'SourceSelector'
local PhotosImporter = require 'PhotosImporter'
local logger = require 'Logger'

local provider = {}

-- Called when the Export dialog opens.
provider.startDialog = function(propertyTable)
    if propertyTable.convertToHEIC == nil then propertyTable.convertToHEIC = false end
    if propertyTable.heicQuality == nil then propertyTable.heicQuality = 0.95 end
    if propertyTable.albumName == nil then propertyTable.albumName = '/Lightroom/Review' end
    if propertyTable.exportToPhotos == nil then propertyTable.exportToPhotos = true end
    if propertyTable.openAlbumAfterImport == nil then propertyTable.openAlbumAfterImport = true end
    if propertyTable.preferCameraJPEG == nil then propertyTable.preferCameraJPEG = true end
    if propertyTable.forceCameraJPEGIfSibling == nil then propertyTable.forceCameraJPEGIfSibling = false end
    if propertyTable.debugAnnotateFilenames == nil then propertyTable.debugAnnotateFilenames = false end

    -- Encourage Lightroom to render to a temp location and not prompt on collisions
    if propertyTable.LR_export_destinationType == nil then propertyTable.LR_export_destinationType = 'temporary' end
    if propertyTable.LR_collisionHandling == nil then propertyTable.LR_collisionHandling = 'rename' end
end

-- Fields we may persist in presets later.
provider.exportPresetFields = {
    { key = 'convertToHEIC', default = false },
    { key = 'heicQuality', default = 0.95 },
    { key = 'albumName', default = '/Lightroom/Review' },
    { key = 'exportToPhotos', default = true },
    { key = 'openAlbumAfterImport', default = true },
    { key = 'preferCameraJPEG', default = true },
    { key = 'forceCameraJPEGIfSibling', default = false },
    { key = 'debugAnnotateFilenames', default = false },
}

provider.sectionsForTopOfDialog = function(vf, propertyTable)
    local bind = LrView.bind
    return {
        {
            title = 'Lightroom to Photos',
            vf:column {
                spacing = vf:control_spacing(),

                vf:row { vf:checkbox { title = 'Prefer camera JPEG when no edits', value = bind 'preferCameraJPEG' } },
                vf:row { vf:checkbox { title = 'Force camera JPEG if sibling exists (debug)', value = bind 'forceCameraJPEGIfSibling' } },
                vf:spacer { height = 8 },

                vf:row { vf:checkbox { title = 'Import to Apple Photos after export', value = bind 'exportToPhotos' } },
                vf:row { vf:static_text { title = 'Album:', width_in_chars = 18, alignment = 'right' }, vf:edit_field { value = bind 'albumName', width_in_chars = 32 } },
                vf:row { vf:checkbox { title = 'Open album after import', value = bind 'openAlbumAfterImport' } },

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
                vf:spacer { height = 8 },
                vf:static_text { title = 'Wireframe: Export runs and optionally creates HEIC copies. Import to Photos is supported.' },
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
    -- Simpler, robust approach: always call waitForRender() to keep LR happy,
    -- but if we prefer the camera JPEG we will base conversions on it and ignore LR's render.
    for _, rendition in exportContext:renditions { stopIfCanceled = true } do
        totalCount = totalCount + 1
        local photo = rendition.photo

        local choice = { useRendered = true }
        if props.preferCameraJPEG or props.forceCameraJPEGIfSibling then
            choice = SourceSelector.choose(photo, { forceIfSibling = props.forceCameraJPEGIfSibling, preferCameraJPEG = props.preferCameraJPEG })
        end

        local success, pathOrMessage = rendition:waitForRender()
        if not success then
            local msg = string.format('%s: render failed (edited=%s, fileFormat=%s, sibling=%s, reason=%s)', (photo and photo:getFormattedMetadata('fileName') or '?'), tostring(choice.edited), tostring(choice.fileFormat), tostring(choice.siblingPath), tostring(choice.reason))
            decisions[#decisions + 1] = msg
            logger:warn(msg)
        else
            local basePath
            local srcTag
            if choice.useRendered then
                basePath = pathOrMessage
                srcTag = 'SRC-LR'
                renderedCount = renderedCount + 1
                logger:trace(string.format('Rendered from LR: file=%s path=%s reason=%s edited=%s format=%s sibling=%s',
                    tostring(photo and photo:getFormattedMetadata('fileName') or '?'), tostring(basePath), tostring(choice.reason), tostring(choice.edited), tostring(choice.fileFormat), tostring(choice.siblingPath)))
            else
                basePath = choice.sourcePath or pathOrMessage
                srcTag = 'SRC-CAM'
                reusedCount = reusedCount + 1
                logger:info(string.format('Reused camera JPEG (did not skip LR render): file=%s path=%s fallbackLR=%s reason=%s edited=%s format=%s sibling=%s',
                    tostring(photo and photo:getFormattedMetadata('fileName') or '?'), tostring(basePath), tostring(pathOrMessage), tostring(choice.reason), tostring(choice.edited), tostring(choice.fileFormat), tostring(choice.siblingPath)))
            end

            local outPath = basePath
            if props.convertToHEIC and basePath then
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
            decisions[#decisions + 1] = string.format('%s: %s -> %s', (photo and photo:getFormattedMetadata('fileName') or '?'), srcTag or 'SRC-UNK', outPath)
        end
    end

    -- Optionally import to Photos
    local importOk, importRc, albumShown
    if props.exportToPhotos and #finalPaths > 0 then
        logger:info('Starting import to Photos, count=' .. tostring(#finalPaths) .. ' album=' .. tostring(props.albumName))
        PhotosImporter.ensureAutomationPermission()
        importOk, importRc = PhotosImporter.import(finalPaths, props.albumName)
        if importOk and props.openAlbumAfterImport and props.albumName and props.albumName ~= '' then
            PhotosImporter.showAlbum(props.albumName)
            albumShown = true
        end
    end

    LrFunctionContext.postAsyncTaskWithContext('LTP_Wireframe_ExportDone', function()
        local importSummary = ''
        if props.exportToPhotos then
            importSummary = string.format('\nImported to Photos: %s (rc=%s)%s', tostring(importOk), tostring(importRc), albumShown and ' and opened album' or '')
        end
        local summary = string.format('Processed %d photo(s). Rendered: %d, Reused JPEG: %d, HEIC conversions: %d.%s', totalCount, renderedCount, reusedCount, heicCount, importSummary)
        logger:info('Export summary: ' .. summary)
        LrDialogs.message(
            'Lightroom to Photos – Export Complete',
            summary,
            'info'
        )
    end)
end

return provider
