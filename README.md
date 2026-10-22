# RestoreGPSTime

An original native macOS 13+ photo/video metadata and file-attribute utility, being implemented with separate Apple Silicon and Intel releases.

The user approved the specification and implementation plan and chose implementation in this chat. The final app name is **RestoreGPSTime**. Implementation is in progress: the native app/runtime foundation and read-only discovery are under test. The foundation window explicitly has no file-processing controls yet. Local ad-hoc test signing is not Developer ID signing or notarization; no public release has been published.

- [Specification](docs/superpowers/specs/2026-10-21-restoregpstime-design.md): requirements, user flow, date/place semantics, file recovery, format limits and release acceptance.
- [Implementation plan](docs/superpowers/plans/2026-10-21-restoregpstime-implementation.md): 13 tasks, exact contracts, focused test cycles and publication checks.
- [Reference action matrix](docs/acceptance/reference-actions.csv): all 31 actions from the installed reference app, mapped to planned behavior and verification.
- [Reference Tools matrix](docs/acceptance/reference-tools.csv): the two additional Finder visibility commands, with explicit restoration and isolated testing.
- [Planning review](docs/acceptance/planning-review.md): document checks and remaining resource dependencies.

Public publication to `Delitants/restoregpstime-macos` remains scheduled for when both release versions satisfy their acceptance checks. Cross-compilation and Intel execution through Rosetta do not qualify native Intel/macOS 13 or signing gates.

## Development

Use Xcode with Swift 5.9 or newer, Python 3.12+ for build scripts, and the system C compiler/make. The app itself needs no separately installed Perl, Python, Homebrew or ExifTool.

```sh
Scripts/build-app.sh --arch arm64 --configuration debug --output work/test-bundles/arm64-standard
Scripts/test.sh
```

For Intel builds, use `--arch x86_64` and a fresh output directory. Test the matching bundle with `RESTOREGPSTIME_TEST_APP=/absolute/path/to/RestoreGPSTime.app RESTOREGPSTIME_TEST_ARCH=x86_64 Scripts/test.sh`. The local test runner keeps compiler caches under `work/` for restricted development environments.

Dependencies are fetched from their official sources and checked against `Dependencies/dependencies.lock.json`. An existing build output is never overwritten: choose a fresh output directory to retain failed evidence. Generated fixtures contain geometric images and synthetic GPS, with provenance in `Tests/Fixtures/manifest.json`.

No proprietary reference implementation/artwork, personal media, signing credentials or remote GitHub project is included. Dependency source/license notices are retained in `ThirdParty/`; downloaded/build products remain local and ignored.
