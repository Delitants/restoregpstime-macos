# RestoreGPSTime Specification

Date: 2026-10-21, Pacific/Honolulu. Status: written for review; implementation has not started.

## 1. Agreed purpose and scope

Build an original macOS utility that restores useful file dates and place names from existing photo/video metadata, supports batches, and offers both copy export and recoverable in-place changes. Reproduce the functional scope of the locally inspected A Better Finder Attributes 7.31, using original implementation and branding.

The user approved the initial design, macOS 13+, and offline place lookup, then explicitly renamed the app **RestoreGPSTime**. The rename replaces MediaRestorer throughout the product. It does not request a new GPS-clock recovery feature. This specification and its implementation plan are the currently authorized deliverables. Public GitHub publication is authorized when the two release versions are ready; no public draft, user media, or reference-app content is to be uploaded during planning.

Success means a person can inspect a batch, understand which tags and files will change, apply those changes without media re-encoding, and recover an in-place edit from retained originals. A compiled binary alone is insufficient release evidence.

### Global constraints

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

## 2. Requirements and acceptance ownership

| ID | Requirement | Plan task(s) |
| --- | --- | --- |
| R01 | Native app and self-contained metadata runtime for both architectures | T01, T12, T13 |
| R02 | Scan files/folders; discover metadata and operation capabilities | T02 |
| R03 | Restore birth time, modification time, or both from embedded capture dates | T03, T06, T09 |
| R04 | Recover approximate city/country offline from existing coordinates | T04 |
| R05 | Write location comments and supported structured place fields | T04, T08 |
| R06 | Rename with place names and deterministic collision-safe numbering | T05, T07 |
| R07 | Batch preview, immutable plans, progress, cancellation and per-file results | T06, T07, T10 |
| R08 | Save copies without changing source content/attributes; recoverable in-place mode | T07 |
| R09 | Reference actions A01–A31, advanced date sources and Finder visibility Tools commands X01–X02 | T03, T08, T09, T11 |
| R10 | Preserve Live Photo links, sidecars and media payloads | T05, T07, T08, T12 |
| R11 | Explicit format limitations and readable-but-not-writable media | T02, T08, T10, T12 |
| R12 | Native import/export UI, inspector, keyboard access and appearance support | T10 |
| R13 | Saved workflows, droplet equivalents and Finder integration | T11 |
| R14 | Recovery journal, safe restore and private local reports | T07, T10 |
| R15 | Offline operation, isolated helper execution and dependency provenance | T01, T02, T04, T12 |
| R16 | Separate verified releases, signing assessment and public publication | T12, T13 |

The complete 31-action mapping is in [the reference action matrix](../../acceptance/reference-actions.csv); the separately inspected Finder visibility commands are in [the Tools matrix](../../acceptance/reference-tools.csv). No action may disappear from the release checklist because its original wording is old or its filesystem behavior is constrained. A constrained action is exposed with accurate semantics and a reason when unsupported for an item.

## 3. User flow

1. Add files or folders using drag-and-drop, Open, Finder Open With, or the Finder Services menu. Import is read-only.
2. Choose Restore Dates, Restore Places, Metadata, Finder Attributes, or a Saved Workflow. Files/folders and recursive inclusion are explicit switches; recursion starts off.
3. Select changes and save mode. Pick an output folder for copies. Select a timezone if the chosen source lacks one. Select a recovery folder for in-place operations.
4. Preview. Each row shows source, detected format, selected date tag, timezone interpretation, current/proposed dates, approximate place and match distance, proposed path, and support status.
5. Resolve blocked rows or exclude them. Changing options, a correction, or the input list invalidates the previous preview. No unsupported operation is silently replaced with a different operation.
6. Apply the previewed eligible rows. Progress and cancellation remain usable. Completed, skipped, failed, cancelled and recovery-needed states remain distinct.
7. Review results, reveal outputs in Finder, export a report, or restore an in-place batch from its recovery journal.

### Window layout and copy

The sidebar has **Restore Dates**, **Restore Places**, **Metadata**, **Finder Attributes**, **Saved Workflows**, and **Recovery**. The center contains a sortable batch table. A right inspector displays metadata provenance, explicit tag names, warnings and selected-file details. An options panel and bottom action bar contain **Preview Changes**, **Save Copies**, **Modify in Place**, **Cancel**, and **Export Report** as applicable.

Minimum usable window size is 1100 × 720 points. Smaller content areas use horizontal table scrolling and a collapsible inspector. Support system light/dark appearance, VoiceOver labels, keyboard operation, selectable error text, and readable progress. Default body text follows system settings. Network map tiles are not part of the interface.

## 4. Architecture and data contracts

Use a Swift package containing `RestoreGPSTimeCore`, a native executable target `RestoreGPSTime`, and a small droplet executable target `RestoreGPSTimeDroplet`. The core owns parsing, planning and execution, independent of SwiftUI. The package uses tools version 5.9 and Swift 5 language mode so macOS 13 is a real deployment target rather than a label on a modern-only app.

`Scripts/build-app.sh` assembles the package executables and resources into normal `.app` bundles. It records the selected Xcode/SDK version and deployment target. Use only public system APIs and pinned bundled dependencies. A helper failure produces an item error and preserves stderr locally.

The native app is architecture-specific. ExifTool's Perl code/data is interpreted; the bundled interpreter and any native modules match the release architecture. This is a native Swift app with an interpreted metadata backend, not a claim that ExifTool itself is compiled Swift.

### Core records

All persisted records below are versioned `Codable` values; plan/journal/report schema version starts at `1`.

- `SourceID`: volume identity, device/inode, resolved regular-file identity, size, modification time, change time and link count. The discovery record also carries original URL and display path.
- `FileSnapshot`: `SourceID`, filesystem dates, POSIX mode and owner/group IDs, ACL/xattr inventory, lock/hidden-extension/Finder data, file kind, availability and read errors.
- `MetadataDocument`: group-qualified tags and values, detected container, capture candidates, coordinates, linked-asset identifiers and backend diagnostics. Duplicate tag names retain group provenance.
- `CaptureCandidate`: tag, original string, parsed wall clock, fractional precision, explicit offset if present and candidate kind. An unzoned wall clock is not a resolved instant.
- `DatePolicy`: source choice, fallback order, missing-zone selection, QuickTime interpretation, target fields, fixed-duration shift and optional sequence start/step.
- `PlaceMatch`: city, region, country, country code, database record identity, distance in km, database version and origin (`database` or `manual`). It never means verified administrative containment.
- `AssetGroup`: ordered media/sidecar members with pairing evidence. Filename similarity alone is not sufficient evidence of a Live Photo.
- `OperationRequest`: typed date, metadata, place, rename and filesystem requests plus save mode and explicit inclusions/exclusions.
- `PlannedItem`: source fingerprint, resolved mutations, expected tag differences, expected attributes, destination reservations, capability decisions and blocking reasons.
- `BatchPlan`: UUID, schema, options digest, ordered groups, fixed current-time sample, dependency/database identities, and per-item eligibility. Immutable after preview.
- `BatchEvent`: item/group progress, committed results, skipped/failed reasons and recovery IDs, delivered as an `AsyncStream`.
- `RecoveryRecord`: original/final paths, phase, before/after hashes and attributes, member decisions, backup locations and retained errors.

Primary interfaces are defined in plan task blocks. Changes to these contracts during implementation require updating the spec, plan and dependent tests together.

### Logical pipeline

`Discover → Read → Resolve dates/places → Group/name → Plan → Revalidate → Back up → Stage → Mutate stage → Verify → Commit → Report`.

Batch groups commit serially for version 1. Read-only metadata work has at most two active helpers. This limits simultaneous large-video copies and makes cancellation/recovery predictable. Inventory is frozen before creating output directories, preventing a destination nested inside an input tree from being re-imported.

## 5. Date behavior

### Source selection

For photos, automatic capture-source preference is: valid EXIF `DateTimeOriginal` with its subsecond/offset companions; XMP `DateTimeOriginal`; XMP `CreateDate`; EXIF `CreateDate`. For videos, prefer explicitly zoned QuickTime `Keys:CreationDate`, then valid XMP capture/create dates, then user-interpreted QuickTime container CreateDate and MediaCreateDate. Exact available group-qualified tags are displayed; the backend registry resolves family/group aliases for the pinned engine.

The user can select a specific source, overriding automatic preference. Missing or invalid candidates are reported; the planner does not substitute the current date, filesystem date or another source unless the previewed fallback policy explicitly permits it.

Additional reference sources: file birth/modification time, specific date, current time, EXIF digitized date, QuickTime create/modify/media/content date families, composite capture date, Spotlight content-created/content-modified/added/downloaded fields, filename parsing, or a matching relative-path/name file under a selected reference root. A missing Spotlight value is unavailable; it does not start Spotlight indexing. Ambiguous reference matches are blocked and listed for selection.

Filename parsing uses an explicit numeric pattern with year/month/day/hour/minute/second and optional offset tokens. No natural-language date parser is used. Preview highlights the matched substring; invalid calendar dates are errors. Relative reference hierarchy is tried first; basename fallback is opt-in and must have exactly one match.

### Timezone and precision rules

An explicit offset always takes precedence. A missing offset requires the user to choose an IANA zone or fixed offset, visible in the preview. There is no silent use of the computer's zone or the nearest city's zone. Ambiguous fall-back DST times require choosing the earlier/later occurrence; nonexistent spring-forward times block that item.

QuickTime integer dates are not silently treated as UTC. The workflow presents **Interpret QuickTime integer dates as UTC** or **Interpret as local camera time in the selected zone**; a choice is required when such a candidate is selected. Helper locale/TZ are controlled so extraction does not depend on the host. Write string dates with explicit offsets and integer dates using the chosen policy. Preserve fractions to the precision supported by the destination; report reduced precision.

Dates may be set, copied between fields, shifted by a signed duration in seconds (days mean 86400 seconds), or sequenced from an explicit start/step using the final deterministic group order. Freeze “current time” once per plan. Store resolved instants and provenance in the plan, not a recipe that can resolve differently at execution time.

### Filesystem dates

Set embedded metadata first and final filesystem dates last. If a change targets only one filesystem date, retain the other when the filesystem permits it. If the combination is impossible, show the required normalization in preview and require its selection; otherwise block it. Read the actual attributes back and compare at the destination's observed precision.

Reference “remove creation date” and “remove both dates” are labeled **Reset creation date** and **Reset creation and modification dates**. Their explicit reset value is `1904-01-01T00:00:00Z`. Filesystems do not generally provide an absent birth/modification date. The action is unsupported when the volume cannot represent the reset or the unselected companion date cannot be retained under the selected policy. Removing embedded shooting dates deletes only the listed supported embedded date tags, with read-back verification.

## 6. Offline place recovery and naming

Use the database bundled with the pinned ExifTool distribution; its standard population cutoff is 2000. Display the database version/provenance in About and each report. No service key, photo upload, geocoding request or location permission is needed. Do not install an alternate database implicitly or fall back to an online service.

Read explicit EXIF/XMP/QuickTime GPS coordinates, honoring hemisphere references. Validate finite latitude −90…90 and longitude −180…180. A valid `(0, 0)` is not automatically discarded, but normally has no eligible nearby city. Missing/contradictory GPS blocks location-derived operations for that file. Preserve original coordinates unless the user expressly selected removal/editing.

Return up to three nearby records. Default maximum distance is **25 km**, editable per workflow. A match is labeled **Nearest place**, with distance, and never described as a restored historical address or verified country boundary. Show a caution when candidate countries differ. Rural/ocean/border locations and missing settlements may have no acceptable match. The user can choose another candidate or enter a city/country correction, applied per file or selected group; record manual provenance.

### Metadata outputs

Provide independent switches for a readable comment, supported structured city/region/country fields, and rename. A readable comment is `City, Country`, omitting empty parts. Require at least one name component.

- Photo comment profiles prefer verified writable EXIF `UserComment`; otherwise use an explicitly selected XMP description destination.
- Video profiles use verified QuickTime description/comment or XMP description destinations. Display the actual group/tag.
- Structured fields use verified XMP/IPTC/QuickTime location fields for that container. Do not imply that every format stores an EXIF city tag.
- Existing comments default to **Append once**, separated by `\n`; avoid an identical complete appended line on repeats. **Replace** is an explicit alternative. Preserve unrelated language alternatives and list entries unless targeted.

### Deterministic filenames

Default template: `{country} - {city} - {sequence:04}.{extension}`. Sequence starts at 1 for each normalized `(country, city)` group. All members of a confirmed linked group share one sequence and basename; extensions retain their source spelling. Two unrelated files of the same extension receive different numbers even if they have the same date/place.

Sort by resolved capture instant, then normalized root-relative source path, then original path bytes. Items without a resolved capture instant sort after dated items by path. This order is frozen before numbering; adding inputs requires a new preview.

Use Unicode NFC for display names and filesystem-aware case/normalization collision keys. Compare all planned and existing destinations, including sidecars. Replace `/`, `:`, NUL and control characters in substituted name components with `-`; trim trailing dots/spaces. Reject empty, `.` or `..` results and templates that add path separators. Reserve room for the numeric suffix and extension within the volume's filename limit; show any truncation. Preserve existing filenames if rename is off.

Advance the sequence until the whole group's destinations are free. Never silently replace an unrelated file. No two groups may reserve the same destination. No-overwrite commit checks are required even after preview. Case-only renames and name cycles use journaled temporary paths, never a blind overwrite.

Live Photo pairing uses matching asset/content identifiers. Companion XMP/AAE files may be grouped by a unique same stem in the same directory; conflicting stems remain ungrouped and require selection. Show membership and permit unlinking. Group commits are recoverable across all members; do not claim multiple filesystem entries change atomically.

## 7. Format support and integrity

| Family | Version 1 objective | Restrictions |
| --- | --- | --- |
| HEIC/HEIF, JPEG, TIFF | Date/GPS reading; qualified embedded edits; filesystem dates and rename | HEIF variants, HDR/depth/auxiliary images and maker data need fixtures |
| PNG, WebP, AVIF | Available metadata reading; validated XMP/EXIF writes | Advertise only individually tested tag/container combinations |
| DNG, CR2/CR3, NEF, ARW, RAF, ORF, RW2 | Read and qualified writable tags | No blanket RAW metadata stripping; variant-specific capability registry |
| MOV, MP4, M4V, 3GP | Capture/GPS read, verified QuickTime/XMP writes, rename/dates | Preserve tracks, orientation, identifiers, color/HDR metadata and media samples |
| AVI, MKV, WebM, other detected video | Read where engine supports it; rename/filesystem dates | Embedded writes disabled unless added through verified capability profiles |
| Other ordinary files/folders | Filesystem/Finder operations where applicable | Embedded operations require a supported media profile |

Capabilities are per operation and file profile, not just extension. Unknown or untested write profiles start disabled. Read-only formats may use an explicitly selected XMP sidecar for descriptive outputs; a sidecar is never an implicit replacement for an embedded write. Capture-date provenance, read-only support and sidecar status remain visible.

No media re-encoding is allowed. Integrity tests compare compressed image extents or track sample payloads plus auxiliary items, track relationships and required rendering metadata. Decode/playback checks supplement payload checks. A generic file SHA changes on metadata edits and is not an image-quality test. An ExifTool success exit alone is insufficient; re-read changed tags and validate expected differences.

Metadata stripping removes supported descriptive metadata while preserving required rendering/container data, color profiles, orientation and linked-asset identifiers. Label the exclusions. Disable dangerous blanket removal for RAW and unverified HEIF/video variants. GPS removal inventories EXIF/XMP/IPTC/QuickTime and recognized embedded GPS streams. If readable location data remains, report incomplete removal; do not claim complete privacy sanitization or hide an unsupported GPS track.

## 8. File safety, transactions and recovery

### Input rules

Do not follow symlinks. In-place operations on multiply linked regular files are blocked; Save Copies may produce an independent file. Deduplicate selected physical file identities. Skip packages by default, and never recurse into the app, output/recovery roots or symlink loops. Explicit folder attribute actions target selected folders; recurse into subfolders only when selected. Directory dates are applied after affected descendants.

Do not change POSIX permissions to make files writable. Locked inputs remain blocked for operations requiring writes until **Unlock** is explicitly part of the previewed request. This permission covers only the selected file flag; do not adjust ACLs or unrelated permissions. Cloud placeholders are shown as unavailable; no implicit download is initiated. Read-only/network/removable filesystems require the capabilities used by the selected transaction; fail clearly when they cannot provide them.

### Save Copies

Default to preserving relative folder hierarchy under the selected output root. Keep distinct import roots in distinct named subfolders when their relative paths collide. Copy original data, relevant resource forks, ACLs/xattrs and attributes before staged mutations. Fail or obtain an explicit previewed omission when an output filesystem cannot preserve a relevant selected attribute. Preserve source content, filesystem modification/birth times, Finder attributes and location; incidental OS access-time behavior is reported separately if relevant.

Create outputs with no-overwrite semantics. Staging is on the destination volume for same-volume commit. A failed item leaves its source unchanged and its diagnostic staging evidence retained in the batch recovery directory. No final-path partial file is called successful.

### Modify in Place

Before the first change to a group, finish and hash-verify retained originals for every regular-file member and persist their attributes and paths. For a selected directory attribute change, journal its metadata snapshot rather than copying the directory hierarchy. Default recovery root: `~/Library/Application Support/RestoreGPSTime/Recovery/`; allow a user-selected alternative. Recovery manifests/backups use user-only permissions. Refuse to start if backup/staging space or required attribute preservation is unavailable.

Revalidate identity, content hash and attributes against preview immediately before mutation. Use a staged independent regular file on the target volume; the metadata helper never writes a user source path. Coordinate file access and use descriptor-relative identity checks and no-replace/exchange primitives as applicable. Concurrent external changes cause a conflict; do not claim protection from a hostile concurrent writer or silently retry against changed inputs.

Persist journal phases `prepared → backedUp → staged → verified → committing → committed`, or `failed`, `cancelled`, `recoveryNeeded`, `restoring`, `restored`. Flush each phase before its corresponding externally visible mutation. Write manifests atomically and sync them; a failure to persist recovery state stops the commit. A normal path replacement is atomic where the volume supports it. Renames and multi-member groups require journaled steps and recovery, rather than a fictitious whole-batch atomic guarantee.

After mutation, verify tags/payloads as required, apply final filesystem dates/flags, and read them back. A post-commit verification failure is **recovery needed**, never success. Attempt group restoration only when expected post-operation identities/hashes still match; retain conflicts for user-directed resolution. Preserve the original state as recoverable evidence even if automatic restoration succeeds.

On launch, display incomplete journals. Do not replay a write automatically. Restore checks that current outputs match the journal's expected after-state; if changed externally, offer restore to a separate folder instead of overwriting newer edits. Recovery originals are retained until the user explicitly removes that batch. No automatic retention purge is included.

Cancellation stops starting new groups. It can terminate a helper writing only a disposable stage; it never interrupts the small protected commit sequence. Finish/restore the active group as needed, then report cancelled and untouched items separately.

## 9. Metadata and Finder action semantics

Tag editing uses a curated group-qualified writable tag registry plus an advanced selector restricted to backend-declared writable descriptive tags. Lists, Unicode and language alternatives keep their types. Reject executable config, expressions, shell snippets, output redirection and raw ExifTool switches. An unsupported or read-only tag is blocked in preview.

All date, tag and Finder actions are addressed individually in the action matrix. Finder flags use public filesystem/AppKit interfaces. Preserve FinderInfo bytes unrelated to creator/type, label, extension visibility or the explicit selected field. Creator/type codes are exactly four bytes and are shown with an ASCII/hex representation; removal zeros only the selected fields. “Remove WhereFroms” removes only `com.apple.metadata:kMDItemWhereFroms`, never quarantine or unrelated xattrs.

Invisible-file cleanup is a separate terminal workflow: enumerate hidden regular files in the explicitly selected scope, preview their exact paths, and send selected entries to Trash through the system API. Do not delete hidden directories, dotfiles indiscriminately, `.DS_Store` outside scope, packages or symlink targets. Save Copies is inapplicable to this action. If a target cannot be Trashed, leave it in place and report the failure. Other mutations and Trash cannot share one workflow run.

Finder refresh notifies the system about selected changed paths. It does not relaunch Finder or change global Finder preferences. Opening/revealing a selected file or folder in Finder is supported.

The reference additionally exposes **Show invisible files in the Finder** and **Hide invisible files in the Finder**. Provide these as separate Tools commands, never part of batch processing or a droplet. Read and retain the previous `com.apple.finder` / `AppleShowAllFiles` value, including whether the key was absent. Before changing it, present **Apply and Restart Finder**, explaining that Finder windows may be interrupted; cancellation changes nothing. Change only that preference, read it back, then request Finder termination/relaunch through AppKit. A refusal/failure is reported accurately. Provide **Restore Previous Finder Visibility** and restore an absent key by removing only that key. If another application/user has changed the setting since this app's command, show the conflict instead of overwriting it automatically. This explicit utility is the only planned global Finder preference change. Verify the preference behavior on each supported OS; no private framework or security bypass is used.

## 10. Workflows and integration

Save versioned JSON workflow files with extension `.rgtimeworkflow`, storing operation settings, timezone and naming rules. Do not embed credentials, absolute source roots, output/recovery roots or previously read user metadata. Require destination selection when applying an imported workflow. Reject unsupported schema versions, unknown operation types and path traversal. Workflow files are data, not scripts.

A droplet is an exported small native `.app` carrying a validated workflow. It imports dropped files into the installed RestoreGPSTime app and opens preview; it never applies changes silently. Build a reusable droplet executable with the app, then copy it and the workflow when exporting. The new bundle cannot inherit the main app's signature: sign each exported bundle if a suitable identity is available, otherwise label it ad-hoc/local and explain its distribution limit. Do not bypass Gatekeeper or require disabling protection. Verify relocated workflows and droplets on both architectures.

Finder integration means `.app` document opening, drag-and-drop and **Services → Open in RestoreGPSTime**. Register an AppKit Services provider and read only the files supplied by the service. No Finder Sync extension, global shell hook or background daemon is required. Standard app registration is checked after installing the release candidate in a disposable test location.

## 11. Runtime, privacy and diagnostics

Version 1 uses pinned ExifTool **13.59**, its included city database and a bundled Perl **5.44.0** source build, subject to a dependency feasibility/security check in T01. Record official source URLs, SHA-256 hashes, license files, architecture, deployment targets and compiler versions in `Dependencies/dependencies.lock.json`. Never use a mutable branch or unverified download in a release. If the pinned runtime cannot support macOS 13, stop that dependency integration and propose a documented version adjustment; do not lower the OS requirement or silently use system Perl.

Invoke the bundled Perl executable directly with `Process`, an argument array, a controlled environment and absolute executable/input paths. Disable ExifTool user config with `-config` and an empty config value. Clear Perl injection/search environment variables; set only known bundled module paths. Do not use a shell or newline-delimited argument files for untrusted paths/values. Capture stdout/stderr concurrently, enforce per-request cancellation/timeouts and bounded output, and report read/parse/timeout errors distinctly.

The application performs no outbound network requests. No update polling, analytics, online maps or online geocoder are included. User file paths/GPS remain local; reports omit coordinates by default, with explicit local export inclusion available. CSV report text is exported as spreadsheet data, neutralizing formula prefixes in untrusted fields; JSON retains typed values. Release fixtures are generated or redistributable and contain synthetic coordinates, never personal media. Crash/debug records are not uploaded automatically.

## 12. Verification and release acceptance

Every action row needs a disposable fixture, a semantic before/after check and a support decision. Unit tests cover parsers/planning; integration tests run the actual bundled engine and real filesystem; native UI checks exercise user flows. Injected failures validate recovery but are labeled injected evidence. Rosetta and cross-compilation never count as native Intel testing.

Required fixture classes: ordinary JPEG; Apple HEIC/HEIF; HDR/depth/auxiliary HEIF; paired Live Photo; TIFF; PNG; WebP; AVIF; representative supported RAW families; MOV/MP4/M4V/3GP; read-only AVI/MKV/WebM; Unicode/leading-dash/newline paths; missing/malformed metadata; offset/DST edge cases; sparse >4 GiB and large real video; APFS case-sensitive/insensitive; constrained/exFAT/removable-volume behavior. Only lawful redistributable inputs enter Git or public releases; private qualification media stays local.

Qualify cold launch and core restore/copy/recovery flows on actual native ARM64 and native Intel, and on macOS 13 for each architecture before advertising the minimum. Record both process architecture and hardware capability/translation state (`sysctl.proc_translated` and ARM capability where available); `uname -m` alone cannot establish native Intel execution. The local Xcode/SDK and Rosetta observations in the audit are preliminary only. CI uses explicit architecture labels verified at execution; it must not assume `macos-latest` is Intel. Where an oldest-OS host or required fixture is unavailable, that gate remains open and stable publication waits.

At 10,000 synthetic entries, planning must remain responsive and cancellable with no UI stall exceeding 250 ms attributable to main-thread batch work in an Instruments trace. Files are streamed, not loaded wholesale into RAM. Helper count stays at most two. Log host/hardware/fixture sizes with throughput measurements rather than promising a universal processing rate.

### Release artifacts

Both tags point to the same reviewed source commit. Each contains its architecture-only `.app` as ZIP and DMG:

- `RestoreGPSTime-1.0.0-AppleSilicon.zip` and `.dmg` under `v1.0.0-arm64`.
- `RestoreGPSTime-1.0.0-Intel.zip` and `.dmg` under `v1.0.0-x86_64`.

Each release also includes `SHA256SUMS.txt`, `release-evidence.json`, the operation/format matrix, install/recovery instructions, dependency/license notices and known limits. Inspect every Mach-O and native module for a single correct architecture, OS minimum and absence of Homebrew/build-directory dependencies. Test the assembled app after moving it to a path containing spaces and Unicode, with network disabled and system/Homebrew Perl unavailable to the app.

Default public distribution is Developer ID signed, hardened, notarized and stapled; assess extracted downloaded artifacts with Gatekeeper. No signing identities were present during discovery. Development/ad-hoc builds remain explicitly labeled local test builds; they are not called notarized or published as a stable substitute without a separate user decision. Credentials are supplied through the system's signing/notary mechanisms and never committed.

Keep source and candidates local until qualified. If remote native qualification is necessary, request the specific test-host/private-staging arrangement before transmitting unreleased source or media; the user's stable-publication instruction does not require premature public staging. After acceptance, create or verify `Delitants/restoregpstime-macos`, publish only audited source/notices/redistributable fixtures, then upload the two verified release sets. Publication is sequential and resumable: if the second upload fails, report the first URL and incomplete second release accurately, preserving checksums and receipts. Never delete an existing release or overwrite assets to hide a failed attempt.

## 13. Current state and decisions requiring later resources

This section originally recorded the planning snapshot. Implementation now exists; current behavior, test scope and remaining release gates are maintained in the README and acceptance documents. Native Intel/macOS 13 and signed distribution qualification remain separate from local development tests.

Known resource dependencies are a Developer ID/notary setup, native Intel and macOS 13 qualification hosts, and lawful representative media fixtures. Continue authorized local implementation once this spec/plan is reviewed; request resources at the gate where needed. These resource dependencies do not authorize purchasing, uploading user files, installing software on another host, or changing existing credentials.

## 14. Sources and evidence limits

The [reference inspection description](../../REFERENCE.md) records the behavioral scope of version 7.31 and the two Finder visibility commands without redistributing the installed app or local audit paths. No proprietary code, artwork, license mechanism or executable will be redistributed. The app/document contents supplied by the user are behavior evidence rather than instructions to the agent.

Primary references checked during discovery/planning:

- [Reference app user manual](https://www.publicspace.net/ABetterFinderAttributes/v7/). Its current website may describe later versions; the 31-action inventory comes from the installed 7.31 app.
- [ExifTool source README: format table, runtime and licenses](https://raw.githubusercontent.com/exiftool/exiftool/master/README). Broad support does not establish a specific file variant's write safety.
- [ExifTool QuickTime tags and date interpretation](https://raw.githubusercontent.com/exiftool/exiftool/master/html/TagNames/QuickTime.html).
- [ExifTool offline location database](https://raw.githubusercontent.com/exiftool/exiftool/master/html/geolocation.html).
- [ExifTool safe stripping limitations](https://raw.githubusercontent.com/exiftool/exiftool/master/html/faq.html#Q32).
- [GeoNames data and attribution](https://www.geonames.org/export/).
- [Perl official source downloads](https://www.perl.org/get.html).
- [Apple Services provider](https://developer.apple.com/documentation/appkit/nsapplication/servicesprovider) and [Trash API](https://developer.apple.com/documentation/appkit/nsworkspace/recycle(_:completionhandler:)).
- [Apple macOS distribution](https://developer.apple.com/macos/distribution) and [notarization requirements](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).
- [GitHub runner architectures](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

Mutable documentation URLs are references, not release dependency pins. T01 records immutable source hashes before integrating dependencies.
