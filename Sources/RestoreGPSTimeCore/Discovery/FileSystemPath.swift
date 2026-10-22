import Foundation
import Darwin

public enum FileSystemPath {
    // NSURL deliberately retains some system aliases (including /var). realpath does not.
    public static func canonicalDirectory(_ url:URL) throws -> URL {
        guard url.isFileURL,!url.path.utf8.contains(0),let pointer=realpath(url.path,nil) else {throw RestoreError(.io,"Cannot resolve the existing directory identity.")}
        defer {free(pointer)}
        return URL(fileURLWithPath:String(cString:pointer),isDirectory:true)
    }
    /// Keep lexical components intact while locating an existing ancestor. URL
    /// standardization can rewrite /private/tmp only after part of a path exists.
    static func existingAncestor(of url:URL) throws -> (parent:URL,components:[String]) {
        guard url.isFileURL,url.path.hasPrefix("/"),!url.path.utf8.contains(0) else {throw RestoreError(.invalidInput,"Invalid local path.")}
        var parts=url.path.split(separator:"/").map(String.init),missing=[String]()
        guard parts.allSatisfy({$0 != "." && $0 != ".."}) else {throw RestoreError(.invalidInput,"Directory traversal is not allowed.")}
        while true {
            let path="/"+parts.joined(separator:"/");var st=stat()
            if lstat(path,&st)==0 {return (URL(fileURLWithPath:path,isDirectory:true),missing.reversed())}
            guard errno==ENOENT,let component=parts.popLast() else {throw RestoreError(.io,"Cannot inspect a destination parent.")}
            missing.append(component)
        }
    }
    static func relativeComponents(of url:URL,under root:URL) throws -> [String] {
        let parts=url.path.split(separator:"/").map(String.init),base=root.path.split(separator:"/").map(String.init)
        guard url.isFileURL,root.isFileURL,parts.allSatisfy({$0 != "." && $0 != ".."}),parts.starts(with:base) else {throw RestoreError(.conflict,"Destination is outside its frozen parent.")}
        return Array(parts.dropFirst(base.count))
    }
}
