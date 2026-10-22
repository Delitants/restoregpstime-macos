import Foundation
import Darwin

public enum FileSystemPath {
    // NSURL deliberately retains some system aliases (including /var). realpath does not.
    public static func canonicalDirectory(_ url:URL) throws -> URL {
        guard url.isFileURL,!url.path.utf8.contains(0),let pointer=realpath(url.path,nil) else {throw RestoreError(.io,"Cannot resolve the existing directory identity.")}
        defer {free(pointer)}
        return URL(fileURLWithPath:String(cString:pointer),isDirectory:true)
    }
}
