# Backups and undo

When changing originals, choose a backup mode:

- **Metadata backup** (default): saves space by keeping the information needed to undo changes. The processed files must remain available and unchanged.
- **Full backup**: keeps entire originals, so recovery does not depend on the processed files.
- **No backup**: disables undo after a successful batch.

Use **Advanced backup settings** to choose where backups are stored. Keep that folder until you no longer need undo.

## Restore files

Open **More tools → Backups & undo**, select a batch, then choose **Undo selected files** or **Undo batch**. Linked photo/video pairs restore together.

**Restore to folder** recovers originals into another folder. Use it when you want to keep current files. Later edits and unrelated files are not overwritten.

If a batch is interrupted, keep its backup folder and any hidden `.RestoreGPSTime-*` folders. Open **Backups & undo** to review and recover it.

Saving copies leaves the originals unchanged. Undo removes only unchanged copies created by the app; edited copies are kept.
