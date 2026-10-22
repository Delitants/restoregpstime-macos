# Filesystem and Finder acceptance

The production driver applies verified embedded edits, selected Finder fields and final
filesystem dates in that order. Final file/folder locks are installed at commit. Dates are
read back within one microsecond; nanosecond-exact preservation is not established by these
checks. The 1904 reset value is explicit rather than a claim that mandatory dates disappear.

Creator/type edits preserve the other FinderInfo bytes. Labels preserve user tags. WhereFroms
removal preserves quarantine and other attributes. Locked in-place sources require explicit
Unlock; Save Copies reads the original and applies the intended lock to the independent copy.
Notification-only in-place requests send a file-change notice without replacing files or
requiring a recovery folder. Other combined operations notify their committed destinations.

Native generated-file checks cover original-parent unlock before children, final nested
locks, cancellation after a child commit, original and repeated recovery, copy-folder undo,
and rejection of a copy folder with an external added child. Unknown recovery states remain
blocked. Failed evidence and verified originals are retained.

Cleanup is a separate scoped preview and system Trash operation. It accepts hidden regular
files, excludes packages/symlinks/private transaction folders and revalidates roots and file
fingerprints. There is no permanent-delete fallback. Native system Trash acceptance passed
on a generated UUID text fixture; destination receipts remain local. System-added macl and
provenance attributes are allowed at the Trash destination, while stored bytes and size/mtime
are independently checked. No Trash contents were purged.

The Show/Hide Hidden Files tools use only `com.apple.finder` / `AppleShowAllFiles` and retain
the exact prior absent/bool/string/integer state in a private phase record. Preview is read-only;
Apply and graceful Finder restart are separate choices. Six isolated backend tests cover
conflicts, restart refusal and restoration across controller recreation. Native preference
writes/restarts have **not** been run in the user's current login. An explicitly authorized
isolated login/session is required for that release qualification.

The acceptance CSVs map all 31 reference actions and two Tools commands to actual owning
checks. This mapping does not claim every format, filesystem or OS/CPU variant is qualified.
