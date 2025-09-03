local M = {}

local crc32_table = {}
do
  local poly = 0xEDB88320
  for i = 0, 255 do
    local crc = i
    for _ = 1, 8 do
      if (crc & 1) ~= 0 then
        crc = (crc >> 1) ~ poly
      else
        crc = (crc >> 1)
      end
    end
    crc32_table[i] = crc
  end
end

function M.crc32(str)
  local crc = 0xFFFFFFFF
  for i = 1, #str do
    local b = string.byte(str, i)
    local idx = (crc ~ b) & 0xFF
    crc = ((crc >> 8) & 0xFFFFFF) ~ crc32_table[idx]
  end
  return (~crc) & 0xFFFFFFFF
end

function M.tohex(u32)
  local t = {}
  for i = 7, 0, -1 do
    local n = (u32 >> (i*4)) & 0xF
    t[#t+1] = string.format("%x", n)
  end
  return table.concat(t)
end

return M

