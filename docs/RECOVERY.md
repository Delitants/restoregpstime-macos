# Backups and undo

New in-place batches default to **Metadata backup**. The private per-batch SQLite database stores original filesystem attributes and a bounded exact reverse delta. Unchanged media bytes are referenced from the processed file. After a durable verified group commit, temporary full media is removed. Metadata-only undo therefore requires the unchanged processed media; missing, damaged or externally edited files are refused. Choose **Full backup** when recovery must also survive loss of the processed media. **No backup** retains temporary protection for unfinished transactions but disables undo after successful completion. Existing recovery records keep their original full-backup policy.

In **Backups & undo**, select a batch, then select files for **Undo selected files**, or choose **Undo batch**. Selecting a linked photo or video restores its entire linked group. **Restore to folder** reconstructs retained originals in a separate folder. Later edits are never overwritten. Keep the backup database and its private journal together. Interrupted cleanup can leave protected temporary files until recovery completes; those are recovery evidence, not disposable project files.

Compact recovery entries have a 16 MiB limit on stored changed fragments and a 24 MiB encoded-entry limit. If exact compact undo cannot fit or no unchanged media can be safely referenced, the group fails before source commit; choose Full backup and preview again.

# Recover a batch

In-place operations retain undo information according to the chosen backup mode. To choose a custom location, use **Change originals → Advanced backup settings → Backup storage**. Keep that folder and any private `.RestoreGPSTime-*` staging directories until the batch has been reviewed. Do not treat these as disposable hidden files.

Open **More tools → Backups & undo**. **Storage location** can select another undo store when needed. The browser lists unfinished batches without automatically replaying them. Review the batch and choose **Undo batch** or **Restore to folder**. Original-location recovery verifies file identities, content, dates, attributes and commit state. Newer or unrelated work is a conflict; it is not overwritten. Use separate-folder recovery to retrieve retained originals while preserving conflicting current files.

Cancellation stops remaining work and waits for an already protected group commit. Reports retain committed, failed, blocked, cancelled and recovery-needed rows. An interrupted compound asset may require recovery of the complete group. Keep its journal and all related members.

Save Copies leaves source bytes and attributes intact. Recovery can remove only a verified app-created output at its original identity. An edited output is retained as a conflict. **Restore to folder** is available for retained in-place originals; Save copies does not retain redundant source backups. Separate-folder recovery never deletes the current output.

The scoped hidden-file Tool moves only the previewed ordinary files to the system Trash. Export its local receipt to retain actual Trash destinations and individual errors. Restore these through Finder's normal Trash recovery. The Tool has no permanent-delete fallback and never empties Trash.

Finder visibility has its own previous-preference record. Use Tools → Restore Previous Finder Visibility. Finder restart is a separate explicit choice. A file's hidden state and Finder's global display preference are different operations.
