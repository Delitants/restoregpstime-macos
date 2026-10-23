# Automatic missing-offset handling — 0.1.2

New app sessions enable automatic handling. Embedded offsets retain priority. Offset-free capture metadata uses ExifTool's offline GeolocationTimeZone only with consistent valid GPS coordinates, a valid IANA zone and a finite city distance of 0–25 km. The time zone uses Foundation historical rules at the capture date. Nearest-city estimates can be wrong near borders and are flagged in File details. No network lookup is used.

Without usable GPS, one time zone selected for the batch is required; the Mac's current zone is never silently substituted. Explicit QuickTime integer interpretation and DST fold/gap safeguards remain in force. Old saved policies decode as strict mode. Filename-derived dates use the fallback rather than GPS context.

Regression evidence: 230 core tests (one opt-in Trash test skipped), 35 app tests, and three QA tests passed on Apple Silicon. Fourteen release-gate contract tests also passed. New tests cover Paris winter/summer, New York and Tokyo, explicit offset precedence, missing/invalid/distant or unproved GPS zones, legacy policy decoding, the bundled reader's single/batch offline zone and a generated photo without GPS.

Native UI checks and per-architecture packaging receipts are retained with the release qualification evidence. Physical Intel and macOS 13 hosts, polygon-accurate timezone mapping, and a full real-media performance matrix remain unqualified.

Native UI: the title and header displayed 0.1.2, automatic handling was checked, and three generated files previewed as two eligible/one blocked before selecting Europe/Paris once, then three eligible/zero blocked. The embedded-offset HEIC kept its instant; GPS provenance and approximation warning were visible in File details. No changes were applied to user media.

Intel qualification used x86_64 test bundles and an explicit Rosetta XCTest runner. Core (230, one opt-in skip) and QA (3) passed; all 35 app tests passed after increasing only the helper-readiness deadline from three to fifteen seconds, retaining exact child-count, cancellation, termination and permit assertions. The original timeout and SwiftPM's incompatible-architecture Swift Testing/discovery-helper failures were retained. No production code changed for the harness correction. This is translated execution, not physical Intel acceptance.
