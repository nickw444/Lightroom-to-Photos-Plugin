local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'

local HeicConverter = require 'HeicConverter'

local provider = {}

-- Called when the Export dialog opens.
provider.startDialog = function(propertyTable)
    if propertyTable.convertToHEIC == nil then propertyTable.convertToHEIC = false end
    if propertyTable.heicQuality == nil then propertyTable.heicQuality = 0.95 end
    if propertyTable.albumName == nil then propertyTable.albumName = '/Lightroom/Review' end
end

-- Fields we may persist in presets later.
provider.exportPresetFields = {
    { key = 'convertToHEIC', default = false },
    { key = 'heicQuality', default = 0.95 },
    { key = 'albumName', default = '/Lightroom/Review' },
}

provider.sectionsForTopOfDialog = function(vf, propertyTable)
    local bind = LrView.bind
    return {
        {
            title = 'Lightroom to Photos – Wireframe',
            vf:column {
                spacing = vf:control_spacing(),

                vf:row {
                    vf:checkbox { title = 'Convert to HEIC (via sips)', value = bind 'convertToHEIC' },
                    vf:spacer { width = 12 },
                    vf:static_text { title = 'Quality' },
                    vf:slider { value = bind 'heicQuality', min = 0.6, max = 1.0 },
                    vf:static_text { title = bind({ key = 'heicQuality', transform = function(v) return string.format('%d%%', math.floor((tonumber(v) or 0.95)*100)) end }) },
                },

                vf:spacer { height = 6 },
                vf:row { vf:static_text { title = 'Album (not used yet):', width_in_chars = 18, alignment = 'right' }, vf:edit_field { value = bind 'albumName', width_in_chars = 32 } },

                vf:spacer { height = 8 },
                vf:static_text { title = 'Wireframe: Export runs and optionally creates HEIC copies. Import to Photos is not implemented yet.' },
            },
        },
    }
end

-- Core export loop: renders using Lightroom; optionally converts to HEIC for testing.
provider.processRenderedPhotos = function(functionContext, exportContext)
    local exportSession = exportContext.exportSession
    local nPhotos = exportSession:countRenditions()
    local props = exportContext.propertyTable or {}

    local finalPaths = {}
    local heicCount = 0

    for _, rendition in exportContext:renditions { stopIfCanceled = true } do
        local success, pathOrMessage = rendition:waitForRender()
        if success and pathOrMessage then
            local outPath = pathOrMessage
            if props.convertToHEIC then
                local base = LrPathUtils.leafName(pathOrMessage)
                local stem = base:gsub('%.[^%.]+$', '')
                local outDir = LrPathUtils.parent(pathOrMessage) or LrPathUtils.getStandardFilePath('temp')
                local dest = LrPathUtils.child(outDir, stem .. '.HEIC')

                local ok, heicPath = HeicConverter.convert(pathOrMessage, { quality = props.heicQuality, destPath = dest })
                if ok and heicPath then
                    outPath = heicPath
                    heicCount = heicCount + 1
                end
            end
            finalPaths[#finalPaths + 1] = outPath
        else
            rendition:skipRender()
        end
    end

    LrFunctionContext.postAsyncTaskWithContext('LTP_Wireframe_ExportDone', function()
        LrDialogs.message(
            'Lightroom to Photos – Export Complete',
            string.format('Processed %d photo(s). HEIC conversions: %d.\nNote: This wireframe does not import to Photos yet.', nPhotos, heicCount),
            'info'
        )
    end)
end

return provider

