# Install RestoreGPSTime

RestoreGPSTime targets macOS 13 and newer. Choose **AppleSilicon** for an Apple Silicon Mac or **Intel** for an Intel Mac. Each download contains only its named architecture. The two 0.1.0 downloads are self-signed previews: Apple Silicon was tested natively and Intel through Rosetta on Apple Silicon. Physical Intel/macOS 13 qualification and Apple notarization remain pending.

For these preview releases, verify the download against the attached `SHA256SUMS.txt`, expand the ZIP and move RestoreGPSTime.app into Applications. The public `.cer` file documents the self-signed identity and contains no private key. It is not an Apple-issued certificate. macOS may block the downloaded app or show an unidentified-developer warning; these previews do not establish Apple Gatekeeper trust.

For a completed stable release, verify the archive against `SHA256SUMS.txt`, open the DMG and drag RestoreGPSTime into Applications, or expand the ZIP and move the app there. Open it normally. Stable downloads must pass Gatekeeper with Developer ID signing and notarization. Do not disable Gatekeeper to install a development candidate.

The metadata engine, Perl runtime and offline place database are bundled. No Homebrew, separate Perl, online map, account or location permission is required. All media processing and coordinate lookup stay on the Mac.

Start with disposable copies. Add files or folders, choose operations and explicit camera/output time-zone rules, select **Save copies** and choose **Save copies to**. Undo records are managed automatically; you do not choose a second destination. Use **Preview changes**, then select a row and open **File details** to review date provenance, approximate place and distance, metadata destinations, grouped assets and resulting names. Apply uses that frozen preview. Changing options invalidates it. **Change originals** retains originals for undo. A custom **Originals backup** folder is available under **Advanced backup settings**. Open **More tools → Backups & undo** to manage retained batches.

Location matches are nearby populated places, not verified addresses or GPS accuracy corrections. Set the maximum distance and choose a candidate or manual correction. Missing GPS/capture metadata remains visible; the app does not invent it.

Workflows contain data-only operation settings. Opened workflows, Services input and exported droplets bring files to review; they never apply automatically. A droplet needs the main application installed. Finder visibility and hidden-file Trash are separate Tools actions with explicit previews.

Use **More → Export report** for a local JSON/CSV export. Coordinates are omitted by default; paths, place names, selected changes and recovery references are included. Share only a report you have reviewed.
