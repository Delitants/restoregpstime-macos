# RestoreGPSTime

Planning documents for an original native macOS 13+ photo/video metadata and file-attribute utility, with separate Apple Silicon and Intel releases.

The user approved the initial design and offline place lookup, renamed the app from MediaRestorer to **RestoreGPSTime**, and requested the written specification and implementation plan. This directory is the local project handoff. **No product code, executable build, product tests, signing or GitHub publication has been completed.**

- [Specification](docs/superpowers/specs/2026-10-21-restoregpstime-design.md): requirements, user flow, date/place semantics, file recovery, format limits and release acceptance.
- [Implementation plan](docs/superpowers/plans/2026-10-21-restoregpstime-implementation.md): 13 tasks, exact contracts, focused test cycles and publication checks.
- [Reference action matrix](docs/acceptance/reference-actions.csv): all 31 actions from the installed reference app, mapped to planned behavior and verification.
- [Reference Tools matrix](docs/acceptance/reference-tools.csv): the two additional Finder visibility commands, with explicit restoration and isolated testing.
- [Planning review](docs/acceptance/planning-review.md): document checks and remaining resource dependencies.

Recommended next step: review the spec and plan, then execute the tasks in this chat. Delegated execution is also available if explicitly selected. Public publication to `Delitants/restoregpstime-macos` remains scheduled for when both release versions satisfy their acceptance checks.

No proprietary reference implementation/artwork, user media, third-party dependency binaries, signing credentials or remote GitHub project is included in this planning handoff.
