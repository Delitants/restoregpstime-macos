import Foundation
import AppKit

public protocol FinderNotifying:Sendable {func notify(changed urls:[URL]) async}
public struct FinderNotifier:FinderNotifying {
    public init() {}
    public func notify(changed urls:[URL]) async {
        let paths=Set(urls.filter(\.isFileURL).map {$0.standardizedFileURL.path}).sorted()
        await MainActor.run {for path in paths {NSWorkspace.shared.noteFileSystemChanged(path)}}
    }
}
