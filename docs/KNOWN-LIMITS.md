# Known limits — unreleased development candidate

- Stable acceptance is pending native Intel/macOS 13 hosts, genuine camera/HDR/depth/Live Photo/RAW and large video inputs, volume behavior, native UI/Services/droplets, isolated Finder preferences, Instruments responsiveness, Developer ID and notarization.
- Current integration evidence uses generated JPEG, baseline HEIC, TIFF, PNG, lossless WebP, 8-bit AVIF, MOV and MP4. This does not qualify every file with one of those extensions.
- Unknown, encrypted, externally referenced, auxiliary or otherwise unqualified layouts are read-only for embedded edits. Filesystem dates/rename and explicitly chosen XMP sidecars have separate support decisions. PNG full stripping and unqualified RAW embedded writing are disabled.
- Video embedded writes require locally stored, verifiable audio/video samples. Caption, GPS/metadata and auxiliary tracks require separate qualification. External URL/alias media references are rejected before asset loading.
- Conflicting metadata copies require an explicit date copy, manual place or correction; embedded rewrites of repeated descriptive/capture layouts are blocked. Structural copies are preserved and checked.
- Offline lookup supplies nearby populated places from the bundled GeoNames-derived database. Small places may be absent. Distances and alternative candidates are approximate; there is no online fallback.
- Nanosecond evidence is retained where provided. Filesystem rounding or inability to preserve required metadata stops a write. Older Date-only recovery manifests retain their original precision limitations.
- No network update checks, analytics or automatic sharing are implemented. Developer signing/notarization and an explicitly invoked publication script are separate distribution operations.
