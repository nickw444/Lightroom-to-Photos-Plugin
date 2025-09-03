local LrLogger = import 'LrLogger'

local logger = LrLogger('LightroomToPhotos')

-- Always log to file; users can inspect via Lightroom logs.
logger:enable('logfile')

-- Uncomment to also print to the Lightroom log console for debugging.
-- logger:enable('print')

return logger

