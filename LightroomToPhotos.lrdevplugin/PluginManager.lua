local LrView = import 'LrView'

local provider = {}

function provider.sectionsForTopOfDialog(vf, _)
    return {
        {
            title = 'Lightroom to Photos',
            vf:column {
                spacing = vf:control_spacing(),
                vf:static_text { title = 'Wireframe loaded.' },
                vf:static_text { title = 'Use Plug-in Extras > Lightroom to Photos: Hello to verify.' },
            },
        },
    }
end

return provider

