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
- [ ] RED: normal HEIC codec repetitions accepted; changed occurrence multiset rejected; editable/unknown repetitions still block.
- [ ] Implement a narrow structural allowlist. Existing complete multiset diff and media parsers remain required.
- [ ] GREEN: provenance/metadata tests and generated HEIC write round-trip. Record real-media limit.
- [ ] Review and commit only owned files.

## Task 2: Proposed columns and lazy thumbnails
Files: BatchTableView.swift, new ThumbnailProvider.swift / ThumbnailSize.swift, focused App tests if useful.
Interface: `enum ThumbnailSize: String, CaseIterable { case off, small, medium, large }` in app target; preference key `thumbnailSize` in UserDefaults. BatchTableView(model:selection:) remains unchanged.
- [ ] RED: test bounded/cancelled thumbnail requests against generated files and cache behavior where production logic is meaningful.
- [ ] Implement an AppKit table or equivalent native view: green proposed headers/cells, preserved sort/selection/full labels, 48/96/160-point optional thumbnails, Off default, lazy two-worker cached rendering.
- [ ] Add a table-local thumbnail selector persisted using the named preference key; parent need not modify AppModel.
- [ ] GREEN: compile, focused tests; native visual verification by parent after integration.
- [ ] Review and commit only owned files.

## Task 3: Backup policies and compact exact undo
Files: Core Model/OperationRequest.swift, RecoveryRecord.swift, Transactions/BackupStore.swift, StageStore.swift, Committer.swift, RecoveryCoordinator.swift, HeldOriginalVerifier.swift, SecureFileSystem.swift (only as needed); new compact database/delta files and Core tests. RecoveryView/Browser integration may be proposed separately, parent owns UI until agreed.
Interface: `public enum BackupMode: String, Codable, Sendable { case metadata, full, none }`; `BatchOptions.backupMode: BackupMode?`, `effectiveBackupMode` treats nil as full. Parent sets new app default to .metadata. Public selected-file restore choice/API must be documented to parent.
- [ ] RED: original file bytes and metadata restore exactly with compact mode; no full originals retained after commit; changed output rejected; none disallows completed undo; legacy full still works.
- [ ] Implement bounded reverse delta and private SQLite metadata database with original/output hashes and raw original attributes. Set a defensible bound and fail before source commit when exceeded.
- [ ] Capture compact backup before commit. Persist cleanup intent and remove only verified owned held originals after commit; interrupted operations retain safe recovery.
- [ ] Restore via exact reconstruction with current output verification, all original attributes, and original paths. Support choosing independent files while keeping linked groups protected. Clean temporary media after successful compact undo.
- [ ] GREEN: exact embedded rewrite undo, xattrs/dates/rename, all three policies, crash/compaction boundaries and changed-output refusal; keep assertions from existing transaction suites.
- [ ] Review and commit only owned files.

## Task 4: Core component composition and deferred destination
Files: new Planning/PreviewComponent.swift and BatchPlanComposer.swift; BatchPlanner.swift, NameAllocator.swift, NameReservation.swift, PlanValidator.swift; focused Core tests. Parent owns these.
Interfaces: `PreviewComponent` cases dates/places/metadata/finder with `request(from:)` and `isSelected(in:)`; `BatchPlanComposer.combine(components:request:options:) async throws -> BatchPlan`; `bindDestination(_:to:) async throws -> BatchPlan`. Composition must not call capture-date or place resolvers.
- [ ] RED: per-component requests exclude unrelated operations; combine exact date and place/name previews; reject source mismatches/duplicate tags/incompatible operations; unavailable destination never executes.
- [ ] Extend planner with preview-only unresolved-destination support and optional cached fingerprints checked against current snapshots. Preserve default strict behavior for existing Core callers.
- [ ] Add a provisional destination context that performs no destination writes or misleading existing-source collisions. Executor validation rejects unresolved plans.
- [ ] Compose component mutation/tag/Finder data by stable source keys and linked membership; preserve cached names and dates. Qualify combined tag conflicts and blocked/excluded groups.
- [ ] Bind deferred output by reserving the exact previewed names under selected root, checking actual volume/collisions and freezing anchors; do not regenerate dates/places or silently renumber.
- [ ] GREEN: planner/naming/validation/composition tests.

## Task 5: App component cache, persistence and combined Apply UI
Files: AppModel.swift, LiveAppBackend.swift, WorkspaceView.swift, DestinationView.swift, AppSession.swift, InspectorView.swift, RecoveryView.swift; new AppPreferences.swift; App tests. Parent owns these.
Interfaces: `AppModel.preview(component:)`; existing `preview()` retained for legacy/test full-preview behavior. `AppModel.applyPreview()` executes only a current combined plan. Components are cached by scoped request and source/import revision. Live backend caches inspected fingerprints only with snapshot rechecks.
- [ ] RED: location preview excludes dates, date preview retains prior names, navigation/no-op writes keep previews; editing one component only makes it stale; Apply combines selected current caches; missing component never silently applies.
- [ ] Implement independent caches and shared projected rows. Keep prior visible results marked outdated while editing. Add selected-operation summary.
- [ ] Rename button Apply Changes. Save copies opens folder picker only when needed; cancellation keeps previews. Bind cached results and show destination conflicts before any execution.
- [ ] Persist filtered settings (request/options/discovery/appearance/tab/thumbnail preference) atomically; exclude imported sources, per-file state and executable plans. Load before initializing UI and preserve new metadata default.
- [ ] Update backup picker and undo UI for per-file selection; make compact/no-backup limits clear.
- [ ] Improve diagnostic text to include real helper diagnostics, separate successful lookup from embedded-write failure.
- [ ] GREEN: AppModel/preferences/live backend tests and native UI close/reopen/tab switching checks.

## Task 6: Qualification and release
- [ ] Full native regression and release-gate contract suite. Review all changes; fix demonstrated blockers with RED/GREEN evidence.
- [ ] Native generated-media UI checks: deferred folder, independent caches, combined Apply/undo, green columns, all thumbnail sizes, persisted settings, full labels.
- [ ] Build/sign/package arm64 and x86_64 with minOS13, pinned existing identity, all native component architecture/signature verification and archive readback.
- [ ] Run Intel tests with explicit Rosetta XCTest runner (avoid known SwiftPM ARM discovery-helper issue).
- [ ] Install safely, preserve prior copy in Trash, publish separate versioned previews and verify every uploaded/public archive hash. Update docs and report real-media/host limitations honestly.

## Execution ledger
- Spec approval: user selected Approve and implement in this chat. Builder check: nothing important left.
- Base: 80b133b plus approved design commit a6c0163. Existing isolated publication clone is reused; installed/public v0.1.2 remains available until qualified replacement.
- Ruling: cached component names remain stable; final destination conflicts block rather than silently renumber. Cost: user may choose a different folder or refresh the Location preview.
- Ruling: compact undo contains small restoration chunks as needed for byte-exact undo, not just exposed tag values. It depends on unchanged output media and has a bounded size, as stated in approved design.
