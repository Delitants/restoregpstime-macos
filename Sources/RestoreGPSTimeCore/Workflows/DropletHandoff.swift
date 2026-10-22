import Foundation
import Darwin

public struct DropletHandoff:Codable,Equatable,Sendable {
    public let schema:Int,workflow:WorkflowDocument,urls:[URL]
    public init(workflow:WorkflowDocument,urls:[URL]) {schema=1;self.workflow=workflow;self.urls=urls}
    public func write(to directory:URL=FileManager.default.temporaryDirectory) throws -> URL {
        try validate()
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let data=try encoder.encode(self)
        guard data.count<=16_777_216 else {throw RestoreError(.invalidInput,"The droplet handoff exceeds its size bound.")}
        let parent=try FileSystemPath.canonicalDirectory(directory),root=parent.appendingPathComponent("RestoreGPSTime-Handoff-"+UUID().uuidString,isDirectory:true)
        try SecureFS.privateDirectory(root)
        let url=root.appendingPathComponent(UUID().uuidString+".rgtimehandoff")
        try data.write(to:url,options:.withoutOverwriting)
        guard chmod(url.path,0o600)==0 else {throw RestoreError(.io,"Could not restrict handoff file permissions.")}
        return url
    }
    public static func load(from url:URL) throws -> DropletHandoff {
        guard url.isFileURL,url.pathExtension.lowercased()=="rgtimehandoff" else {throw RestoreError(.invalidInput,"Invalid droplet handoff document.")}
        let data=try WorkflowStore.readBounded(url,limit:16_777_216,privateFile:true)
        let value=try JSONDecoder().decode(Self.self,from:data);try value.validate()
        guard let input=try JSONSerialization.jsonObject(with:data) as? [String:Any],let canonical=try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any],(input as NSDictionary).isEqual(canonical as NSDictionary) else {throw RestoreError(.invalidInput,"Unknown handoff fields are not accepted.")}
        return value
    }
    private func validate() throws {
        guard schema==1,!urls.isEmpty,urls.count<=10_000,urls.allSatisfy({$0.isFileURL && $0.path.hasPrefix("/") && !$0.path.utf8.contains(0) && $0.path.utf8.count<=4096}) else {throw RestoreError(.invalidInput,"The handoff requires a bounded list of local files or folders.")}
        _=try WorkflowStore().encode(workflow)
    }
}
