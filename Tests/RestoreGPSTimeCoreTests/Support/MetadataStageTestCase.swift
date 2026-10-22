import XCTest
@testable import RestoreGPSTimeCore

class MetadataStageTestCase:CoreTestCase {
    private var owned=[URL]()
    func ownedStage(_ name:String) throws -> URL {
        let root=try FileSystemPath.canonicalDirectory(workspace).appendingPathComponent(".RestoreGPSTime-"+UUID().uuidString)
        try SecureFS.privateDirectory(root)
        let source=try fixture(name),stage=root.appendingPathComponent(name)
        _ = try SecureFS.copy(FileIdentityReader().fingerprint(at:source),from:SecureFS.canonical(source),to:stage)
        try StageOwnership.shared.register(stage,root:root)
        owned.append(stage)
        return stage
    }
    override func tearDownWithError() throws {
        for stage in owned {StageOwnership.shared.remove(stage)}
        if (testRun?.totalFailureCount ?? 0)>0,let workspace {
            let path=repository.appendingPathComponent("work/failed-metadata/"+UUID().uuidString)
            try FileManager.default.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true)
            try FileManager.default.moveItem(at:workspace,to:path);self.workspace=nil
        }
        try super.tearDownWithError()
    }
}
