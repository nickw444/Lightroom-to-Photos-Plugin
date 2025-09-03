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

    -- Simple menu item to verify loading
    LrLibraryMenuItems = {
        {
            title = 'Lightroom to Photos: Hello',
            file = 'Main.lua',
        },
    },

    -- Minimal export service scaffold
    LrExportServiceProvider = {
        title = 'Photos (HEIC) – Wireframe',
        file = 'ExportServiceProvider.lua',
        id = 'com.nickwhyte.photos-wireframe',
    },
}
