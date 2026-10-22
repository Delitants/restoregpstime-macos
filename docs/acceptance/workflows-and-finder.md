# Workflow, droplet, and Finder integration acceptance

Implemented data paths are independently tested. Native Finder/Services/drop/launch acceptance is pending a Mac unlock and the required native host matrix.

## Workflow format

Schema 1 `.rgtimeworkflow` documents contain only the workflow name and portable operation settings. Per-file place corrections, physical source identities, grouping overrides, input paths, output/recovery/reference roots, and previously read metadata are omitted. Loading rejects future schema versions, unknown nested fields, executable instructions, invalid tag operations, and path-producing rename templates. A file is bounded to one MiB and read without following a final symlink.

Import validates the whole request before changing the current batch. Imported workflows reset to Save Copies and require destination/reference selections. Opening a workflow/droplet attempts preview and leaves Apply untouched. Before an output folder is selected, the batch displays the required-folder error rather than inventing an output anchor.

## Droplets

Each export assembles fixed native executable/resource components with its validated workflow, gets a fresh bundle identifier, and is signed and verified ad-hoc. It does not inherit the main app's identity, Developer ID signature, or notarization. Export refuses existing destinations and retains incomplete exports on failure. Local ad-hoc exports have distribution limits; Gatekeeper is not disabled.

The actual droplet executable receives files from AppKit, locates the installed main app by its fixed bundle identifier, validates its embedded workflow, and opens a private bounded handoff document in that app. Handoff data permits local file URLs only, carries no Apply operation, and is saved in a user-private temporary directory/file. The main app rejects unknown or non-private handoff documents and requires normal destination selection and preview.

A missing main app produces an error and leaves dropped files unchanged. No helper engine is bundled into each exported droplet; all processing occurs in the main app.

## Shared import boundary

The Add Files panel, native drop target, document Open With, Services provider, and droplet handoff route through `DocumentImporter`. AppSession serializes overlapping OS imports. A running mutation batch rejects a new import explicitly; an asynchronous parse rechecks busy state before changing settings. No route calls `applyPreview`.

`WorkflowTests`, `DropletTests`, and `ImportTests` cover schema/path privacy, malicious nested keys, private handoff bounds, relocation of exported bundle resources, unique identities, local signature verification, rejected existing exports, required destinations, invalid-document atomicity, shared Service routing, and overlapping imports with zero executor calls. Export assembly tests use an inert native executable and are **not** actual Finder/drop acceptance.

## Native OS checklist — all pending

- Main app Open With and relaunch with several selected photos/videos/folders.
- Finder Service registration in a disposable candidate installation; selection arrives once with correct paths.
- Native drag/drop and overlapping Open With calls.
- Export actual droplet, move it, and drop generated files; main app opens preview without applying.
- Native missing-main-app error in an isolated test setup without changing the user's main app installation.
- Verify each architecture natively, including macOS 13.
- Quarantined exported droplets retain normal Gatekeeper behavior; no security bypass.

Local synthetic fixtures and handoff records remain outside public source/assets. No user media or live Finder preferences were used in these tests.
