# Lightroom to Photos Plugin

Lightroom Classic export plug‑in to send photos directly to Apple Photos, converting to HEIC for better iCloud storage efficiency and duplicate detection. It replaces the crude "[`syncpics.py`](./syncpics/syncpics.py)" workflow that mirrored and batch‑converted JPEGs.

The plug‑in focuses on a pragmatic, context‑aware export:
- If a photo has no edits, reuse the original camera JPEG (if present) and import that to Photos (optionally converting to HEIC).
- If a photo is edited in Lightroom, render it from Lightroom, convert to HEIC, and import that to Photos.

The result is a fast path for unedited shots (keeping the camera’s colour science) and a high‑quality path for edited images.

## Features

- Export to Apple Photos with HEIC conversion (uses macOS capabilities).
- Prefer camera JPEG for unedited photos (skips Lightroom rendering for the source decision).
- Edited detection for common adjustments (crop/angle, tone/presence, sharpening/noise thresholds) and white balance changes.
- Duplicate‑friendly HEIC outputs:
  - Unedited: HEIC stored/reused in a hidden `.photos-heic/` folder next to the JPEG (Lightroom ignores it; Photos sees identical bytes on re‑import).
  - Edited: Deterministic cache path with a short fingerprint and quality indicator; re‑exporting identical edits reuses the same bytes.
- Album import:
  - Primary album: receives unedited (camera) photos.
  - Optional “Edited Album”: receives edited photos. If left blank, edited photos go to the Photos library only.
- Albums are created only if missing (top‑level albums; no folders created).
- Verbose logging (TRACE/INFO) to help reason about decisions and troubleshoot.

## Philosophy

- Prefer camera JPEG when unedited:
  - Color/tonality: In‑camera processing (e.g., Canon Picture Styles) often gives pleasing skin tones and contrast that are hard to match with profiles.
  - Zero generational loss: We avoid rendering JPEG‑from‑RAW when there are no edits; when we convert to HEIC, it’s from the original camera JPEG.
  - Speed: Skips Lightroom’s render pipeline for unedited shots, reducing export time and CPU.
  - Consistency: Documentary/event workflows often rely on the OOC JPEG look; only images needing adjustments are rendered from RAW.
  - Duplicate handling: Reusing a stable HEIC derived from the same camera JPEG helps Photos detect duplicates on re‑import.

- Respect edits when present:
  - If edits are detected (including white balance changes), render from Lightroom, convert once to HEIC, and cache it deterministically so identical re‑exports reuse the same bytes.

- Be duplicate‑friendly and Lightroom‑friendly:
  - Cache HEICs in a hidden `.photos-heic/` folder next to sources so Lightroom ignores them; Photos imports by full path.
  - Reuse HEICs whenever possible (unedited and edited paths) so Photos sees identical content and flags duplicates.

- Minimal surface area:
  - Albums created only if missing; no folders created.
  - Keep UI focused on decisions that matter: prefer camera JPEG, HEIC + quality, album names.

## Installation

1. Clone or download this repo.
2. In Lightroom Classic, open File → Plug‑in Manager… → Add, and select the folder `LightroomToPhotos.lrdevplugin`.
3. Enable the plug‑in.

## Usage

1. Select photos in Lightroom.
2. File → Export… → Choose “Apple Photos (HEIC)”.
3. Options in the panel:
   - Prefer camera JPEG when no edits: If a sibling JPG exists and no edits are detected, reuse it.
   - Convert to HEIC (via sips) + Quality: Apply HEIC conversion (80–100% typical).
   - Album Name: Primary album for unedited photos.
   - Edited Album (optional): If provided, edited photos are imported here; if blank, edited photos go to the Photos library only.
4. Export. At completion you’ll see a summary with import results.

## Logs

- macOS: `~/Library/Logs/Adobe/Lightroom/LightroomToPhotos.log`
- We use `LrLogger('LightroomToPhotos')` with `logfile` enabled; TRACE/INFO messages include source selection decisions and import actions.

## File Layout and Caching

- Hidden cache folder: `.photos-heic/` in the same directory as the source image.
  - Unedited: `<stem>.HEIC`
  - Edited: `<stem>-EDIT-<short-hash>Q<quality>.HEIC` (short hash reflects the edit state; quality is the configured HEIC quality)
- Lightroom ignores dot‑folders; Photos imports by full path.

## Limitations / Notes

- Lightroom rendering: Lightroom may still render a temporary file during export. For unedited photos we ignore that output and work from the camera JPEG.
- Cache scope: The edited‑photo cache reflects Lightroom develop settings and the chosen HEIC quality. Other export options (like pixel dimensions or colour space) aren’t included.
- Apple Photos scripting: Import is best‑effort and can vary slightly by macOS version; the plug‑in imports and adds to the named album if present (creating it only when missing).

## Roadmap / Ideas

- Performance: investigate a safe path to truly skip LR rendering for reused JPEGs.
- Robustness: surface AppleScript errors inline in the summary with more detail.
- Dimensions/profile aware cache: include export dimensions/colour profile in the edited fingerprint.
- Optional “Use folders” mode for nested album organization (currently album‑only to keep things simple).

---

### Existing Plugins / Research

* https://github.com/sto3014/LRPhotos: LRPhotos is a Lightroom Classic publishing service for Apple's Photos app.
* https://github.com/cimm/iphotoexportservice/: The Lightroom to iPhoto plugin exports the selected photos from Adobe Lightroom to iPhoto and creates an album with these photos if needed.
* https://github.com/matiaskorhonen/custom-photo-importer: Prior art for dealing with Apple Photos metadata
* https://github.com/Jaid/lightroom-sdk-8-examples
* https://github.com/bmachek/lrc-immich-plugin
* https://akrabat.com/writing-a-lightroom-classic-plug-in/
* https://developer.adobe.com/console/servicesandapis
* http://regex.info/blog/lightroom-goodies/run-any-command
