# Install RestoreGPSTime

RestoreGPSTime targets macOS 13 and newer. Choose **AppleSilicon** for an Apple Silicon Mac or **Intel** for an Intel Mac. Each download contains only its named architecture. The two 0.1.0 downloads are self-signed previews: Apple Silicon was tested natively and Intel through Rosetta on Apple Silicon. Physical Intel/macOS 13 qualification and Apple notarization remain pending.

For these preview releases, verify the download against the attached `SHA256SUMS.txt`, expand the ZIP and move RestoreGPSTime.app into Applications. The public `.cer` file documents the self-signed identity and contains no private key. It is not an Apple-issued certificate. macOS may block the downloaded app or show an unidentified-developer warning; these previews do not establish Apple Gatekeeper trust.

## Opening the self-signed preview

If macOS says **“Apple could not verify … free of malware”** or that the developer cannot be verified, the initial alert may offer **Move to Trash** and **Done**. The approval control is in System Settings:

1. Choose **Done** (or **Cancel**) to keep the app.
2. After trying to open RestoreGPSTime, open **System Settings → Privacy & Security** and scroll down to Security.
3. Click **Open Anyway** for RestoreGPSTime, then confirm **Open**. Authenticate if macOS requests it.

macOS saves an exception for this app so subsequent launches can use a normal double-click. [Apple documents this procedure](https://support.apple.com/en-us/102445). Since macOS Sequoia, [Control-click no longer overrides Gatekeeper](https://developer.apple.com/news/?id=saqachfa); use the Settings procedure. Managed Macs may restrict approval.

The app cannot choose the wording or buttons in macOS security alerts. A self-signed certificate cannot replace Apple Developer ID signing and notarization. Do not install the supplied certificate as a trusted root or disable Gatekeeper to install this preview. If the alert says **“is damaged”** or **“will damage your computer”**, retain the downloaded file and report the exact alert and download version for investigation.

## Using the app

For a completed stable release, verify the archive against `SHA256SUMS.txt`, open the DMG and drag RestoreGPSTime into Applications, or expand the ZIP and move the app there. Open it normally. Stable downloads must pass Gatekeeper with Developer ID signing and notarization. Do not disable Gatekeeper to install a development candidate.

The metadata engine, Perl runtime and offline place database are bundled. No Homebrew, separate Perl, online map, account or location permission is required. All media processing and coordinate lookup stay on the Mac.

Start with disposable copies. Add files or folders, choose operations and explicit camera/output time-zone rules, select **Save copies** and choose **Save copies to**. Undo records are managed automatically; you do not choose a second destination. Use **Preview changes**, then select a row and open **File details** to review date provenance, approximate place and distance, metadata destinations, grouped assets and resulting names. Apply uses that frozen preview. Changing options invalidates it. **Change originals** retains originals for undo. A custom **Originals backup** folder is available under **Advanced backup settings**. Open **More tools → Backups & undo** to manage retained batches.

Location matches are nearby populated places, not verified addresses or GPS accuracy corrections. Set the maximum distance and choose a candidate or manual correction. Missing GPS/capture metadata remains visible; the app does not invent it.

Workflows contain data-only operation settings. Opened workflows, Services input and exported droplets bring files to review; they never apply automatically. A droplet needs the main application installed. Finder visibility and hidden-file Trash are separate Tools actions with explicit previews.

Use **More → Export report** for a local JSON/CSV export. Coordinates are omitted by default; paths, place names, selected changes and recovery references are included. Share only a report you have reviewed.
