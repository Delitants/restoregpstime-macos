# Embedded metadata profiles

The registry is an upper bound on operations. Each preview also validates the exact tags and
parses the actual media. Malformed or unrecognized layouts remain blocked even when their
container name appears in the registry. Writes operate only on private transaction stages.

The synthetic geometric JPEG, baseline HEIC, TIFF, PNG, WebP, AVIF and H264 MOV/MP4 fixtures
exercise real bundled ExifTool writes. WebP was authored with Pillow 12.3.0/libwebp 1.6.0;
AVIF with FFmpeg 8.1.2/SVT-AV1; MP4 remuxes the generated MOV without re-encoding. The optional
`Scripts/generate-additional-fixtures.py` records versions and hashes in a fresh folder.
These are baseline and parser tests, not genuine camera RAW/HDR/depth/Live Photo qualification.
Unqualified RAW, HEIF HDR/auxiliary and video metadata-track layouts remain read-only.

| Profile | Selected fields | GPS removal | Descriptive strip |
| --- | --- | --- | --- |
| JPEG | Qualified | Qualified | Qualified bounded layouts |
| Baseline HEIC/HEIF | Qualified | Qualified | Disabled |
| TIFF, PNG, WebP, AVIF | Qualified | Qualified | Disabled |
| MOV, MP4 stored audio/video tracks | Qualified | Qualified fields only | Disabled |
| New explicit XMP sidecar | Qualified XMP fields | Source unaffected | Disabled |
| Unqualified RAW/HDR/depth/auxiliary variants | Read-only | Disabled | Disabled |

PNG stripping is disabled after a real fixture check found ExifTool's blanket removal
also deletes sRGB. The integrity check rejected the stage and no source was committed.
Date edits retain an existing EXIF capture family in PNG/WebP/AVIF when present;
otherwise those containers use XMP. Other unselected date families remain intact.

Integrity evidence covers stored JPEG scans, PNG image chunks, TIFF image extents, WebP
image/alpha/frame chunks, HEIF/AVIF item extents and properties/relationships, and compressed
video/audio samples with timing, formats and track properties. It is independent of a
successful image decode or a whole-file hash. New explicit XMP sidecars contain no media;
their XML must be bounded RDF without entities. Existing XMP sidecars remain read-only.

Descriptive stripping preserves required rendering and linkage fields; its capability is
qualified separately from selected tag edits and location removal. Removing recognized
GPS streams or fields without a supported removal path fails with incomplete-removal.
This is not a claim to erase every possible location clue in arbitrary comments or media.

Primary format/API references consulted for the independently written parsers:

- [Google WebP container specification](https://developers.google.com/speed/webp/docs/riff_container)
- [Adobe TIFF 6.0 specification](https://developer.adobe.com/content/dam/udp/en/open/standards/tiff/TIFF6.pdf)
- [W3C PNG specification](https://www.w3.org/TR/png-3/)
- [AOM AV1 image file format](https://aomediacodec.github.io/av1-avif/)
- [libheif HEVC configuration parser](https://github.com/strukturag/libheif/blob/master/libheif/codecs/hevc_boxes.cc)
- [Apple stored-format sample output](https://developer.apple.com/documentation/avfoundation/avassetreadertrackoutput/init(track:outputsettings:))
- [ExifTool writing documentation](https://exiftool.org/exiftool_pod.html)

No reference application's code or assets are incorporated. The app's displayed behavior
and documentation informed the functional inventory only.
