# NRW Apply and Quarantine Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking. The user explicitly requested these fixes and reruns in this chat; execute inline.

**Goal:** Preserve downloaded RAW attributes exactly and complete native UI Apply without requesting read access to ancestor directories.

**Architecture:** Keep the existing descriptor-based transaction and verification model. Restore opaque quarantine bytes after the system metadata copy, and use search-only descriptors for directory traversal. Reuse these paths for staging, attribute archives, metadata restoration and recovery.

**Tech Stack:** Swift, Darwin public filesystem APIs, XCTest, packaged Perl/ExifTool and offline GeoNames database.

**Spec:** `Docs/superpowers/specs/2026-10-21-restoregpstime-design.md`, especially safe paths, exact attribute preservation, staging and undo. Current user request authorizes fixing both discovered failures and testing both architecture candidates.

## Global Constraints

- macOS 13+; separate arm64 and x86_64 app candidates.
- Never strip quarantine or change its flags, agent, event ID or timestamp to obtain a passing result.
- Keep exact hash/xattr/date checks and symlink rejection; preserve failed evidence and downloaded originals.
- Keep the UI layout and public operation options unchanged.
- Real GPS remains embedded in the original public P6000 NRW; no coordinate injection.
- Intel execution on this host is Rosetta, not physical Intel acceptance. No stable release publication during this repair.

## Review Focus

- Quarantined files must retain exact attribute bytes through copy, archive, restoration and undo.
- Existing unrelated xattrs, including binary values, remain identical.
- A searchable but unreadable ancestor must allow a transaction in its authorized child.
- Ancestor and leaf symlinks remain rejected, and directory sync must succeed.
- A native app must finish Apply using the selected output and undo folders; CLI success alone does not qualify it.

### Task 1: Exact quarantine preservation

**Files:** `Sources/RestoreGPSTimeCore/Transactions/SecureFileSystem.swift`, `Sources/RestoreGPSTimeCore/Metadata/FileAttributeArchive.swift`, new `Tests/RestoreGPSTimeCoreTests/QuarantinePreservationTests.swift`.

**Interfaces:** Existing `SecureFS.copy`, `SecureFS.applyMetadata`, `FileAttributeArchive.capture`; add one shared descriptor-based xattr-copy helper for these consumers.

- [ ] Add real filesystem tests: copy, archive and restoration retain literal `0081;5f5e1000;RestoreGPSTimeTests;00000000-0000-4000-8000-000000000001` quarantine bytes and an unrelated binary attribute. The source remains identical.
- [ ] Run `Scripts/test.sh --filter QuarantinePreservationTests` and retain expected verification failures.
- [ ] Implement bounded exact quarantine byte preservation after `fcopyfile`, without bypassing the final attribute equality check. Reuse the helper in all three consumers.
- [ ] Run the regression tests; expect all pass.

### Task 2: Search-only parent traversal

**Files:** `Sources/RestoreGPSTimeCore/Transactions/SecureFileSystem.swift`, new `Tests/RestoreGPSTimeCoreTests/SecureDirectoryTraversalTests.swift`.

**Interfaces:** `SecureFS.directory(_:create:mode:) -> Int32` remains unchanged. Its returned descriptor must support existing `openat`, `mkdirat`, `renameat`, `fsync` consumers.

- [ ] Add a filesystem regression where a `0300` ancestor contains a `0700` child: open/create a transaction descendant and sync it without granting ancestor read access. Add ancestor/leaf symlink rejection cases.
- [ ] Run `Scripts/test.sh --filter SecureDirectoryTraversalTests`; expect the unreadable-ancestor case to fail with the old read-only traversal.
- [ ] Use public `O_SEARCH` handles with `O_DIRECTORY`, `O_NOFOLLOW` and `O_CLOEXEC`, supported by the macOS 13 kernel headers. Preserve all existing validation and exclusive creation rules.
- [ ] Run both new regression classes, then the complete `Scripts/test.sh`; expect zero failures. Commit the focused source, tests and plan once green.

### Task 3: Candidate and real NRW verification

**Files:** ignored local QA harness/evidence and new user-facing reports/candidates in outputs; existing failure reports stay unchanged.

**Interfaces:** `Scripts/build-app.sh --arch ARCH --configuration release --output NEW_DIRECTORY`, existing NRW integration harness and exact newly built app bundles.

- [ ] Build fresh arm64 and x86_64 apps from the same clean source SHA; retain build logs and identities. Keep old apps intact.
- [ ] Run the public P6000 NRW tests for both packaged runtimes, retaining browser attributes: genuine GPS offline lookup, three numbered saved copies, three in-place renames and undo. Also retain the camera-like payload comparison scope.
- [ ] Independently verify original/output SHA-256, existing GPS, timestamps and exact xattrs including quarantine.
- [ ] Run native GUI Apply on both app versions using isolated NRW copies and selected output/undo folders. Verify all three published files and retained records, export reports/screenshots and close test apps normally.
- [ ] Review the focused diff and evidence, retain a source patch/candidate identities and final report. State physical Intel/macOS 13/signing limitations accurately.
