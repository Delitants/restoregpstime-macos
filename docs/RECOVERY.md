# Recover a batch

In-place operations retain original bytes and attribute evidence in the chosen recovery folder. Keep that folder and any private `.RestoreGPSTime-*` staging directories until the batch has been reviewed. Do not treat these as disposable hidden files.

Open the Recovery section and select the recovery root. The browser lists unfinished batches without automatically replaying them. Review the batch and choose original locations or a separate folder. Original-location recovery verifies file identities, content, dates, attributes and commit state. Newer or unrelated work is a conflict; it is not overwritten. Use separate-folder recovery to retrieve retained originals while preserving conflicting current files.

Cancellation stops remaining work and waits for an already protected group commit. Reports retain committed, failed, blocked, cancelled and recovery-needed rows. An interrupted compound asset may require recovery of the complete group. Keep its journal and all related members.

Save Copies leaves source bytes and attributes intact. Recovery can remove only a verified app-created output at its original identity. An edited output is retained as a conflict. Separate-folder recovery never deletes the current output.

The scoped hidden-file Tool moves only the previewed ordinary files to the system Trash. Export its local receipt to retain actual Trash destinations and individual errors. Restore these through Finder's normal Trash recovery. The Tool has no permanent-delete fallback and never empties Trash.

Finder visibility has its own previous-preference record. Use Tools → Restore Previous Finder Visibility. Finder restart is a separate explicit choice. A file's hidden state and Finder's global display preference are different operations.
