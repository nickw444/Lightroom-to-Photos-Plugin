return {
    VERSION = { major = 0, minor = 1, revision = 0, build = 1 },

    -- Lightroom SDK versions
    LrSdkVersion = 9.0,
    LrSdkMinimumVersion = 6.0,

    -- Plugin identity
    LrToolkitIdentifier = 'com.nickwhyte.lightroom-to-photos',
    LrPluginName = 'Lightroom to Photos',
    LrPluginInfoUrl = 'https://github.com/nickw444/Lightroom-to-Photos-Plugin',

    -- Plug-in Manager info panel
    LrPluginInfoProvider = 'PluginManager.lua',

    -- No debug menu items in production build

    -- Export service
    LrExportServiceProvider = {
        title = 'Apple Photos (HEIC)',
        file = 'ExportServiceProvider.lua',
        id = 'com.nickwhyte.lightroom-to-photos.export',
    },
}
