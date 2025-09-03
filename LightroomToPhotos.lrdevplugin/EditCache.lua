local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrTasks = import 'LrTasks'
local Hash = require 'Hash'

local M = {}

local function canonicalize_develop_settings(ds)
  if type(ds) ~= 'table' then return '' end
  local keys = {}
  for k, v in pairs(ds) do
    local tv = type(v)
    if tv == 'number' or tv == 'string' or tv == 'boolean' then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = ds[k]
    local tv = type(v)
    local sv
    if tv == 'number' then
      sv = string.format('%.4f', v)
    elseif tv == 'boolean' then
      sv = v and 'true' or 'false'
    else
      sv = tostring(v)
    end
    parts[#parts + 1] = k .. '=' .. sv
  end
  return table.concat(parts, ';')
end

local function photo_uuid(photo)
  local ok, uuid = LrTasks.pcall(function() return photo:getRawMetadata('uuid') end)
  return ok and uuid or ''
end

function M.editedDestFor(photo, quality, origPath)
  local q = tonumber(quality) or 0.8
  local qInt = math.floor(q * 100 + 0.5)
  local okDS, ds = LrTasks.pcall(function() return photo:getDevelopSettings() end)
  local canon = canonicalize_develop_settings(okDS and ds or {})
  local key = photo_uuid(photo) .. '|' .. tostring(qInt) .. '|' .. canon
  local digest = Hash.md5(key)
  local dir = LrPathUtils.parent(origPath or '') or LrPathUtils.getStandardFilePath('temp')
  local hiddenDir = LrPathUtils.child(dir, '.photos-heic')
  if not LrFileUtils.exists(hiddenDir) then
    LrFileUtils.createAllDirectories(hiddenDir)
  end
  local leaf = LrPathUtils.leafName(origPath or 'photo')
  local stem = leaf:gsub('%.[^%.]+$', '')
  local name = string.format('%s__EDIT-%s-Q%02d.HEIC', stem, digest, qInt)
  return LrPathUtils.child(hiddenDir, name)
end

return M
