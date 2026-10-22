# Timestamp precision and preservation

The application stores exact seconds/nanoseconds separately from Foundation Date. Date is used for calendar interpretation and display. Parsed one-to-nine-digit capture fractions, filesystem birth/mtime snapshots, fixed shifts and sequences use the exact representation for writing and verification.

On the development APFS volume, native tests verify exact unselected birth/mtime preservation during independent copies, metadata restoration and paired filesystem date changes. An unselected one-nanosecond external folder birth edit blocks own-change promotion and original-location recovery. Committing/retiring an unexpected original blocks stale-vault recovery for its whole asset group and retains both versions.

Actual bundled-engine tests verify JPEG, HEIC, PNG and MOV capture writes, exact resulting filesystem dates and unchanged media signatures, including the literal fraction `000000001`. A separate XMP sidecar transaction also checks the copied file dates and sidecar fraction. These are generated baseline fixtures; they do not qualify genuine RAW, HDR, depth, motion-photo or Live Photo variants.

Sequence ordering uses exact capture instants before the stable path tie-break. Local reports preserve exact UTC fractions when available and show expanded planned tag destinations. The inspector displays the same frozen tag destinations.

Shifts and sequence steps must be finite and representable in whole nanoseconds. Arithmetic overflow and smaller intervals are rejected. A target volume that cannot preserve the intended raw times rejects the staged operation before source replacement. There is no silent precision downgrade for unselected filesystem dates.

Earlier local recovery manifests without raw timestamp fields still decode and are checked at their recorded Date precision. Their original nanoseconds cannot be reconstructed retroactively. Absolute Date-only API sources are limited by the precision of that source; adding raw storage cannot create missing precision.

The native calendar input exposes seconds and uses the system zone shown beside it. Whole-second calendar edits avoid hidden fractions. Missing capture zones and QuickTime integer-date interpretation remain explicit choices. Embedded source offsets retain priority.

Native macOS 13, native Intel, other filesystem volumes and the graphical acceptance checklist remain separate required gates. Compilation, Rosetta, generated fixtures and model tests do not substitute for those checks.
