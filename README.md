# Lightroom to Photos Plugin

A Lightroom Export Plugin to add support for direct export to Apple Photos with HEIC conversion for iCloud storage optimisation. 

Intends to replace my crude "[`syncpics.py`](./syncpics/syncpics.py)" script which goes through my Lightroom photos directory and mirrors it into another folder, converts all JPEGs it finds into HEIC equivalents.

### Features

* Export Lightroom photos directly to Apple Photos
* Export corresponding unprocessed camera JPEGs (if preferred). Personally I prefer Canon's JPEG colour over Lightroom's camera matching profile, so prefer this as an option to making global edits for documentary/non-artistic shots.

### Goals

* Ideally support contextually aware export: For photos _with_ edits, export the RAW to JPEG/HEIC. For photos _without_ edits, export the unprocessed camera JPEG.

### Existing Plugins / Research

* https://github.com/sto3014/LRPhotos: LRPhotos is a Lightroom Classic publishing service for Apple's Photos app.
* https://github.com/cimm/iphotoexportservice/: The Lightroom to iPhoto plugin exports the selected photos from Adobe Lightroom to iPhoto and creates an album with these photos if needed.
* https://github.com/matiaskorhonen/custom-photo-importer: Prior art for dealing with Apple Photos metadata
* https://github.com/Jaid/lightroom-sdk-8-examples
* https://github.com/bmachek/lrc-immich-plugin
