import Foundation
import CryptoKit

public struct DependencyIdentityProvider:Sendable {
    private let paths:RuntimePaths,policyRoot:URL
    public init(paths:RuntimePaths,policyRoot:URL?=nil) {self.paths=paths;self.policyRoot=policyRoot ?? paths.appBundle.appendingPathComponent("Contents/Resources")}
    public func observe() async throws -> DependencyIdentity {
        let worker=Task.detached(priority:.userInitiated) {try read()}
        return try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
    }
    private func read() throws -> DependencyIdentity {
        let reader=FileIdentityReader()
        func hash(_ url:URL) throws -> String {
            guard try reader.snapshot(at:url).kind == .regular else {throw RestoreError(.unsupported,"A dependency is not an ordinary bundled file: \(url.lastPathComponent).")}
            return try reader.fingerprint(at:url).contentHash
        }
        var engine=SHA256(),policy=SHA256(),count=0
        func tree(_ url:URL,label:String) throws {
            try Task.checkCancellation();count+=1
            guard count<=100000 else {throw RestoreError(.unsupported,"The runtime dependency inventory exceeds its bound.")}
            if url.standardizedFileURL.path==paths.database.standardizedFileURL.path {return}
            let snapshot=try reader.snapshot(at:url)
            switch snapshot.kind {
            case .regular:engine.field(label);engine.field(try hash(url))
            case .directory:
                engine.field("directory:"+label)
                for child in try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil).sorted(by:{$0.lastPathComponent<$1.lastPathComponent}) {try tree(child,label:label+"/"+child.lastPathComponent)}
            default:throw RestoreError(.unsupported,"Runtime dependencies cannot be links, packages or unavailable files.")
            }
        }
        for (url,label) in [(paths.appBundle.appendingPathComponent("Contents/MacOS/RestoreGPSTime"),"application"),(paths.perl,"interpreter"),(paths.exifToolRoot,"metadata-engine"),(paths.runtimeRoot,"runtime-libraries"),(paths.nativeModules,"native-modules")] {try tree(url,label:label)}
        let database=try hash(paths.database)
        for name in ["container-capabilities.json","writable-tags.json"] {policy.field(name);policy.field(try hash(policyRoot.appendingPathComponent(name)))}
        return .init(engineHash:engine.finalize().hex,databaseHash:database,capabilityHash:policy.finalize().hex)
    }
}
