local LrMD5 = import 'LrMD5'

local M = {}

function M.md5(str)
  return LrMD5.digest(str or '')
end

return M
