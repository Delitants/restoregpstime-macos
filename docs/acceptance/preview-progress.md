# Preview progress and blocked-date guidance

Version 0.1.1 adds counted metadata-reading, source-fingerprint and group-planning progress. File discovery, dependency checks and filename allocation show their current stage without inventing a percentage. Updates are coalesced to at most ten per second between stage transitions/completion, and stale callbacks cannot replace the status of a cancelled or changed preview.

Metadata inspection batches at most 32 files per helper, with at most two chunks active. Every JSON record must match its requested source path and order. Batch-level failures fall back to individual reads, preserving per-file diagnostics; cancellation stops this fallback. A nonzero helper exit is accepted as a per-file failure only for ExifTool's file-error status with an explicit error record, not merely a warning.

The blocked-reasons sheet counts distinct affected groups per reason. A group can appear under several reasons. No default camera time zone is guessed. Version 0.1.2 enables automatic GPS city time zones in new app sessions, with one selected batch fallback for files without usable GPS. Embedded UTC offsets keep priority. Linked assets are still applied as protected groups, so the group count can differ from the file count.

Full source fingerprints, dependency identities and pre-commit revalidation remain enabled. Preview can therefore take time on external drives, network volumes or large media. The progress bar counts completed files within each stage and can pause while one large file is read; it is not a whole-operation time estimate.

## Measurements and limits

On the development Apple Silicon Mac, 24 repeated generated baseline HEIC entries took 2.507 seconds using individual helpers (maximum two concurrent) and 0.334 seconds using one batch helper. All decoded metadata matched. This measures helper startup amortization, not a user's media set or full preview throughput.

The 65-file generated import regression, including one empty unreadable file, took 4.417 seconds on the old path and 0.904 seconds on the new path in the recorded runs. It preserved the 64 good JPEG documents, isolated the empty file's error and left source fingerprints unchanged. Timing depends on host load, storage and metadata.

Native UI checks used an isolated app identifier and generated fixtures. A sparse large-file preview displayed a moving counted progress bar and cancelled without applying changes. A two-file timezone example changed from one eligible/one blocked group to two eligible/zero blocked after selecting Europe/Paris; the embedded-offset HEIC's proposed instant stayed unchanged. Buttons were readable in the 1100-point-wide window. No user's media was applied in these checks.

Regression coverage includes exact source mapping, malformed batches, per-file error isolation, unexplained nonzero exits, active and queued helper cancellation, child termination, permit recovery, cancelled-import fallback suppression, stale callbacks after cancel/reimport, grouped blocking reasons and unchanged source fingerprints.

Physical Intel hardware, macOS 13 execution and the full Instruments performance acceptance remain separate pending gates. Intel execution through Rosetta must be labelled as such. The preview remains self-signed and unnotarized.
