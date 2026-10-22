# Candidate qualification evidence

`RestoreGPSTimeQA` is a separate developer executable. It is never shipped inside the user app and has no hidden mutation switch in the app. Run `Scripts/qualify.sh` on each actual test host with a self-contained app, a lawful fixture manifest and a fresh evidence directory. An incomplete run returns exit code 2 and still writes its report. Missing evidence stays `missing`.

Generated fixture tests cover deterministic behavior. They do not qualify camera RAW, genuine Apple HDR/depth/auxiliary HEIF, paired Live Photos, large real video, exFAT/removable media, other native hardware, or an older OS. Private qualification media and raw reports belong in ignored local storage. Do not upload them to public CI.

Retain actual command output, before/after hashes, media signatures, filesystem attributes and recovery receipts. Native host records include process architecture, hardware ARM capability, Rosetta translation, macOS version/build and the candidate executable hash. Manual UI, Finder/Services/droplet, isolated Finder preferences, offline/quarantine and Instruments checks require their own evidence. A successful build or synthetic suite cannot close these gates.

The stable release checker also requires Developer ID signing, hardened runtime, notarization and stapling. It must verify both architecture sets against one reviewed source commit. Locally ad-hoc signed apps are development candidates.
