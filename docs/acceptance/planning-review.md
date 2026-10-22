# RestoreGPSTime planning review

Date: 2026-10-21, Pacific/Honolulu. Scope: document self-review, not software acceptance.

## User decisions carried into the documents

- Final app name: **RestoreGPSTime**, replacing MediaRestorer.
- Minimum operating system: **macOS 13.0** for Apple Silicon and Intel.
- Place lookup: **offline**, using the bundled city database with approximate matches and manual corrections.
- Main capabilities: embedded-date recovery, place comments/structured fields and numbering, broad photo/video support, batches, copies and recoverable in-place edits.
- Two separate release tags and artifact sets; publish to Delitants on GitHub when qualified.
- Current requested stage: written specification and implementation plan. Product implementation has not been started.

## Review results

- All **16 requirements** have named plan tasks.
- All **31 reference action IDs** A01–A31 have behavior, constraints, a test owner and plan-task ownership.
- The two additional Finder visibility commands X01–X02 have separate Tools ownership, explicit user action, previous-state restoration and isolated qualification requirements. They are not batch side effects.
- All **13 tasks** T01–T13 have files, consumed/produced interfaces, a failing-test step, verification steps, implementation guidance and a bounded commit step.
- The plan copies the specification's global constraints and identifies this turn's planning-only constraint separately from later execution.
- Shared type ownership was made explicit, including tag mutations before location planning, the clock/date contracts, staged verification, report records and native-host evidence.
- Missing-zone/DST policies, non-UTC camera QuickTime dates, filesystem date resets, safe stripping limits, linked-asset naming, no-overwrite commits and restore conflicts have concrete test expectations.
- Native Intel evidence must check hardware/translation state; Rosetta is never counted as a native Intel pass.
- No placeholder sections or broken local document links remain. The specification's local audit link intentionally points outside the future source repository; T13 replaces it with an audited public description before publication.
- Source support tables distinguish read access from embedded write qualification. The plan cannot call a format writable solely because ExifTool broadly lists the format.
- The plan's proposed repository identifier and original-code MIT license remain visible for the user's document review.

A mechanical document check verifies IDs, task sections, copied constraints, CSV columns/owners, relative links and balanced code fences. Its scratch receipt is retained in this chat's `work/planning/` directory. This check establishes document consistency; it does not compile Swift or prove product behavior.

## Resource gates recorded for later execution

| Resource | What it gates | Current status |
| --- | --- | --- |
| Native ARM64 build/runtime | T01 and subsequent local development | Local host/toolchain found during discovery; no product build attempted |
| Pinned ExifTool/Perl source compatibility | Dependency integration in T01 | Versions selected from primary references; source digests/build feasibility still to verify during implementation |
| Genuine lawful media variants | Per-format integrity/capability qualification | Baseline can be generated; genuine HDR/depth/Live Photo/RAW variants require appropriate fixtures |
| Native Intel and macOS 13 qualification hosts | Stable release claims | Not yet arranged or run; cross-compilation/Rosetta cannot close these gates |
| Developer ID signing and notarization | Default public stable release | No valid signing identity found during discovery; no credential changes attempted |
| Exact public repository/assets | Publication after readiness | Target is proposed; no repository, tags, releases or assets created |

No gate above prevents delivering the requested specification and plan. Unavailable runtime/source/test/signing resources must remain explicit when execution reaches the relevant task.

## Execution handoff

Recommend implementing the reviewed plan in this chat: the date, naming, transaction and validation contracts are tightly coupled, so a single implementation context is useful. Delegated implementation is available if the user selects it; no subagents were spawned for planning.

Ask the user to review the specification and plan and select execution in this chat or delegation. Once that review is received, use the selected execution skill and begin T01. The original app-and-release request remains active in scope beyond this planning deliverable.
