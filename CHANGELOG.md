# Changelog

## 0.1.1 — self-signed preview

- Counted progress for metadata reading, file-content checks and planning, with cancellation and stale-update protection.
- Read metadata in batches of up to 32 files, with at most two helpers. Validate each response against its requested source and recover individual files after a batch failure.
- Review blocked reasons grouped by affected asset count. Offset-free capture dates require an explicit camera time zone; existing metadata offsets retain priority.
- Retain full source fingerprints and all pre-commit checks. File-content checking still depends on the drive and media sizes.

## 1.0.0 — unreleased

Original native macOS interface; separate ARM64 and x86_64 builds targeting macOS 13.

- Restore creation/modification dates from capture metadata, offsets, reference files, filenames, fixed/current dates, shifts and sequences; preserve exact supported fractions.
- Offline approximate city/country lookup, bounded radius, alternative candidates and manual corrections; qualified comments/structured fields and collision-safe place-based names.
- Frozen batch previews, Save Copies, recoverable in-place transactions, partial reports and explicit recovery.
- Qualified metadata/GPS removal and descriptive edits, Finder attributes, separate scoped system Trash, Finder visibility Tools, data-only workflows, Services and review-first droplets.

Stable release is pending native hardware/OS, genuine-media, UI/OS integration, performance trace, distribution signing and notarization acceptance. Generated fixtures and Rosetta are labeled development evidence.
