# RestoreGPSTime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans, or superpowers:subagent-driven-development if the user chooses delegation, to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build RestoreGPSTime for macOS 13+, with offline date/place recovery, the reference attribute tools, recoverable batch changes and separate verified Apple Silicon and Intel releases.

**Architecture:** A Swift package separates a testable core from a native SwiftUI/AppKit app and droplet executable. Bundled ExifTool runs under a pinned, architecture-matched Perl runtime. Immutable previews feed a journaled stage/verify/commit engine; UI and integrations cannot bypass that engine.

**Tech Stack:** Swift tools 5.9 / Swift 5 language mode; SwiftUI, AppKit, Foundation, CryptoKit, ImageIO, AVFoundation and Darwin; ExifTool 13.59; Perl 5.44.0; bundled standard ExifTool/GeoNames database; XCTest; shell/Python build and evidence scripts.

**Spec:** [RestoreGPSTime Specification](../specs/2026-10-21-restoregpstime-design.md). Read it, [the action matrix](../../acceptance/reference-actions.csv) and [the Tools matrix](../../acceptance/reference-tools.csv) before executing this plan.

Status: written for review. No task below has been implemented or tested. The user authorized writing the specification and plan; implementation starts after their review and execution-method choice.

## Global Constraints

- Product name: `RestoreGPSTime`.
- Minimum OS: `macOS 13.0` on `arm64` and `x86_64`.
- UI: native `SwiftUI` and `AppKit`; original branding and artwork.
- Repository target: `Delitants/restoregpstime-macos`.
- App bundle identifier: `io.github.delitants.RestoreGPSTime`.
- Location lookup: offline only; bundle the ExifTool city database and its attribution.
- Metadata backend: bundled ExifTool and an architecture-matched bundled Perl runtime; no Homebrew or separate runtime installation for users.
- Default save mode: `Save Copies`; alternate: `Modify in Place` with retained originals.
- No unrelated destination is overwritten, and no source is mutated during preview.
- Public release tags: `v1.0.0-arm64` and `v1.0.0-x86_64`, from the same reviewed source commit.
- Source code license: MIT for original code; retain each dependency's own notices and license.
- No product implementation, external repository creation, or publication occurs as part of writing these documents.

The final constraint describes this planning turn; it does not prohibit later user-approved execution of T01–T13. Do not silently replace an unavailable dependency, minimum OS, safety rule or release gate. Propose the specific change with evidence first.

## Review Focus

1. EXIF wall clocks without offsets, DST ambiguity and QuickTime UTC/local camera dates must resolve identically on different host timezones: T03.
2. Same-place names colliding through case, Unicode normalization, existing outputs or linked Live Photo/sidecar members must never overwrite another item: T05/T07.
3. A crash, full disk or external edit between preview and commit must leave a recoverable original and must never restore over a newer external edit: T07.
4. HEIF auxiliary/HDR/depth data, RAW rendering metadata and MOV tracks must survive descriptive edits; unsupported stripping must be blocked: T08/T12.
5. A quarantined, relocated Intel or ARM64 app must work offline without Homebrew/system Perl, and an incomplete qualification must keep publication closed: T01/T12/T13.

## File structure and ownership

All paths below are relative to the new local repository at `outputs/RestoreGPSTime/`. That repository currently contains only planning documents. `work/`, `.build/`, dependency build products and local qualification media are ignored. User-facing release artifacts are exported into `outputs/releases/` inside this repository only after qualification.

```text
Package.swift                     Core, App, Droplet, QA and XCTest targets
App/Info.plist                    Document/Services registration and bundle metadata
App/Resources/                    Original app icon and local UI resources
Sources/RestoreGPSTime/           App entry, models, views, Services and document import
Sources/RestoreGPSTimeDroplet/    Small native workflow-to-main-app handoff
Sources/RestoreGPSTimeQA/         Developer-only qualification command; not shipped in app
Sources/RestoreGPSTimeCore/
  Model/                         Shared versioned records and typed requests
  Runtime/                       Bundled runtime locator, Process runner and diagnostics
  Discovery/                     File identity, inventory, metadata and capability parsing
  Dates/                         Capture candidates, timezone/date policies and reference dates
  Places/                        Offline database lookup, corrections and location tag plans
  Naming/                        Asset groups, templates, ordering and reservations
  Planning/                      Immutable plans and semantic validation
  Transactions/                  Backups, journals, commits, recovery and event stream
  Metadata/                      Stage-only writing, tag profiles and integrity validation
  Attributes/                    Filesystem dates, Finder flags and scoped Trash operations
  Workflows/                     Workflow JSON and droplet export validation
  Resources/                     Curated container/tag registries
Dependencies/dependencies.lock.json   Exact source URLs, digests and build settings
ThirdParty/                      Licenses/provenance; downloaded source policy in T01
Tests/RestoreGPSTimeCoreTests/    Unit, engine and filesystem integration tests
Tests/RestoreGPSTimeAppTests/     Main-actor model/integration tests
Tests/Fixtures/manifest.json     Provenance and expected properties for lawful fixtures
Scripts/                         Dependency, bundle, qualification and release scripts
docs/acceptance/                 Action matrix, format evidence and manual UI checks
docs/superpowers/                This reviewed specification and plan
```

The app uses the core package; the core never imports SwiftUI. Keep one responsibility per file. Add new format validators as focused files rather than expanding one central metadata controller.

## Interface conventions and test support

Shared records named in the spec are defined once under `Model/`; do not create near-duplicate UI models with different meanings. IDs are UUIDs. `TagID` is a validated group-qualified tag identifier; `TagValue` is a typed scalar/list/language map. `ContentHash` is a lowercase SHA-256 hex string. All thrown core errors use `RestoreError`, with a code, operation/item context and user-readable detail. Unless a full path is given, paths beginning `Model/`, `Runtime/`, `Discovery/`, `Dates/`, `Places/`, `Naming/`, `Planning/`, `Transactions/`, `Metadata/`, `Attributes/`, `Workflows/` or `Resources/` are relative to `Sources/RestoreGPSTimeCore/`. Test and app paths are always rooted explicitly.

`DateResolution` contains the chosen source, resolved instant, precision and interpretation. `SourceChoice` includes the spec's automatic and explicit sources. `PlaceQuery` contains latitude/longitude, `maxDistanceKM` and `limit`; `PlaceCorrection` contains selected/manual names. `NameReservation` contains group/member IDs, final URL and collision key. `MutationPlan` contains explicit tag mutations, expected filesystem attributes and required integrity profile. `StageResult` carries the verified stage URLs and verification evidence. `ContainerProfile` identifies a detected container/variant; `CapabilityDecision` carries supported/blocked status and reason.

`BatchOptions` contains save mode, selected roots, inclusions and all visible policy choices. `RunOptions` supplies the cancellation token and journal location, not new mutations. `RecoveryChoice` is `originalLocations` or `separateFolder(URL)`. `RecoveryOutcome`, `ImportOutcome` and `QualificationResult` are explicit result records, never Boolean success flags that discard partial failures. `Clock` supplies a frozen `now()` for tests. `SourceFingerprint` adds a streaming content hash to `FileSnapshot` identity/attributes.

T01 creates `Tests/RestoreGPSTimeCoreTests/Support/CoreTestCase.swift` with a per-test temporary directory, `fixture(_ id: String) throws -> URL`, `utc(_ iso8601: String) throws -> Date`, and cleanup restricted to that test directory. T02 adds typed fixture metadata builders. T07 adds fault injection at named transaction phases. These are test-only helpers, not product bypasses. Assertions below describe tests to write during execution; none have been run while planning.

Execute tasks in order. Each task is an independently reviewable deliverable with its own red/green cycle. Commit only that task's reviewed files and relevant updated documentation. Use explicit paths when staging; never `git add .` around local/private fixtures.

---

### T01: Prove the native baseline and bundled runtime

**Files:** Create `Package.swift`, `.gitignore`, `App/Info.plist`, `Sources/RestoreGPSTime/AppMain.swift`, `Sources/RestoreGPSTimeCore/Runtime/{RuntimeLocator,ProcessRunner,RuntimeProbe}.swift`, `Sources/RestoreGPSTimeCore/Model/RestoreError.swift`, `Dependencies/dependencies.lock.json`, `Scripts/{prepare-dependencies,build-runtime,build-app}.sh`, `ThirdParty/NOTICES.txt`, `Tests/Fixtures/manifest.json`, `Tests/RestoreGPSTimeCoreTests/{RuntimeTests,Support/CoreTestCase}.swift`.

**Interfaces:**
- Produces `RuntimeLocator.locate(in appBundle: URL) throws -> RuntimePaths`, where paths identify the bundled interpreter, modules, ExifTool script and database.
- Produces `ProcessRunner.run(executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval) async throws -> ProcessResult`; the result retains exit status, bounded stdout/stderr and duration.
- Produces `RuntimeProbe.inspect(paths: RuntimePaths) async throws -> RuntimeIdentity`; identity includes versions, source hashes and current machine architecture.
- The initial app only opens a native window and reports runtime availability locally; it does not mutate files.

- [ ] **1. Establish only the package/test shell, then write failing runtime tests.** Set `.macOS(.v13)`, Swift language version 5, and core/app targets. Test `testBundleRuntimeWorksWithoutSystemPerl`, `testHostileEnvironmentIsIgnored`, `testUnicodeRelocation`, `testStderrFloodDoesNotDeadlock`, and `testArchitectureAndDeploymentTarget`.
  Assertions: `XCTAssertEqual(identity.exifToolVersion, "13.59")`; `XCTAssertEqual(identity.perlVersion, "5.44.0")`; `XCTAssertFalse(identity.loadedPaths.contains { $0.hasPrefix("/opt/homebrew") })`; a hostile `PERL5OPT`/user ExifTool config cannot execute a marker command; a cancelled/flooding helper returns a bounded error without deadlock.
- [ ] **2. Run the focused tests and retain the expected red result.** `swift test --filter RuntimeTests`; failures must concern the missing/incorrect bundled runtime contract, not unrelated fixture paths or permissions.
- [ ] **3. Implement the runtime and minimal native bundle.** Obtain the pinned sources from official publishers, verify their published provenance/digests and record SHA-256 before use. Build Perl separately for each architecture with deployment target 13.0; bundle its needed modules/libraries and ExifTool/data. Disable user configs and ambient Perl module injection. Generate lawful basic JPEG/HEIC/MOV fixtures with recorded synthetic coordinates; do not ingest personal files. Stop and report an incompatible/unavailable pin instead of using host Perl. The assembly script supports `--arch`, `--configuration` and `--output`.
- [ ] **4. Verify the actual assembled app.** Run the focused tests, `Scripts/build-app.sh --arch arm64 --configuration debug --output work/build/arm64`, and the corresponding `x86_64` build. Inspect `file`, `lipo -archs`, `otool -L` and `vtool -show-build` for all native components. Launch ARM64 locally; label Intel execution through Rosetta separately. Repeat the runtime probe from a moved Unicode/spaced app path with network and host Perl access unavailable in the test harness. Record logs in `work/evidence/T01/`.
- [ ] **5. Commit the baseline.** Stage the exact files above, notices and fixture provenance; commit `build: establish native app and bundled metadata runtime`. No external repository is created.

### T02: Read metadata and discover operation capabilities

**Files:** Create `Model/{FileSnapshot,MetadataDocument,MetadataMutation,Capabilities}.swift`, `Discovery/{SourceInventory,FileIdentityReader,MetadataReader,MetadataDecoder,CapabilityRegistry}.swift`, `Resources/container-capabilities.json`, `Tests/RestoreGPSTimeCoreTests/{DiscoveryTests,MetadataReaderTests,CapabilityTests}.swift`, `Tests/RestoreGPSTimeCoreTests/Support/MetadataFixtures.swift`.

**Interfaces:**
- Consumes T01 runtime interfaces.
- Produces `SourceInventory.scan(urls: [URL], options: DiscoveryOptions) async -> DiscoveryResult`; options contain recursion, file/folder inclusion and excluded output/recovery roots. Results retain excluded/unavailable-item reasons.
- Produces `FileIdentityReader.snapshot(at url: URL) throws -> FileSnapshot` and `fingerprint(at url: URL) throws -> SourceFingerprint`.
- Produces `MetadataReader.read(snapshot: FileSnapshot) async throws -> MetadataDocument`.
- Produces `CapabilityRegistry.decision(for operation: OperationKind, document: MetadataDocument, snapshot: FileSnapshot) -> CapabilityDecision`.
- Defines `SourceID`/`SourceFingerprint` in `FileSnapshot.swift`; `InspectedItem`/`DiscoveryResult`/`DiscoveryOptions` in `SourceInventory.swift`; `OperationKind`/`ContainerProfile`/`CapabilityDecision` in `Capabilities.swift`; and `TagID`/`TagValue`/`TagMutation` in `MetadataMutation.swift`. These are typed contracts, not write capability grants.

- [ ] **1. Write failing tests.** `testDuplicateGroupsAreRetained`, `testExtensionDoesNotDecideWriteSupport`, `testSymlinkHardlinkPackageAndPlaceholderRules`, `testOutputInsideInputIsExcluded`, `testReadOnlyVideoStillAllowsDateRestore`, `testNewlineAndLeadingDashPaths`.
  Assertions: two source tags named CreateDate remain distinct; symlink targets are never opened; duplicate inode inputs produce one physical entry; `capability(.embeddedWrite, mkv).isSupported == false` while readable metadata remains available; reading a filename containing a newline does not create an extra helper argument/file operation.
- [ ] **2. Verify red.** `swift test --filter 'DiscoveryTests|MetadataReaderTests|CapabilityTests'`; retain failures that demonstrate the missing behavior.
- [ ] **3. Implement discovery/read contracts.** Use no-follow identity checks, bounded parallel reads and group-qualified ExifTool JSON. Inspect file signatures/container features, not extension alone. Preserve unknown metadata for display without granting it write permission. Start write profiles disabled until verified. Add a streaming SHA-256 fingerprint and preserve read/parse/timeout diagnostics.
- [ ] **4. Verify green on real temporary files and bundled-engine fixtures.** Repeat focused tests. Assert before/after source bytes, birth/modification dates and Finder/xattr state match for inspection; count active helpers and assert `maximumActive <= 2`.
- [ ] **5. Commit.** `feat: inspect files and expose per-operation capabilities` with only the listed production/tests/registry changes.

### T03: Resolve capture dates and all reference date sources

**Files:** Create `Model/{CaptureCandidate,DatePolicy,DateResolution,Clock}.swift`, `Dates/{CaptureDateResolver,WallClockParser,TimezoneResolver,ReferenceDateResolver,FilenameDateParser,DateMutationPlanner}.swift`, `Tests/RestoreGPSTimeCoreTests/{CaptureDateTests,TimezoneTests,ReferenceDateTests}.swift`.

**Interfaces:**
- Consumes `MetadataDocument`, `FileSnapshot`, `Clock` and source-selection records.
- Produces `CaptureDateResolver.resolve(document: MetadataDocument, snapshot: FileSnapshot, policy: DatePolicy) throws -> DateResolution`.
- Produces `ReferenceDateResolver.resolve(source: SourceChoice, snapshot: FileSnapshot, context: ReferenceDateContext) async throws -> DateResolution`; context includes explicitly selected roots/patterns and the frozen clock.
- Produces `DateMutationPlanner.plan(resolution: DateResolution, policy: DatePolicy, snapshot: FileSnapshot, sequenceIndex: Int) throws -> DateMutation`.
- Defines `SourceChoice`/`DateMutation` in `DatePolicy.swift`, `ReferenceDateContext` in `ReferenceDateResolver.swift`, and `Clock.now() -> Date` in `Clock.swift`.

- [ ] **1. Write failing tests for A01–A17/A05 source options.** `testExplicitOffsetWins`, `testUnzonedRequiresSelection`, `testFallBackNeedsOccurrenceChoice`, `testSpringGapBlocks`, `testQuickTimeIntegerNeedsInterpretation`, `testCurrentTimeIsFrozen`, `testReferenceHierarchyAmbiguity`, `testFilenameRejectsInvalidCalendarDate`, `testResetValueAndCompanionDate`.
  Assertions: `2024:01:02 03:04:05+02:00` resolves to `2024-01-02T01:04:05Z`; an unzoned candidate returns `.timezoneRequired`; New York `2024-11-03 01:30` has two explicit choices; `2024-03-10 02:30` blocks; reset resolves exactly to `1904-01-01T00:00:00Z`; a duration day equals 86400 seconds. Repeat resolutions with host TZ UTC and Honolulu and assert equality.
- [ ] **2. Verify red.** `swift test --filter 'CaptureDateTests|TimezoneTests|ReferenceDateTests'`.
- [ ] **3. Implement the specified source orders and policies.** Parse without host-locale assumptions. Add all reference menu source families, explicit numeric filename patterns, unique hierarchy matching, seconds-based shift/sequence operations, and delete/reset plans. Do not enable a new GPS-clock feature merely because of the app's new name. Missing Spotlight properties remain unavailable. Encode required companion-date normalization as a visible decision.
- [ ] **4. Verify green and real tag round trips for available date sources.** Repeat focused tests with explicit source and fallback selection; assert the plan records tag, chosen instant, offset/zone policy and fractional precision. Use representative QuickTime fixtures whose UTC/local interpretations differ by a known offset.
- [ ] **5. Commit.** `feat: resolve capture dates with explicit timezone policies`.

### T04: Resolve offline places and plan location metadata

**Files:** Create `Model/{PlaceMatch,PlaceQuery}.swift`, `Places/{OfflinePlaceResolver,PlaceCorrectionStore,LocationTagPlanner}.swift`, `Tests/RestoreGPSTimeCoreTests/{OfflinePlaceTests,LocationTagPlanTests}.swift`.

**Interfaces:**
- Consumes T01 database/runtime identity, validated GPS in `MetadataDocument`, and T02 capabilities.
- Produces `OfflinePlaceResolver.lookup(_ query: PlaceQuery) async throws -> [PlaceMatch]` and `resolve(document: MetadataDocument, correction: PlaceCorrection?, queryDefaults: PlaceQueryDefaults) async throws -> [PlaceMatch]`.
- Produces `LocationTagPlanner.plan(match: PlaceMatch, document: MetadataDocument, options: LocationWriteOptions) throws -> [TagMutation]`.
- Defines `PlaceCorrection`/`PlaceQueryDefaults` in `PlaceQuery.swift` and `LocationWriteOptions` in `LocationTagPlanner.swift`.

- [ ] **1. Write failing tests.** `testParisOffline`, `testDistanceAndLimitDefaults`, `testMissingAndConflictingGPS`, `testZeroCoordinatesAreValidButNoNearbyMatch`, `testBorderCandidatesStayApproximate`, `testCorrectionProvenance`, `testAppendOncePreservesExistingComment`, `testPhotoAndVideoUseQualifiedDestinations`.
  Assertions: synthetic Paris coordinates return country code `FR` with a displayed database identity/distance; `maxDistanceKM == 25` and `limit == 3`; missing GPS cannot silently use an existing city string as coordinate evidence; repeated append adds `Paris, France` once; manual corrections carry `.manual` provenance; a video is never promised an EXIF UserComment write when unsupported.
- [ ] **2. Verify red.** `swift test --filter 'OfflinePlaceTests|LocationTagPlanTests'`.
- [ ] **3. Implement database-only lookup and typed location plans.** Pass explicit coordinates rather than ExifTool's fallback city-name inference. Preserve distance/country ambiguity and raw GPS. Store corrections in batch state/workflow settings only as explicitly chosen settings; use the spec's precise append/replace behavior and qualified destination profiles.
- [ ] **4. Verify green with network denied to the app/runtime.** Re-run the focused tests using the bundled database; record the data version and assert no network client is constructed. Missing database must error rather than switch to a service. Review attribution text and reports.
- [ ] **5. Commit.** `feat: recover nearest place names offline`.

### T05: Group linked assets and reserve collision-safe names

**Files:** Create `Model/{AssetGroup,NameReservation}.swift`, `Naming/{AssetGrouper,NameTemplate,NameAllocator,VolumeNamingRules}.swift`, `Tests/RestoreGPSTimeCoreTests/{AssetGroupTests,NameAllocatorTests}.swift`.

**Interfaces:**
- Consumes snapshots/documents, optional resolved dates and places.
- Produces `AssetGrouper.group(items: [InspectedItem], overrides: GroupOverrides) throws -> [AssetGroup]`.
- Produces `NameAllocator.reserve(groups: [AssetGroup], destinations: DestinationContext, template: NameTemplate) throws -> [NameReservation]`; destination context contains observed case/normalization/length rules and existing entries.
- Defines `GroupOverrides` in `AssetGroup.swift`, and `DestinationContext` in `NameReservation.swift`.

- [ ] **1. Write failing tests.** `testSamePlaceIncrementsByStableOrder`, `testLivePhotoAndSidecarShareBase`, `testUnrelatedSameStemIsNotLivePhoto`, `testCaseAndUnicodeCollision`, `testExistingNameAdvancesSequence`, `testCrossRootCollision`, `testInvalidComponentsAndLength`, `testCaseOnlyRenameAndCycles`.
  Assertions: first two independent Paris assets receive `France - Paris - 0001.HEIC` and `France - Paris - 0002.MOV`; a confirmed HEIC+MOV pair shares `0001`; decomposed/composed forms and mixed-case names collide on the corresponding volume; no destination key appears twice; an occupied `0001` reserves `0002` without replacing it.
- [ ] **2. Verify red.** `swift test --filter 'AssetGroupTests|NameAllocatorTests'`.
- [ ] **3. Implement grouping, template grammar and reservations.** Use identifier evidence for Live Photos and explicitly bounded same-stem sidecar rules. Apply the spec's sorting, NFC/volume collision keys, suffix allocation and path-component restrictions. Return intermediate path requirements for case-only/name-cycle commits; do not execute renames here.
- [ ] **4. Verify green.** Re-run the focused tests on case-sensitive and case-insensitive APFS test volumes where available; label injected volume-rule tests separately from actual filesystem evidence. Property-test that adding no inputs and changing no options produces identical reservations.
- [ ] **5. Commit.** `feat: plan linked-asset renames without overwrites`.

### T06: Freeze preview plans and mutation contracts

**Files:** Create `Model/{OperationRequest,MutationPlan,BatchPlan,BatchEvent}.swift`, `Planning/{BatchPlanner,PlanValidator}.swift`, `Transactions/MutationDriver.swift`, `Tests/RestoreGPSTimeCoreTests/{BatchPlannerTests,PlanValidationTests}.swift`.

**Interfaces:**
- Consumes T02–T05 outputs.
- Produces `BatchPlanner.preview(items: [InspectedItem], request: OperationRequest, options: BatchOptions) async throws -> BatchPlan`.
- Produces `PlanValidator.revalidate(_ plan: BatchPlan) async -> PlanValidationResult`.
- Defines `MutationDriver.apply(_ mutation: MutationPlan, to stage: URL) async throws -> StageVerification` and `restoreAttributes(_ snapshot: FileSnapshot, to stage: URL) async throws` for transaction execution. T07 uses a test driver; T08/T09 supply production behavior.
- Defines `BatchOptions`/`OperationRequest` in `OperationRequest.swift`; `PlannedItem`/`PlannedGroup`/`PlanValidationResult` in `BatchPlan.swift`; and `StageVerification`/`AllowedMetadataChanges` in `MutationDriver.swift`. A no-content-change mutation verifies a content hash; an embedded write requires a profile-specific integrity validator.

- [ ] **1. Write failing tests.** `testPreviewNeverMutatesSource`, `testOptionsInvalidatePreview`, `testUnsupportedCompoundOperationBlocksGroup`, `testSidecarRequiresExplicitChoice`, `testCurrentTimeAndOrderingAreFrozen`, `testTrashCannotCombineWithOtherMutations`, `testIdentityOrContentChangeConflicts`.
  Assertions: preview leaves data/attributes unchanged; the options digest changes for a timezone/name correction; unsupported embedded output never becomes an implicit XMP sidecar; planned sibling destinations remain reserved even when another group fails; a changed source hash yields `.conflict` before any mutation driver call.
- [ ] **2. Verify red.** `swift test --filter 'BatchPlannerTests|PlanValidationTests'`.
- [ ] **3. Implement immutable plan generation and typed validation.** Capture all policy values, resolved dates/place corrections, group order, dependency identity, expected diffs and no-overwrite destinations. Separate eligible/excluded/blocked rows. A blocked requested mutation blocks its whole group until the user explicitly changes/excludes it; preserve valid independent groups. Re-preview is required after edits.
- [ ] **4. Verify green.** Repeat focused tests; serialize/deserialize schema-1 plans and assert semantic equality. Confirm source changes, a different engine/database identity and new destination collisions invalidate execution rather than causing unpreviewed fallbacks.
- [ ] **5. Commit.** `feat: freeze auditable batch previews`.

### T07: Implement staged changes, journals and safe recovery

**Files:** Create `Transactions/{BatchExecutor,RecoveryJournal,BackupStore,StageStore,Committer,RecoveryCoordinator,SourceRevalidator}.swift`, `Model/RecoveryRecord.swift`, `Tests/RestoreGPSTimeCoreTests/{CopyModeTests,InPlaceTests,CrashRecoveryTests,CancellationTests}.swift`, `Tests/RestoreGPSTimeCoreTests/Support/TransactionFaults.swift`; modify `Model/BatchEvent.swift` to add the completed group/report records.

**Interfaces:**
- Consumes immutable plans and `MutationDriver` from T06.
- Produces `BatchExecutor.execute(_ plan: BatchPlan, options: RunOptions) -> AsyncStream<BatchEvent>` and `cancel(batchID: UUID)`.
- Produces `RecoveryJournal.persist(_ record: RecoveryRecord) throws`, `incompleteRecords() throws -> [RecoveryRecord]` and `RecoveryCoordinator.restore(batchID: UUID, choice: RecoveryChoice) async throws -> RecoveryOutcome`.
- Produces `Committer.commit(group: PlannedGroup, stages: StageResult, journal: RecoveryJournal) async throws -> GroupResult`; all filesystem primitives remain inside this boundary.
- Defines `RunOptions` in `BatchExecutor.swift`; `StageResult` in `StageStore.swift`; `GroupResult`/`BatchReport` in `BatchEvent.swift`; and `RecoveryChoice`/`RecoveryOutcome` in `RecoveryRecord.swift`. Directory actions journal restorable metadata and run after descendants; they do not recursively copy an entire directory as an original.

- [ ] **1. Write failing filesystem/fault tests.** `testCopiesPreserveSources`, `testBackupBeforeFirstMutation`, `testCrashAtEveryPersistedPhase`, `testDiskFullAndJournalSyncFailure`, `testExternalEditBeforeCommit`, `testRecoveryNeverOverwritesNewerEdit`, `testGroupFailureRestoresLinkedMembers`, `testNoReplaceAtCommit`, `testCancelDuringStageAndCommit`, `testHardlinksSymlinksACLsAndLocks`.
  Assertions: source byte hashes and selected attributes match in copy mode; no mutation begins before all member backups verify; a crash injected after each journal phase permits safe recovery; an output edited after commit returns `.conflict` on original-location restore and permits separate-folder restore; a destination race never overwrites the new external file; cancellation does not leave half a protected commit labeled success.
- [ ] **2. Verify red.** `swift test --filter 'CopyModeTests|InPlaceTests|CrashRecoveryTests|CancellationTests'`. Run only in uniquely created fixture directories; failures retain journals and identify injected versus real I/O errors.
- [ ] **3. Implement backup, stage and commit contracts.** Stream hashes/copies; preserve required forks/ACL/xattrs; enforce source/volume identities and no-follow/no-replace semantics. Journal every phase before its corresponding mutation and sync it. Stage on the target volume and never pass source paths to the writing driver. Implement recoverable multi-member/rename steps without claiming whole-group atomicity. Keep originals indefinitely until explicit user removal. Serialize group commits and defer directory-date actions until children finish.
- [ ] **4. Verify green and real filesystem behavior.** Repeat focused tests on APFS, a constrained/full test volume and supported removable-volume fixtures. Verify copy failure leaves original unchanged; source permission/lock handling follows the preview; incomplete journals appear after restart; recovery conflicts retain both the original backup and external newer data. Confirm user-only recovery permissions.
- [ ] **5. Commit.** `feat: make batch edits recoverable through staged transactions`.

### T08: Write and verify supported embedded metadata

**Files:** Create `Metadata/{ExifToolWriter,TagRegistry,MetadataMutationDriver,MediaIntegrityValidator,JPEGIntegrity,TIFFIntegrity,HEIFIntegrity,PNGIntegrity,WebPIntegrity,RAWIntegrity,VideoIntegrity,MetadataStripProfiles}.swift`, `Resources/writable-tags.json`, `Tests/RestoreGPSTimeCoreTests/{MetadataWriteTests,MetadataStripTests,MediaIntegrityTests}.swift`.

**Interfaces:**
- Consumes runtime, capability profiles, `TagMutation`, `MutationPlan` and the T06 `MutationDriver` protocol.
- Produces `ExifToolWriter.write(_ mutations: [TagMutation], to stage: URL, profile: ContainerProfile) async throws -> MetadataDocument`.
- Produces `MediaIntegrityValidator.signature(at url: URL, profile: ContainerProfile) async throws -> MediaIntegritySignature` and `verify(before: MediaIntegritySignature, after: MediaIntegritySignature, allowedChanges: AllowedMetadataChanges) throws`.
- `MetadataMutationDriver` implements `MutationDriver`; it only accepts stage URLs owned by T07 and read-verifies expected tags before returning `StageVerification`.
- Defines `MediaIntegritySignature` in `MediaIntegrityValidator.swift`. `HEIFIntegrity` also owns separately verified AVIF BMFF item layouts; `RAWIntegrity` dispatches only model/container profiles whose image-bearing extents are understood.

- [ ] **1. Write failing tests for A04/A09/A13/A14/A17–A21 and R05.** `testDatesAndLocationRoundTrip`, `testUnicodeCommentsAndLanguageAlternatives`, `testListsRetainTypes`, `testUnknownReadOnlyTagBlocks`, `testRAWStripBlocks`, `testStripPreservesRenderingAndIdentifiers`, `testLocationTrackRemainderIsNotSuccess`, `testHEIFAuxiliaryAndVideoSamplesPreserved`.
  Assertions: changed tags equal the frozen plan, unrelated language alternatives remain; repeated location append is idempotent; compressed media/auxiliary signatures and Live Photo identifiers match; trying to strip an unverified RAW profile is `.unsupported`; residual recognized GPS yields `.incompleteRemoval`, not a privacy-success result.
- [ ] **2. Verify red.** `swift test --filter 'MetadataWriteTests|MetadataStripTests|MediaIntegrityTests'`.
- [ ] **3. Implement qualified stage-only writing and validators.** Pass literal argument values through `Process`, validate all tag identifiers and exclude raw switches/expressions. Use exact write profiles and read-back diffs. Build bounded parsers for JPEG compressed scans, PNG image chunks, WebP image/alpha chunks, HEIF/AVIF image extents and relationships, and TIFF/RAW image-bearing extents as required by enabled profiles. Use AVFoundation stored-format sample access for supported videos and preserve timing/track/color/orientation evidence. Reject malformed extents, unsupported layouts and validators that cannot prove preservation; keep those profiles read-only. Never use a full-file hash or successful decode alone as proof of unchanged compressed payloads.
- [ ] **4. Verify green through T07 transactions.** Repeat focused tests with actual bundled ExifTool. Exercise Save Copies and in-place restore, CR3/HEIF structural exceptions, malformed media and deliberate payload corruption. Turn on registry write capabilities only for profiles with passed tag/payload evidence. Add source citations to format-specific rules.
- [ ] **5. Commit.** `feat: write verified metadata without re-encoding media`.

### T09: Complete filesystem/Finder actions and scoped cleanup

**Files:** Create `Attributes/{FileDateWriter,FinderAttributeWriter,LegacyFinderInfo,ScopedTrash,FinderNotifier,FinderVisibilityController,AttributeMutationDriver}.swift`, `Tests/RestoreGPSTimeCoreTests/{FileDateWriterTests,FinderAttributeTests,FinderVisibilityTests,ScopedTrashTests,ReferenceActionCoverageTests}.swift`.

**Interfaces:**
- Consumes date plans, snapshots, T07 transactions and metadata driver composition.
- Produces `FileDateWriter.apply(_ change: FileDateChange, to url: URL) throws -> AttributeVerification`.
- Produces `FinderAttributeWriter.apply(_ change: FinderAttributeChange, to url: URL) throws -> AttributeVerification`.
- Produces `ScopedTrash.preview(scope: TrashScope) async throws -> TrashPlan`, `execute(_ plan: TrashPlan) async -> [TrashResult]`, and `FinderNotifier.notify(changed urls: [URL])`.
- Produces `FinderVisibilityController.preview(visible: Bool) throws -> FinderVisibilityChange`, `apply(_ change: FinderVisibilityChange, restartApproved: Bool) async throws -> FinderVisibilityResult`, and `restorePrevious(restartApproved: Bool) async throws -> FinderVisibilityResult`. These explicit Tools utilities are separate from `MutationDriver` and never called by preview, a batch or a droplet.
- `AttributeMutationDriver` composes embedded and filesystem stages in the specified order and implements the full production `MutationDriver` contract.
- Defines `FileDateChange`/`AttributeVerification` in `FileDateWriter.swift`, `FinderAttributeChange` in `FinderAttributeWriter.swift`, and `TrashScope`/`TrashPlan`/`TrashResult` in `ScopedTrash.swift`.
- Defines `FinderVisibilityChange`/`FinderVisibilityResult` in `FinderVisibilityController.swift`, preserving absent-key versus false and expected-current preference state.

- [ ] **1. Write failing tests for A01–A03/A06–A08/A10–A12/A15–A16/A22–A31.** `testDatesWrittenLastAndReadBack`, `testReset1904OrExplicitUnsupported`, `testFolderDatesAfterChildren`, `testFourByteCodesPreserveOtherFinderInfo`, `testWhereFromsOnly`, `testExplicitUnlockOnly`, `testHiddenCleanupUsesTrash`, `testActionMatrixHas31OwnedChecks`.
  Assertions: unselected attributes remain; creator/type edits affect exactly their selected bytes; WhereFroms removal preserves quarantine and every unrelated xattr; an explicit unlock does not change mode/ACL; cleanup previews only scoped hidden regular files and calls the Trash API, leaving untrashable targets in place.
  For X01/X02 also write `testCancelledVisibilityDoesNothing`, `testShowHideTouchOnlyOneKey`, `testRestoreAbsentKey`, `testExternalPreferenceConflict` and `testFinderRestartRefusalIsReported`. Assert no preference or restart call without explicit approval, exact old-state restoration, and no changes to unrelated keys.
- [ ] **2. Verify red.** `swift test --filter 'FileDateWriterTests|FinderAttributeTests|FinderVisibilityTests|ScopedTrashTests|ReferenceActionCoverageTests'`.
- [ ] **3. Implement exact attribute and cleanup semantics.** Use public APIs/descriptor-safe primitives, preserve unrelated FinderInfo fields and check volume support. Route ordinary mutations through T07. Give Trash a separate terminal plan and system-recoverable path; never combine it with Save Copies or tag changes. Finder refresh never restarts Finder or alters preferences. The separate Tools controller reads/writes only the fixed `com.apple.finder` / `AppleShowAllFiles` preference through Foundation/CoreFoundation preferences APIs or a directly invoked system `defaults` process; no shell or arbitrary domain/key is accepted. Retain previous/expected state, require the app's explicit Apply and Restart choice, read back the preference and request Finder termination/relaunch through AppKit. Restore detects intervening external changes.
- [ ] **4. Verify green on actual disposable files/folders.** Re-run focused tests, then semantically exercise all 31 action rows and two Tools rows. Test global Finder visibility only in an isolated qualification login/session whose use is explicitly authorized; snapshot its prior value, verify Show/Hide/Restore and read back restored state. Do not change this user's live Finder preferences merely to test. Record known unsupported filesystem/profile cases with expected reasons rather than removing their checks. Do not empty Trash or purge recovery evidence during verification.
- [ ] **5. Commit.** `feat: complete Finder attributes and reference action coverage`.

### T10: Build the native batch interface and recovery browser

**Files:** Create `Sources/RestoreGPSTime/{AppModel,BatchTableView,SidebarView,InspectorView,DateOptionsView,PlaceOptionsView,MetadataOptionsView,FinderOptionsView,DestinationView,RecoveryView,ToolsCommands,ReportExporter}.swift`, original resources under `App/Resources/`, `Tests/RestoreGPSTimeAppTests/{AppModelTests,ReportExporterTests}.swift`, `docs/acceptance/ui-checks.md`; update `AppMain.swift` and bundle assembly.

**Interfaces:**
- Consumes T02–T09 core APIs; no view invokes a raw writer.
- Produces `@MainActor AppModel.importURLs(_ urls: [URL]) async`, `preview() async`, `applyPreview() async`, `cancel()`, and `restore(batchID: UUID, choice: RecoveryChoice) async`.
- Produces `ReportExporter.export(_ report: BatchReport, to url: URL, includeCoordinates: Bool) throws`; CSV exports neutralize spreadsheet formula prefixes in untrusted text fields while JSON preserves typed values.

- [ ] **1. Write failing model tests.** `testDefaultIsSaveCopies`, `testApplyDisabledWithoutCurrentPreview`, `testChangingTimezoneOrNamesInvalidatesPreview`, `testBlockedAndFailedRowsRemainVisible`, `testCancellationAndRecoveryStates`, `testReportCoordinatesDefaultOff`, `testCSVFormulaStringsAreData`.
  Assertions: initial mode is `.saveCopies`; no executor call occurs without a current eligible preview; all inspector/tag destination and approximate-place data come from the plan; `includeCoordinates == false` excludes GPS from the default report; imported filename `=...` exports as data rather than an executable spreadsheet formula.
- [ ] **2. Verify red.** `swift test --filter 'AppModelTests|ReportExporterTests'`.
- [ ] **3. Implement the spec's native layout and bindings.** Add file/folder panels, drag-and-drop, current/proposed table columns, explicit zone/QuickTime choices, per-item place corrections, output/backup-space decisions, progress and recovery UI. Add the explicit Show/Hide/Restore Finder visibility Tools commands and Apply and Restart sheet; these never run as import/batch side effects. Offer local diagnostic export without automatic sharing. Keep filesystem work off the main actor. Include original app icon and system-standard controls; avoid unneeded visual-generation service dependencies. Reports retain partial results and recovery references locally.
- [ ] **4. Verify green and inspect the actual interface.** Run focused tests, then perform a documented native UI pass at 1100×720 and a larger window in light/dark appearance. Use the installed computer-use tool for UI interactions and screenshots. Check keyboard/VoiceOver labels, drop/import, preview, copy, in-place, cancellation, missing-runtime errors and recovery conflicts. Capture screenshots using only synthetic/redistributable fixture data; do not call model tests GUI acceptance.
- [ ] **5. Commit.** `feat: add native batch preview and recovery interface`.

### T11: Add workflows, droplets and Finder Services

**Files:** Create `Workflows/{WorkflowDocument,WorkflowStore,DropletExporter}.swift` under core, `Sources/RestoreGPSTime/{WorkflowView,DocumentImporter,ServicesProvider}.swift`, `Sources/RestoreGPSTimeDroplet/DropletMain.swift`, `Tests/RestoreGPSTimeCoreTests/{WorkflowTests,DropletTests}.swift`, `Tests/RestoreGPSTimeAppTests/ImportTests.swift`; update `Package.swift`, `Info.plist` and bundle resources.

**Interfaces:**
- Produces `WorkflowStore.load(from url: URL) throws -> WorkflowDocument` and `save(_ document: WorkflowDocument, to url: URL) throws` for schema 1 `.rgtimeworkflow` files.
- Produces `DropletExporter.export(workflow: WorkflowDocument, to appURL: URL, template: URL) async throws -> DropletExportResult`.
- Produces `DocumentImporter.open(urls: [URL]) async -> ImportOutcome`; AppKit Services and droplets call this same import boundary and always open preview.
- Defines `DropletExportResult` in `DropletExporter.swift` and `ImportOutcome` in `DocumentImporter.swift`. `ImportOutcome` is an app integration record rather than a core UI dependency.

- [ ] **1. Write failing tests.** `testWorkflowRoundTrip`, `testUnknownSchemaAndExecutableFieldsRejected`, `testWorkflowOmitsSourceOutputAndRecoveryPaths`, `testDropletRelocationAndSafeHandoff`, `testDropletNeverAppliesSilently`, `testAppAndServicesOpenSameImports`.
  Assertions: schema `1` round-trips options; future schema/unknown operations fail; exported JSON contains no input paths or prior metadata; a dropped batch leads to preview with Apply untouched; each exported bundle has a new ID and is not represented as inheriting the main app's signature.
- [ ] **2. Verify red.** `swift test --filter 'WorkflowTests|DropletTests|ImportTests'`.
- [ ] **3. Implement data-only workflow validation and native handoff.** Register document types, the AppKit Services provider and file Open With. The droplet validates its embedded workflow, asks the installed main app to import with that workflow and lets it preview. Do not embed destination/recovery paths or a silent apply route. Exported signatures are assessed honestly; ad-hoc droplets are labeled local exports.
- [ ] **4. Verify green and real OS integration.** Repeat focused tests and verify Services registration after installing the candidate in a disposable test location, Finder Open With, drag/drop, relaunch, missing-main-app behavior and moved droplets. Run each architecture natively before release; distinguish app-level model routing from actual Finder integration evidence.
- [ ] **5. Commit.** `feat: add reusable workflows droplets and Finder Services`.

### T12: Qualify real formats, failure handling and native hosts

**Files:** Create `Sources/RestoreGPSTimeQA/{QAMain,QualificationRunner}.swift`, `Scripts/{qualify,collect-evidence}.sh`, `docs/acceptance/{format-matrix,host-matrix,qualification-results}.json`, `Tests/RestoreGPSTimeCoreTests/{LargeBatchTests,FixtureRegressionTests}.swift`, local CI definition `.github/workflows/qualify.yml`; update fixture manifest and write profiles only with justified evidence.

**Interfaces:**
- Produces `QualificationRunner.run(appURL: URL, fixtureManifest: URL, output: URL) async throws -> QualificationResult` in the developer-only QA target.
- `Scripts/qualify.sh --app PATH --fixture-manifest PATH --evidence-dir PATH --host-label LABEL` runs actual tests and emits a versioned evidence manifest with source commit, app/dependency hashes, host architecture/OS, fixture provenance and separate automated/manual results.
- Produces explicit `pass`, `fail` or `missing` gates; a missing native host/fixture is never encoded as pass.
- Defines `QualificationResult` in `QualificationRunner.swift`; QA code is a separate source executable, not a hidden user-app mutation mode.

- [ ] **1. Write failing regression/qualification tests.** `testTenThousandEntriesCancelResponsively`, `testLargeFilesAreStreamed`, `testRealFormatMatrixRequiresEvidence`, `testMissingNativeHostDoesNotPass`, `testAuxiliaryPayloadMismatchRejectsWrite`, and per-action fixture checks. Assert maximum helpers ≤2, stable 10,000-item names, cancellation, bounded file buffering and an open release gate for missing macOS 13/Intel evidence.
- [ ] **2. Verify red.** `swift test --filter 'LargeBatchTests|FixtureRegressionTests'`; run the QA command against a deliberately incomplete evidence directory and expect a nonzero incomplete result.
- [ ] **3. Assemble lawful qualification inputs and exact host jobs.** Cover all spec fixture families and >4 GiB/large media, permissions, volume behavior, conflicts and staged failures. Use generated inputs for deterministic cases and genuine representative HEIF/HDR/depth/Live Photo/RAW/video files where genuine format behavior is required. Record private local fixtures separately and never commit them. Verify current native runner/host capabilities. Keep the workflow local; obtain a specific private/remote qualification arrangement before transmitting unpublished material when local hosts are unavailable.
- [ ] **4. Run the complete acceptance suite natively.** Execute `swift test`, qualification commands, manual UI/Services/droplet checks, offline relocated-bundle checks and Instruments main-thread tracing. Required host matrix: native ARM64/macOS 13, native Intel/macOS 13, and current supported OS on native ARM64/Intel. Capture source SHA, process architecture, hardware ARM capability, translation state (`sysctl.proc_translated` where present), OS/build, toolchain and fixture/dependency identities; reject Rosetta as native Intel evidence. A 10,000-item run must have no batch-work main-thread stall over 250 ms. Retain RED evidence; fix implementation/fixtures as justified, then rerun only affected gates before the final coherent regression pass.
- [ ] **5. Commit verified evidence summaries and support matrix.** `test: qualify metadata recovery across formats and native architectures`. Private media, raw private paths, credentials and local-only reports remain outside Git. Any absent gate stays explicitly open and blocks stable publication.

### T13: Package, sign and publish the two separate releases

**Files:** Create `Scripts/{package,sign-and-notarize,check-release,publish-release}.sh`, `Scripts/release_gate.py`, `App/RestoreGPSTime.entitlements`, `docs/{INSTALL,RECOVERY,RELEASE}.md`, `LICENSE`, `CHANGELOG.md`, `Tests/ReleaseGateTests/test_release_gate.py`; update `README.md` to describe tested product behavior and the pinned dependency notices. Generate deliverables under `outputs/releases/` only during this task.

**Interfaces:**
- `Scripts/package.sh --arch arm64|x86_64 --version 1.0.0 --source-commit SHA --output DIRECTORY` assembles the matching ZIP/DMG and evidence set.
- `Scripts/check-release.sh --directory DIRECTORY --arch arm64|x86_64 --source-commit SHA` inspects archives, Mach-O/dependencies, deployment targets, checksums, signatures and acceptance receipts. It returns nonzero on any missing/failing stable gate.
- `Scripts/publish-release.sh --repository Delitants/restoregpstime-macos --tag TAG --manifest PATH` uploads only the exact manifest-listed, hash-verified artifacts for a prevalidated tag/source commit, retaining API receipts and refusing unrelated asset replacement.

- [ ] **1. Write failing release-gate tests.** Use synthetic manifests only. `testMissingGateBlocks`, `testRosettaIsNotIntelNative`, `testWrongArchitectureOrMinOSBlocks`, `testUnsignedIsNotStable`, `testPrivateFixtureOrSecretBlocks`, `testTagsMustShareReviewedSource`, `testUploadRetryDoesNotOverwriteDifferentHash`.
  Assertions: any absent required native/OS/UI/integrity/notary gate returns nonzero; allowed asset names match the spec exactly; a changed artifact hash stops upload; an existing different asset is a conflict, never a delete-and-retry path.
- [ ] **2. Verify red.** `python3 -m unittest discover -s Tests/ReleaseGateTests -v`. This uses no network and cannot publish a release.
- [ ] **3. Implement packaging and signed distribution.** Sign nested native runtime/modules in the required order, then app/droplet templates and archives; use hardened runtime and the minimum necessary entitlements. Submit with existing authorized Developer ID/notary credentials when supplied, retain Apple's result and staple tickets. Do not create/rotate credentials or disable Gatekeeper. If signing resources are absent, finish local packaging/QA but leave stable release closed. Build DMGs with the app and Applications link; include licenses, instructions, checksums and evidence without private media.
- [ ] **4. Verify candidate delivery before any public mutation.** Run release-gate tests and `Scripts/check-release.sh` for both architectures, extract/mount-install candidates in disposable locations, test moved/quarantined apps with Gatekeeper and recheck offline native operation. Assert both sets came from the same reviewed source SHA. Review the exact Git tracked files and candidate manifests for personal/private/reference-app material, source licenses and secrets; replace the spec's local audit link with an audited public description. Preserve signing/notary and failed qualification receipts.
- [ ] **5. Publish after readiness and record read-back.** The original user request authorizes publication once stable gates pass. Verify authenticated account and repository identity; prefer the GitHub connector for supported operations, using authenticated `gh` only for missing repository/release/binary-asset capabilities. Create the public repo only now, push audited source, create `v1.0.0-arm64` and `v1.0.0-x86_64` at the same reviewed commit, and upload the matching manifest-listed assets. Download/check release metadata and asset hashes; report both actual URLs. If one publication fails, retain receipts, report partial status and resume only the missing exact operation. Do not claim both releases ready until both verify. Commit release tooling/docs before final candidate qualification; do not alter the candidate source SHA after checks.

## Completion checklist and execution handoff

- [ ] User reviews the written specification and this plan, including repository/license and honest format limits.
- [ ] User selects execution in this chat or delegated implementation; recommend execution in this chat because the metadata, naming, transaction and integrity contracts are tightly coupled.
- [ ] T01–T13 are completed with evidence, or resource-dependent gates remain explicitly open.
- [ ] All R01–R16, A01–A31 and X01–X02 link to an implemented, checked result; no skipped unsupported case is called full parity.
- [ ] No user source, original reference binary/artwork, credential or private fixture is in public Git history/assets.
- [ ] Both release URLs and verified artifact checksums exist before claiming publication complete.

The request for plan/spec work is complete when these documents and the action matrix are self-reviewed and delivered. It is not completion of the user's overall app-and-release request. After their review, execute the selected workflow; request signing/test-host resources only at the relevant later gate.
