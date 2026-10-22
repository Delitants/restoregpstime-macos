import Foundation
import Darwin

public struct StageResult:Sendable {
    public var record:RecoveryRecord
    public var expectedSources:[String:SourceFingerprint]=[:]
    public var ownedDirectories:[String:SourceID]=[:]
}
struct StageStore {
    func prepare(_ record:inout RecoveryRecord,journal:RecoveryJournal,driver:any MutationDriver,options:RunOptions) async throws {
        var directories=[String:URL]()
        for index in record.members.indices {
            let item=record.members[index].item
            guard let anchor=item.destinationAnchor else {throw RestoreError(.conflict,"Missing destination identity.")}
            let root:URL
            if let existing=directories[anchor.resolvedURL.path] {root=existing}
            else {
                root=anchor.resolvedURL.appendingPathComponent(".RestoreGPSTime-\(record.batchID.uuidString)-\(record.groupID.uuidString)")
                record.stageDirectories.append(root);try journal.persist(record)
                try SecureFS.privateDirectory(root);directories[anchor.resolvedURL.path]=root
                try SecureFS.requireSpace(at:root,bytes:record.members.reduce(UInt64(1_048_576)) {$0 &+ $1.item.source.snapshot.id.size})
            }
            let stage=root.appendingPathComponent("\(index).stage").appendingPathExtension(item.mutation.outputKind == .xmpSidecar ? "xmp":item.source.snapshot.url.pathExtension)
            record.members[index].stageURL=stage;record.members[index].heldOriginalURL=root.appendingPathComponent("\(index).held-original");try journal.persist(record)
            try options.checkpoint(.beforeStage(item.name.sourceKey));try Task.checkCancellation()
            if item.mutation.outputKind == .xmpSidecar {
                let data=Data("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description rdf:about=\"\"/></rdf:RDF></x:xmpmeta>".utf8)
                try data.write(to:stage,options:.withoutOverwriting)
            } else {
                _ = try SecureFS.copy(try FileIdentityReader().fingerprint(at:item.source.snapshot.url),from:try SecureFS.canonical(item.source.snapshot.url),to:stage)
                try SecureFS.applyMetadata(item.source.snapshot,from:try SecureFS.canonical(item.source.snapshot.url),to:stage)
            }
        }
        record.phase = .staged;try journal.persist(record);try options.checkpoint(.persisted(.staged))
        for index in record.members.indices {
            try Task.checkCancellation()
            let item=record.members[index].item,stage=record.members[index].stageURL!
            let result=try await driver.apply(item.mutation,to:stage)
            let fingerprint=try FileIdentityReader().fingerprint(at:stage)
            guard result.contentHash==fingerprint.contentHash else {throw RestoreError(.verificationFailed,"The stage changed after driver verification.")}
            if !item.mutation.changesContent && fingerprint.contentHash != item.source.contentHash {throw RestoreError(.verificationFailed,"An attribute-only operation changed file bytes.")}
            if item.mutation.changesContent && result.integrityValidator=="sha256-v1" {throw RestoreError(.verificationFailed,"Embedded writes require a media-specific integrity validator.")}
            // Immutable flags are installed only after the directory-entry commit.
            if fingerprint.snapshot.flags & UInt32(UF_IMMUTABLE) != 0 {try SecureFS.flags(stage,fingerprint.snapshot.flags & ~UInt32(UF_IMMUTABLE))}
            let fd=open(stage.path,O_RDONLY|O_NOFOLLOW);guard fd>=0 else {throw SecureFS.error("Open verified stage")};let synced=fsync(fd);close(fd);guard synced==0 else {throw SecureFS.error("Sync verified stage")}
            record.members[index].staged=try FileIdentityReader().fingerprint(at:stage)
        }
        record.phase = .verified;try journal.persist(record);try options.checkpoint(.persisted(.verified))
    }
}
