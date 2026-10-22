# Native interface acceptance

Status: implemented; native visual/interaction acceptance is pending a Mac unlock.

## Automated evidence on the development ARM64 host

- `AppModelTests`: default Save Copies; Apply requires a current eligible frozen preview; settings invalidate preview; stale asynchronous import/preview results are discarded; blocked, excluded and failed rows remain; cancellation and explicit recovery; inspector date source, actual tag destinations and manual correction come from the plan.
- `ReportExporterTests`: coordinate fields are off by default; JSON preserves selected value types; CSV formula-leading filenames are data; reports include the recovery root.
- `RecoveryBrowserTests`: missing roots do not get created; incomplete batches sort first; linked manifests fail closed. The catalogue decodes operational headers rather than keeping source metadata in memory.
- `LiveAppBackendTests`: actual bundled engine, offline place database, native coordination and private disposable fixture directories. These test model-to-engine integration, not graphical interactions.

## Required native UI pass (not yet passed)

Use only `Tests/Fixtures` generated media, copied to a fresh private `work/ui-qa/` directory. Select a recovery folder inside that directory, not the default user Library folder. Preserve failed runs.

| Check | Evidence / state |
|---|---|
| 1100 × 720 and larger window | pending screenshots |
| Light and dark appearance | pending screenshots; app-local appearance menu implemented |
| Table horizontal scrolling and sorting; collapsible inspector | pending native interaction |
| Keyboard import and preview; accessibility labels and focus | pending native interaction / VoiceOver |
| File and folder import; drag and drop; recursion and exclusions | pending native interaction |
| Capture zone and QuickTime interpretation; preview invalidation | pending native interaction |
| Offline approximate place; manual correction; qualified tag destinations | pending native interaction |
| Save Copies with original hashes unchanged | pending native interaction; engine integration is independent |
| Modify in Place followed by guarded recovery | pending native interaction; engine integration is independent |
| Cancellation retaining partial report | pending native interaction |
| Runtime missing / invalid error with processing unavailable | pending deliberately incomplete test bundle |
| External recovery conflict and restore to separate folder | pending native interaction |
| Local JSON/CSV report; coordinates opt-in; diagnostics export | pending native interaction |
| Finder Show/Hide/Restore review sheet | pending sheet-only interaction; no live preference mutation |

CUA inventory on 2026-10-22 returned: “The Mac is locked and automatic unlock could not unlock it.” The user was asked to unlock asynchronously. A successful build or unit test is not recorded as visual acceptance. No system appearance, Finder visibility preference, or Finder restart has been changed for this check.

Native Finder preference mutation/restart qualification requires the isolated login/session recorded in the host acceptance matrix. Native Intel and macOS 13 qualification remain separate gates.
