# Known limits

- Files need capture metadata to restore capture dates, and GPS coordinates to look up places. Missing information is shown in File details.
- GPS time zones use the nearest city within 25 km. Review photos near time-zone borders. Files without a usable offset or GPS time zone need one batch fallback zone; ambiguous daylight-saving times may need a choice.
- Offline place matches are approximate nearby cities, not street addresses. Small places may be missing.
- Some RAW, HEIC and video files support date changes or renaming but cannot safely accept embedded metadata edits. File details explains which changes are available; XMP sidecars are an option where supported.
- Conflicting metadata may need a source selection or correction before applying.
- Metadata-only undo requires unchanged processed files. Choose Full backup if you need recovery after they are edited or lost.
- Downloads are self-signed and unnotarized. macOS may require **Open Anyway** on first launch.
