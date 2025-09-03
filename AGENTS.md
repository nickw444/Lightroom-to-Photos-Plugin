# Guidance for Future Agents

This document briefs future LLM agents on the plugin’s intent, important design choices, and safe development practices for this repository.

## Purpose

Lightroom Classic export plug‑in that sends selected photos to Apple Photos, converting to HEIC for better iCloud storage efficiency. It aims to:
- Prefer the camera JPEG when there are no Lightroom edits.
- Render and export an edited image when there are edits.
- Be duplicate‑friendly by reusing identical HEIC bytes across re‑exports.

Keep user‑facing UI minimal and avoid fragile or noisy features.

## Architecture at a Glance

Key modules inside `LightroomToPhotos.lrdevplugin/`:
- `ExportServiceProvider.lua` – Export UI, orchestration, conversion, and import to Photos.
- `SourceSelector.lua` – Decides “use camera JPEG” vs “render from Lightroom” via Lightroom flags + heuristics (crop/angle, tone/presence, sharpen/NR thresholds, WhiteBalance != "As Shot").
- `HeicConverter.lua` – Wraps macOS `sips` to write HEIC; floors quality to avoid off‑by‑one; early‑reuses dest file if it already exists.
- `EditCache.lua` – Deterministic file naming for edited HEICs using MD5 of photo UUID + canonical develop settings + quality; files written in a hidden side‑folder.
- `Hash.lua` – Uses Lightroom’s `LrMD5` for stable digests (avoid Lua bitwise).
- `PhotosImporter.lua` – AppleScript bridge to import files into Photos and add to an album (created only if missing).
- `Logger.lua` – `LrLogger('LightroomToPhotos')` with logfile enabled.
- `Info.lua`, `PluginManager.lua` – Manifest and Plug‑in Manager panel.

Folder layout and caching:
- A hidden side‑folder `.photos-heic/` is created next to source images.
- Unedited HEICs: `<stem>.HEIC` (reused if present).
- Edited HEICs: `<stem>-EDIT-<short-hash>Q<quality>.HEIC` (hash reflects develop settings; quality is floored integer percent).
- Lightroom ignores dot‑folders; Apple Photos imports by path.

## Behaviors and Decisions

1) Source selection
- If unedited and a sibling camera JPEG exists (or catalog file is JPEG), reuse the camera JPEG.
- Considered “edited” if Lightroom flags edits or any of these heuristics indicate changes:
  - Crop/angle differs from defaults.
  - Tone/presence sliders (exposure/contrast/highlights/shadows/whites/blacks/clarity/texture/dehaze/vibrance/saturation) noticeably non‑zero.
  - Sharpening/NR above typical RAW baselines (Sharpness > 40, ColorNoiseReduction > 25).
  - WhiteBalance != "As Shot".

2) Conversion (to HEIC)
- Uses `/usr/bin/sips` via `HeicConverter.lua`.
- Floors quality so 80% → Q80 (avoids UI off‑by‑one issues).
- Unedited: write/reuse `.photos-heic/<stem>.HEIC` next to the camera JPEG.
- Edited: compute deterministic cache path via `EditCache` and write/reuse there.

3) Import to Photos
- Unedited/camera photos import into the “Album Name”.
- Edited photos import into “Edited Album” if provided, otherwise into the library only.
- Albums are created only if missing (top‑level), never folders.

## Constraints and Gotchas (Please Read)

- Lightroom export sessions
  - `skipRender()` is fragile after rendering starts; current code avoids it. We always call `waitForRender()` and ignore the LR‑rendered file when using the camera JPEG.
- Lightroom Lua environment
  - Use `LrTasks.pcall(...)` for any metadata APIs that may yield; plain `pcall` can cause “Yielding is not allowed…” errors.
  - Avoid Lua bitwise operators; use Lightroom facilities (e.g., `LrMD5`) or pure‑Lua compatible patterns.
- Apple Photos scripting
  - Import is best‑effort and OS‑dependent; this plugin only creates a top‑level album if it does not exist. Do not create folders unless explicitly requested.
- Hidden side‑folder
  - Write cache files into `.photos-heic/` so Lightroom ignores them. Photos imports via full paths, so this is safe.
- Logging
  - TRACE/INFO logs are intentionally verbose for troubleshooting. Keep logs helpful but avoid dumping large structures.

## Development Principles

- Be surgical: respect the minimal UI. Avoid adding debug‑facing toggles unless truly necessary.
- Keep album behavior simple: only albums (no folders), create if missing, never reorganize the user’s Photos library.
- Duplicate‑friendly first: prefer reusing identical HEIC bytes (both unedited and edited paths) to let Photos detect duplicates.
- Robustness over cleverness: accommodate Lightroom SDK quirks (pcall vs pcall, session timing, etc.).
- No external dependencies; rely on Lightroom and macOS capabilities.
- Write small, focused commits with clear messages.

## Safe Ways to Extend

If you add functionality, align with these patterns:
- Edit fingerprint: If you need to account for new factors (e.g., output dimensions/colour space), extend `EditCache`’s key derivation instead of inventing new caches.
- Source decisions: Adjust `SourceSelector.lua` heuristics conservatively and keep thresholds documented.
- Import UX: Maintain album‑only semantics unless a “Use folders” mode is introduced behind a clear toggle.
- Performance: If revisiting render skipping, ensure you never call `skipRender()` after rendering begins; consider a two‑phase approach or Lightroom Publishing APIs if needed.

## Testing & Diagnostics

- Run exports with mixed selections (unedited RAW+JPEG, edited RAW, WB‑only edits).
- Inspect logs: macOS → `~/Library/Logs/Adobe/Lightroom/LightroomToPhotos.log`.
- Validate HEIC cache reuse by re‑exporting the same image without changes and observing identical paths in `.photos-heic/`.

## Out of Scope (Unless Requested)

- Creating Photos folders or nested album hierarchies.
- Opening/revealing albums in Photos (removed to reduce complexity).
- Managing videos or non‑photo assets.
- Broad refactors that change filenames, ids, or plugin identity in `Info.lua`.

