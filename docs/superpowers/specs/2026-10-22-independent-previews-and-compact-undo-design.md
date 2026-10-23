# RestoreGPSTime: independent previews, compact undo, and persistent settings

Status: proposed design for the requested update. No application changes have been implemented yet.

## Intent

Preview only the action shown in the current tab, keep that result when navigating to another tab, and apply all selected operations together. Remove the output-folder prerequisite from preview. Make proposed results easy to identify, support optional thumbnails, remember settings between launches, and default to a compact metadata backup rather than full media copies.

## Required behavior

### Independent previews and one Apply Changes action

Dates & time, Location names, Metadata, and Finder attributes each have an independent preview component. Preview changes acts only on the current component. Location preview must not re-run date resolution, and date preview must not regenerate location names or write plans. Switching tabs does not invalidate or clear any preview. Editing a component invalidates only that component; its previous results remain visible and clearly marked out of date until refreshed.

One table combines current date and naming results. A summary shows selected batch operations and which components need a preview. Rename the final action to **Apply Changes**. It applies the combined, current previews from every selected operation, regardless of the visible tab. A selected operation without an up-to-date preview must be identified before any writes; it cannot silently use an older result or be skipped. Workflows and Backups & undo remain utilities, not extra file mutations. Scoped Trash and Finder visibility remain their separate explicit tools.

Cached previews share the imported metadata and source fingerprints. Later tab previews can reuse fingerprints only after checking that source identity and attributes still match. Full source-content validation remains required before applying. Linked assets retain protected group semantics. Composition rejects incompatible operations, duplicate destinations, conflicting metadata changes, mismatched source snapshots or changed dependencies. It preserves the exact dates and names already previewed.

### Preview without an output folder

Save copies permits preview with no output folder. Display proposed dates and filenames without inventing a user-facing destination path. The folder picker appears when Apply Changes is used in Save copies mode. A user may also choose a destination explicitly before then.

After a folder is chosen, bind the cached proposals to that folder and validate destination identity, volume naming rules and collisions. This does not re-run unrelated date or location previews. If a destination would change an approved filename or is occupied, show the conflict and require review; never overwrite or silently renumber during Apply. No source or output file is created by preview. Change originals does not request an output folder.

### Proposed columns and thumbnails

Give the Proposed creation and Proposed name headers and cells a light-green background, with readable text and selection contrast in light and dark appearance. Keep full button labels at the minimum supported window size.

Add a thumbnail selector: Off (default), Small, Medium, Large. Use approximately 48, 96, and 160-point thumbnails and corresponding row heights. Generate previews lazily for visible rows with bounded concurrency and caching; avoid decoding all 1,146 originals eagerly. Unsupported or unavailable thumbnails show a placeholder and do not block metadata processing. Preview generation must not modify media.

### Remember settings

Restore operation toggles and values, save mode, destination and backup locations, backup mode, fallback zone, lookup and renaming options, discovery settings, appearance, selected tab, and thumbnail size on next launch. Save settings atomically and tolerate missing, old or damaged preferences without deleting recovery evidence.

Do not automatically apply anything on launch. Do not persist a frozen executable plan, transient progress, previous errors or per-file corrections as if they belonged to new inputs. Source imports and per-file state are separate from preferences. Old workflows and recovery journals retain compatible behavior.

### Three backup modes

- **Metadata backup**: enabled by default for new app settings. Retain a per-file database of original names, dates, permissions, flags, ACLs, extended attributes, original metadata and compact restoration data; do not retain complete media files after successful changes.
- **Full backup**: off by default. Retain entire original files and their metadata for undo.
- **No backup**: available but not selected by default. Clearly state that successful changes have no retained undo. Temporary transaction staging is still used to protect an operation in progress.

The compact database must permit exact restoration of changed bytes and filesystem metadata, including for supported embedded edits. A tag-value JSON export alone is insufficient because it cannot reconstruct unknown metadata, original layout or removed values reliably. Recommended implementation: a native SQLite database holding file metadata plus a bounded reverse delta. Unchanged media bytes are referenced in the verified current output; only changed regions and small boundary chunks are stored. Thus the database can contain small restoration fragments, not just printable EXIF values. Full-file hashes bind the database to the exact original and output.

Compact restoration has a size limit. If an operation cannot be represented safely within that limit, stop before changing originals and explain that Full backup is needed. Never silently retain a full media copy under Metadata backup or silently switch to No backup.

After every protected group has committed and its compact backup is durable, verify and remove its temporary held media originals. Persist compaction intent so a crash during cleanup remains recoverable. Failed or uncertain operations retain evidence and recoverable originals. No backup mode also removes held originals only after successful protected commit.

Undo verifies the output's saved after-state, refuses newer or missing media, reconstructs a temporary exact original from the database and unchanged output bytes, verifies the original full-file hash, restores filesystem metadata and the original name, then verifies the result. Independent files can be selected for undo; linked assets are restored together. Compact undo cannot recreate a deleted or damaged media payload without a full backup. Undo may need temporary working space for a complete file, but should not leave full-file backups behind afterward.

### Location detection versus embedded-write eligibility

Successful GPS lookup must remain visible even when embedded writing is unsupported. The supplied HEIC screenshot shows global write gating on repeated QuickTime codec fields, not a failed location match.

Investigate and test a narrow allowlist of read-only structural HEIC/HEIF codec repetitions. Preserve every occurrence and its value in metadata diff verification and protect encoded media and relationships with the existing container integrity validator. Do not broadly ignore conflicting editable metadata, actual helper errors, malformed files, unqualified auxiliary/HDR layouts, or changed media payloads.

Show separate location-name/rename and embedded-write eligibility. Users can preview and select date/rename operations even when embedded comments are unavailable. If embedded output remains selected and cannot be performed safely, explain which operation is blocked rather than silently omitting it. Real-camera HEIC/MOV qualification requires a representative blocked sample accessible on this Mac; the screenshot alone does not qualify a write to that media.

## Approaches considered

1. Recommended: independent cached component plans, a validated combined apply plan, and a compact database that preserves exact undo data. This meets the requested tab workflow and disk-space goal while retaining safeguards.
2. Re-run the whole batch for every tab, retaining full originals. This is the current design and conflicts with both requested improvements.
3. Store only exposed tag values for metadata backup. Smaller implementation, but incomplete undo for removed/unknown metadata and layouts; rejected because it would promise more recovery than it provides.

The reverse-delta implementation and exact compact-size threshold are engineering choices to qualify with tests; they are not claims already approved by the user.

## Verification and delivery

Use generated files for automated mutation/undo tests. Include independent tab caching and no-op settings writes; combined dates, location metadata, naming and Finder actions; deferred folder selection and destination conflicts; all three backup modes; exact compact undo of dates, names, xattrs and qualified embedded changes; changed-output refusal; interruption during staging, commit and compaction; legacy journals/settings; bounded thumbnail work and cancellation; and benign repeated HEIF codec fields versus changed occurrences.

Check native UI with thumbnails Off and each size, the light-green columns, full labels, tab switching, close/reopen settings and the folder-on-save flow. Preview user media only when available; never apply to the user's remote batch as part of qualification.

Build separate Apple Silicon and Intel macOS 13+ self-signed preview releases, qualify Intel through Rosetta with that limitation stated, verify archives/signatures, update the installed app and publish the separate releases under the existing authorization. Preserve failed evidence and previous installed copies for rollback. Physical Intel, macOS 13 and unqualified real-media coverage remain separate acceptance limits.
