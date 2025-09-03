local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'

-- Executed when the Library > Plug-in Extras > "Lightroom to Photos: Hello" menu item is clicked.
LrFunctionContext.callWithContext('LightroomToPhotos_Hello', function()
    LrDialogs.message(
        'Lightroom to Photos',
        'Plugin loaded and ready. This is the initial wireframe.',
        'info'
    )
end)

