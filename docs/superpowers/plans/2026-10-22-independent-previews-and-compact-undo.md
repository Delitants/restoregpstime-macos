# Independent previews and compact undo Implementation Plan

> **For agentic workers:** Use scoped parallel work for independent table, metadata-qualification and backup domains; integrate and review each contribution, then review the whole branch. Steps use checkbox syntax.

**Goal:** Implement the approved per-tab preview/apply workflow, compact backup defaults, persistent settings and preview presentation.
**Architecture:** Cache typed preview components in AppModel and compose their frozen mutations in Core without re-running other components. Keep final source and destination validation. Store compact exact undo in a private per-batch database and keep legacy full-backup recovery compatible.
**Tech Stack:** Swift, SwiftUI/AppKit, macOS 13+, ImageIO/QuickLook, SQLite3, CryptoKit, existing bundled ExifTool runtime.
**Spec:** ../specs/2026-10-22-independent-previews-and-compact-undo-design.md (user approved in chat).

## Global Constraints
- Separate arm64 and x86_64 releases; self-signed preview distribution remains explicit.
- No writes to the user's remote media for qualification. Generated integration fixtures only.
- No silent skipping of selected actions, destination overwrites or weakened source/media verification.
- Keep failed evidence. User has already authorized implementation in this chat, publication and installation.
- Metadata backup is the new app default; legacy encoded/core policies default to full backup.

## Review Focus
- Source changes between cached tab previews and Apply; hash validation must still reject them.
- A destination folder selected after preview that changes collision/naming semantics.
- Crash or newer edits during commit, compact cleanup or per-file undo.
- Structural repeated HEIF tags versus conflicting editable fields and actual helper errors.
- Thumbnail work on remote files must stay lazy, bounded and cancellable.

## Task 1: Narrow HEIF structural-copy qualification
Files: MetadataDocument.swift, new focused Core tests. Ownership isolated from planner/table/backup work.
- [x] RED: normal HEIC codec repetitions accepted; changed occurrence multiset rejected; editable/unknown repetitions still block.
- [x] Implement a narrow structural allowlist. Existing complete multiset diff and media parsers remain required.
- [x] GREEN: provenance/metadata tests and generated HEIC write round-trip. Record real-media limit.
- [x] Review and commit only owned files.

## Task 2: Proposed columns and lazy thumbnails
Files: BatchTableView.swift, new ThumbnailProvider.swift / ThumbnailSize.swift, focused App tests if useful.
Interface: `enum ThumbnailSize: String, CaseIterable { case off, small, medium, large }` in app target; preference key `thumbnailSize` in UserDefaults. BatchTableView(model:selection:) remains unchanged.
- [x] RED: test bounded/cancelled thumbnail requests against generated files and cache behavior where production logic is meaningful.
- [x] Implement an AppKit table or equivalent native view: green proposed headers/cells, preserved sort/selection/full labels, 48/96/160-point optional thumbnails, Off default, lazy two-worker cached rendering.
- [x] Add a table-local thumbnail selector persisted using the named preference key; parent need not modify AppModel.
- [x] GREEN: compile, focused tests; native visual verification by parent after integration.
- [x] Review and commit only owned files.

## Task 3: Backup policies and compact exact undo
Files: Core Model/OperationRequest.swift, RecoveryRecord.swift, Transactions/BackupStore.swift, StageStore.swift, Committer.swift, RecoveryCoordinator.swift, HeldOriginalVerifier.swift, SecureFileSystem.swift (only as needed); new compact database/delta files and Core tests. RecoveryView/Browser integration may be proposed separately, parent owns UI until agreed.
Interface: `public enum BackupMode: String, Codable, Sendable { case metadata, full, none }`; `BatchOptions.backupMode: BackupMode?`, `effectiveBackupMode` treats nil as full. Parent sets new app default to .metadata. Public selected-file restore choice/API must be documented to parent.
- [x] RED: original file bytes and metadata restore exactly with compact mode; no full originals retained after commit; changed output rejected; none disallows completed undo; legacy full still works.
- [x] Implement bounded reverse delta and private SQLite metadata database with original/output hashes and raw original attributes. Set a defensible bound and fail before source commit when exceeded.
- [x] Capture compact backup before commit. Persist cleanup intent and remove only verified owned held originals after commit; interrupted operations retain safe recovery.
- [x] Restore via exact reconstruction with current output verification, all original attributes, and original paths. Support choosing independent files while keeping linked groups protected. Clean temporary media after successful compact undo.
- [x] GREEN: exact embedded rewrite undo, xattrs/dates/rename, all three policies, crash/compaction boundaries and changed-output refusal; keep assertions from existing transaction suites.
- [x] Review and commit only owned files.

## Task 4: Core component composition and deferred destination
Files: new Planning/PreviewComponent.swift and BatchPlanComposer.swift; BatchPlanner.swift, NameAllocator.swift, NameReservation.swift, PlanValidator.swift; focused Core tests. Parent owns these.
Interfaces: `PreviewComponent` cases dates/places/metadata/finder with `request(from:)` and `isSelected(in:)`; `BatchPlanComposer.combine(components:request:options:) async throws -> BatchPlan`; `bindDestination(_:to:) async throws -> BatchPlan`. Composition must not call capture-date or place resolvers.
- [x] RED: per-component requests exclude unrelated operations; combine exact date and place/name previews; reject source mismatches/duplicate tags/incompatible operations; unavailable destination never executes.
- [x] Extend planner with preview-only unresolved-destination support and optional cached fingerprints checked against current snapshots. Preserve default strict behavior for existing Core callers.
- [x] Add a provisional destination context that performs no destination writes or misleading existing-source collisions. Executor validation rejects unresolved plans.
- [x] Compose component mutation/tag/Finder data by stable source keys and linked membership; preserve cached names and dates. Qualify combined tag conflicts and blocked/excluded groups.
- [x] Bind deferred output by reserving the exact previewed names under selected root, checking actual volume/collisions and freezing anchors; do not regenerate dates/places or silently renumber.
- [x] GREEN: planner/naming/validation/composition tests.

## Task 5: App component cache, persistence and combined Apply UI
Files: AppModel.swift, LiveAppBackend.swift, WorkspaceView.swift, DestinationView.swift, AppSession.swift, InspectorView.swift, RecoveryView.swift; new AppPreferences.swift; App tests. Parent owns these.
Interfaces: `AppModel.preview(component:)`; existing `preview()` retained for legacy/test full-preview behavior. `AppModel.applyPreview()` executes only a current combined plan. Components are cached by scoped request and source/import revision. Live backend caches inspected fingerprints only with snapshot rechecks.
- [x] RED: location preview excludes dates, date preview retains prior names, navigation/no-op writes keep previews; editing one component only makes it stale; Apply combines selected current caches; missing component never silently applies.
- [x] Implement independent caches and shared projected rows. Keep prior visible results marked outdated while editing. Add selected-operation summary.
- [x] Rename button Apply Changes. Save copies opens folder picker only when needed; cancellation keeps previews. Bind cached results and show destination conflicts before any execution.
- [x] Persist filtered settings (request/options/discovery/appearance/tab/thumbnail preference) atomically; exclude imported sources, per-file state and executable plans. Load before initializing UI and preserve new metadata default.
- [x] Update backup picker and undo UI for per-file selection; make compact/no-backup limits clear.
- [x] Improve diagnostic text to include real helper diagnostics, separate successful lookup from embedded-write failure.
- [x] GREEN: AppModel/preferences/live backend tests and native UI close/reopen/tab switching checks.

## Task 6: Qualification and release
- [x] Full native regression and release-gate contract suite. Review all changes; fix demonstrated blockers with RED/GREEN evidence.
- [x] Native generated-media UI checks: deferred folder, independent caches, combined Apply/undo, green columns, all thumbnail sizes, persisted settings, full labels.
- [x] Build/sign/package arm64 and x86_64 with minOS13, pinned existing identity, all native component architecture/signature verification and archive readback.
- [x] Run Intel tests with explicit Rosetta XCTest runner (avoid known SwiftPM ARM discovery-helper issue).
- [x] Install safely, preserve prior copy in Trash, publish separate versioned previews and verify every uploaded/public archive hash. Update docs and report real-media/host limitations honestly.

## Execution ledger
- Spec approval: user selected Approve and implement in this chat. Builder check: nothing important left.
- Base: 80b133b plus approved design commit a6c0163. Existing isolated publication clone is reused; installed/public v0.1.2 remains available until qualified replacement.
- Ruling: cached component names remain stable; final destination conflicts block rather than silently renumber. Cost: user may choose a different folder or refresh the Location preview.
- Ruling: compact undo contains small restoration chunks as needed for byte-exact undo, not just exposed tag values. It depends on unchanged output media and has a bounded size, as stated in approved design.

- Integration review: four additional reproduced cache/root/collision findings resolved with focused generated regression tests; final reviewer readback approved their scope. Compact review finding for selected children under tracked ancestors resolved in ad5fd0f, 47 focused native tests pass.
- Final ARM native run: 269 Core (1 intentional skip), 46 App, 3 QA; no failures. Release gate contracts: 14/14. Evidence: work/independent-preview-implementation/full-native-final.log and release-gate-tests.log.
- Native QA: isolated app, generated JPEG/HEIC/MOV; folder-free preview, independent retained dates/names, cancelled destination picker retained previews, final combined copy Apply committed all 3, selected JPEG undo left other outputs, all thumbnail sizes, persisted Madrid fallback/metadata backup/Large size across close/reopen. Dark-mode screenshots retained. Host Go-to-Folder dialog automation later stalled; no user media was touched. Real remote batch remains unavailable.
- Version: 0.2.0 build 4. ARM and Intel release builds passed with deployment target 13.0; package and Intel test qualification follows.

- Final qualification: both architectures passed the 269 Core / 46 App / 3 QA suites with one intentional skip per architecture. Intel is Rosetta execution, not physical Intel. Fourteen release contract tests pass. Genuine GPS-bearing NRW checks passed on both signed runtimes, including compact in-place undo.
- Release source: 9b20a07761728af8365b34907ee7ef0318532a50. Both 0.2.0 tags and main pushed without force. Seven assets per release downloaded and SHA-256 verified; public ZIP downloads verified. Both previews published.
- Installed 0.2.0 build 4 in Applications after user closed 0.1.2, preserving the old copy in Trash. Signed app reopened; visible version, Off thumbnails and Madrid fallback read back across reopen. Light headers/controls checked; system appearance restored. No real user media was modified. Installation, qualification and publication receipts are retained in outputs/RestoreGPSTime-0.2.0 and outputs/RestoreGPSTime-0.2.0-Publication.
- Qualification limits remain explicit: remote 1,146-file batch unavailable; physical Intel/macOS 13 and genuine HDR/auxiliary layouts not qualified. Native Go-to-Folder automation stalled during an additional optional fixture-import pass; its dialog was dismissed by quitting the empty app session, and the app reopened ready. This did not block the earlier generated Apply/undo checks or programmatic signed-runtime checks.

- NRW qualification correction: initial in-place harness retained the legacy full policy. Explicit metadata-policy reruns passed on ARM and Intel/Rosetta; each required durable cleanup, no complete media retained, a 20,480-byte database for 3 RAW files, and exact undo. Preliminary logs remain retained; final output receipt includes this correction. No production code or release assets changed.
