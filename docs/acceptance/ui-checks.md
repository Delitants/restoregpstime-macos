# Native interface acceptance

Status: implemented; a partial native ARM64/macOS 27 smoke pass completed on 2026-10-22 after the Mac was unlocked. Full release acceptance remains open.

## Automated evidence on the development ARM64 host

- `AppModelTests`: default Save Copies; Apply requires a current eligible frozen preview; settings invalidate preview; stale asynchronous import/preview results are discarded; blocked, excluded and failed rows remain; cancellation and explicit recovery; inspector date source, actual tag destinations and manual correction come from the plan.
- `ReportExporterTests`: coordinate fields are off by default; JSON preserves selected value types; CSV formula-leading filenames are data; reports include the recovery root.
- `RecoveryBrowserTests`: missing roots do not get created; incomplete batches sort first; linked manifests fail closed. The catalogue decodes operational headers rather than keeping source metadata in memory.
- `LiveAppBackendTests`: actual bundled engine, offline place database, native coordination and private disposable fixture directories. These test model-to-engine integration, not graphical interactions.

## Native UI acceptance (partial)

Use only `Tests/Fixtures` generated media, copied to a fresh private `work/ui-qa/` directory. Select a recovery folder inside that directory, not the default user Library folder. Preserve failed runs.

| Check | Evidence / state |
|---|---|
| Minimum and larger window | Simplified layout observed at 1100 × 720 content (1100 × 748 including native title bar) and 1280 × 820. Main, workflow, undo and file-details button words remain fully visible. |
| Light and dark appearance | Light and app-local Dark observed at minimum width; larger Light layout also observed. Screenshots retained privately. |
| Table horizontal scrolling and sorting; on-demand details | File-details sheet opens and closes without narrowing the table. Native sorting/scroll acceptance remains partial. |
| Keyboard import and preview; accessibility labels and focus | Command-O import and Command-Shift-P preview passed; accessibility text observed. VoiceOver and full focus traversal remain pending. |
| File and folder import; drag and drop; recursion and exclusions | Native single-file and folder import passed; drop/recursion/exclusion interaction remains pending. |
| Capture zone and QuickTime interpretation; preview invalidation | Explicit-offset interpretation and option/correction invalidation passed; offset-free/QuickTime/DST choices remain pending. |
| Offline approximate place; manual correction; qualified tag destinations | Passed: approximate Paris place/distance, qualified JPEG comment destination, manual city correction and per-place numbering. |
| Save Copies with original hashes unchanged | Passed on generated JPEG/HEIC/TIFF/PNG/MOV: five committed, three metadata-free baseline fixtures blocked; independent disk readback below. |
| Modify in Place followed by guarded recovery | Passed on generated JPEG/HEIC/TIFF/PNG/MOV: five committed, three metadata-free baseline fixtures blocked; independent disk readback below. |
| Cancellation retaining partial report | pending native interaction |
| Runtime missing / invalid error with processing unavailable | pending deliberately incomplete test bundle |
| External recovery conflict and restore to separate folder | Passed: edited generated copy was refused/preserved; five retained in-place originals restored separately with matching hashes. Save Copies has no retained originals and correctly reports unavailable. |
| Local JSON/CSV report; coordinates opt-in; diagnostics export | Local JSON export passed with coordinates off by default and absent from JSON. CSV/coordinate opt-in/diagnostics native interaction remains pending. |
| Finder Show/Hide/Restore review sheet | Show Hidden Files review sheet and Cancel passed; Hide/Restore sheets pending. No preference mutation/restart. |

The unlocked pass used only generated fixtures in a private `work/ui-qa/native-*` directory, with recovery explicitly scoped there. Source `b12a2ef` completed Save Copies, manual correction, in-place changes and guarded recovery. Disk readback confirmed all eight source byte hashes unchanged after copies, five output creation/modification times matching `2024-01-02T01:04:05Z` (subseconds retained where present), and all eight original filenames/hashes restored after in-place recovery. Newer generated output remained unchanged during conflict handling. Five separately recovered media hashes matched originals; retained private transaction attribute archives were inventoried separately.

Native inspection exposed missing AM/PM in a 12-hour locale. `DisplayDateTests` reproduced 12 unique labels for 24 hours in en_US (RED); preserving the localized AM/PM marker passed all hours in en_US/en_GB/fr_FR (GREEN). Source `9aa5cde` was rebuilt and the native inspector showed `01/01/2024, 03:04:05 PM -1000`. Full regression: 239 passed, one opt-in system Trash skip, zero failures. Screenshots, UI records, hashes and the initial misclassified archive verification are retained locally; no raw media paths or precise-coordinate reports are public artifacts.

Workflow export/reload also passed: the document omitted source/destination/recovery paths and manual overrides, reload reset Save Copies, cleared both destinations and left Apply disabled. No system appearance, Finder visibility preference, Finder restart, or Gatekeeper policy was changed.

Native Finder preference mutation/restart qualification requires the isolated login/session recorded in the host acceptance matrix. Native Intel and macOS 13 qualification remain separate gates.

## Approved interface simplification

The 2026-10-22 bounded UI revision was explicitly approved in chat. The file list is wider, File details is a separate on-demand sheet, settings use one column, and More tools groups secondary screens. Save copies shows only Save copies to. Change originals explains automatic backups and places Originals backup under Advanced backup settings. Backups & undo and Workflows use the full content area. More holds refresh, clear, import options and report actions. Buttons reserve their label widths; advanced metadata/time-zone/naming options are disclosed on demand.

The main app configures trusted automatic undo storage when loading portable workflows. The document still cannot supply source/destination/backup paths, resets Save Copies and cannot apply automatically. A regression first failed on missing automatic storage, then passed. Native inspection also reproduced stale Building a preview/missing-destination text after failure and after selecting a folder. The added regression failed three assertions, then the model fix passed all 26 app cases: stopped preview has honest guidance, changing settings clears the stale issue and requires a fresh preview.

The simplified native QA build saved five generated date/location/rename copies, kept three baseline files blocked, and left all eight original hashes unchanged. Creation/mtime readback matched the known EXIF instant. Main save modes, full workflow/undo button labels, the File details sheet, report access with coordinates default-off, and app-local Dark were observed. A separate QA bundle identity was used only to avoid existing window-restoration preferences when measuring the minimum default; its app executable and runtime were unchanged. This is smoke evidence, not complete host/format/VoiceOver/Instruments/distribution qualification.
