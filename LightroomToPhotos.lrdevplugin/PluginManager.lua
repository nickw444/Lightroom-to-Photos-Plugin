local LrView = import 'LrView'

local provider = {}

function provider.sectionsForTopOfDialog(vf, _)
    return {
        {
            title = 'Lightroom to Photos',
            vf:column {
                spacing = vf:control_spacing(),
                vf:static_text { title = 'Plugin loaded.' },
            },
        },
    }
end

return provider
