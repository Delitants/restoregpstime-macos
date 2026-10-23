# Install and use RestoreGPSTime

Requires macOS 13+. Download **Apple Silicon** or **Intel** for your Mac, expand the ZIP, and move RestoreGPSTime into Applications.

These downloads are self-signed and unnotarized. If macOS blocks the first launch, choose **Done**, then open **System Settings → Privacy & Security → Open Anyway** and confirm **Open**. [Apple's instructions](https://support.apple.com/en-us/102445). You do not need to install the attached certificate.

To check a download, place the release attachments in one folder and run `shasum -a 256 -c SHA256SUMS.txt` there.

## Make changes

1. Add files or folders and choose **Save copies** or **Change originals**.
2. Select the changes you want, then click **Preview changes** in each tab you use. Switching tabs keeps your previews.
3. Review the proposed dates and names. Select a file and open **File details** for explanations or blocked reasons.
4. Click **Apply Changes**. If saving copies, choose the destination when asked.

If you change settings, preview that tab again. Thumbnails are optional; settings are remembered when you close the app.

## Dates and locations

Missing UTC offsets are handled automatically using the embedded offset, then an estimated GPS time zone, then the **Fallback time zone for this batch** you select. Choose where those remaining photos were taken.

Place lookup works offline. Matches are nearby cities and countries; review the results before renaming. You can choose another match or enter a correction.

## Backups

Changing originals uses **Metadata backup** by default. Keep the processed files unchanged so they can be restored. Choose **Full backup** to keep entire originals, or **No backup** to turn off undo.

[Backups and undo](RECOVERY.md) · [Known limits](KNOWN-LIMITS.md)
