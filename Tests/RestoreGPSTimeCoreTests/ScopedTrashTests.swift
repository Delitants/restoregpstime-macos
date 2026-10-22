import XCTest
import Darwin
@testable import RestoreGPSTimeCore

struct FakeTrashBackend:TrashBackend {
    let root:URL
    var addSystemMetadata=false
    func trash(_ expected:SourceFingerprint) throws -> URL {
        if expected.snapshot.url.lastPathComponent==".untrashable" {throw RestoreError(.io,"Injected Trash refusal")}
        let result=root.appendingPathComponent(expected.snapshot.url.lastPathComponent)
        try FileManager.default.moveItem(at:expected.snapshot.url,to:result)
        if addSystemMetadata {
            let data=Data("system-managed Trash metadata".utf8)
            guard data.withUnsafeBytes({setxattr(result.path,"com.restoregpstime.test-system-trash",$0.baseAddress,data.count,0,XATTR_NOFOLLOW)})==0 else {throw RestoreError(.io,"Cannot create fixture metadata")}
        }
        return result
    }
}
final class ScopedTrashTests:CoreTestCase {
    func testSystemManagedTrashMetadataDoesNotChangePayloadResult() async throws {
        let trash=workspace.appendingPathComponent("fake-trash");try FileManager.default.createDirectory(at:trash,withIntermediateDirectories:false)
        let file=workspace.appendingPathComponent(".generated");try Data("synthetic payload".utf8).write(to:file)
        let tool=ScopedTrash(backend:FakeTrashBackend(root:trash,addSystemMetadata:true)),plan=try await tool.preview(scope:.init(roots:[file]))
        let result=await tool.execute(plan)
        XCTAssertTrue(result.first?.succeeded==true,"\(result.first?.error ?? "Missing receipt")")
    }
    func testScopedHiddenRegularFilesAndRefusedTargets() async throws {
        let selected=workspace.appendingPathComponent("selected"),outside=workspace.appendingPathComponent("outside")
        let trash=workspace.appendingPathComponent("fake-system-trash")
        for folder in [selected,outside,trash,selected.appendingPathComponent("Package.app")] {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)}
        for (folder,name) in [(selected,".hidden"),(selected,"visible.jpg"),(selected,".untrashable"),(outside,".untouched"),(selected.appendingPathComponent("Package.app"),".package-data")] {try Data(name.utf8).write(to:folder.appendingPathComponent(name))}
        try FileManager.default.createSymbolicLink(at:selected.appendingPathComponent(".link"),withDestinationURL:outside.appendingPathComponent(".untouched"))
        let tool=ScopedTrash(backend:FakeTrashBackend(root:trash)),plan=try await tool.preview(scope:.init(roots:[selected],recursive:true))
        XCTAssertEqual(Set(plan.candidates.map {$0.snapshot.url.lastPathComponent}),[".hidden",".untrashable"])
        XCTAssertTrue(FileManager.default.fileExists(atPath:selected.appendingPathComponent(".hidden").path),"Preview must not move files")
        let result=await tool.execute(plan)
        XCTAssertEqual(result.filter(\.succeeded).count,1);XCTAssertEqual(result.filter {!$0.succeeded}.count,1)
        XCTAssertTrue(FileManager.default.fileExists(atPath:selected.appendingPathComponent(".untrashable").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:outside.appendingPathComponent(".untouched").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:selected.appendingPathComponent("Package.app/.package-data").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:selected.appendingPathComponent("visible.jpg").path))
    }
    func testChangedHiddenFileAndReplacedRootAreNotTrashed() async throws {
        let trash=workspace.appendingPathComponent("fake-trash");try FileManager.default.createDirectory(at:trash,withIntermediateDirectories:false)
        let file=workspace.appendingPathComponent(".hidden");try Data("original".utf8).write(to:file)
        let tool=ScopedTrash(backend:FakeTrashBackend(root:trash)),plan=try await tool.preview(scope:.init(roots:[file]))
        try Data("external replacement".utf8).write(to:file)
        let result=await tool.execute(plan)
        XCTAssertTrue(result.allSatisfy {!$0.succeeded});XCTAssertEqual(try Data(contentsOf:file),Data("external replacement".utf8))
        XCTAssertTrue(result.first?.error?.contains("changed after preview")==true)
        let root=workspace.appendingPathComponent("replace-root");try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        try Data("first".utf8).write(to:root.appendingPathComponent(".file"))
        let rootPlan=try await tool.preview(scope:.init(roots:[root]))
        try FileManager.default.moveItem(at:root,to:workspace.appendingPathComponent("old-root"))
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        try Data("external".utf8).write(to:root.appendingPathComponent(".file"))
        let rootResults=await tool.execute(rootPlan)
        XCTAssertTrue(rootResults.first?.error?.contains("root changed")==true)
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent(".file")),Data("external".utf8))
    }
    func testHiddenCleanupUsesSystemTrash() async throws {
        guard ProcessInfo.processInfo.environment["RESTOREGPSTIME_TEST_SYSTEM_TRASH"]=="1" else {throw XCTSkip("Native system Trash acceptance is run separately on a generated UUID fixture.")}
        let file=workspace.appendingPathComponent(".RestoreGPSTime-QA-\(UUID().uuidString).txt")
        try Data("Synthetic system Trash acceptance fixture; no personal data".utf8).write(to:file)
        let tool=ScopedTrash(),plan=try await tool.preview(scope:.init(roots:[file]))
        try JSONEncoder().encode(plan).write(to:repository.appendingPathComponent("work/system-trash-plan-\(plan.id.uuidString).json"))
        let results=await tool.execute(plan),result=try XCTUnwrap(results.first)
        XCTAssertTrue(result.succeeded,"\(result.error ?? "Missing receipt")")
        let destination=try XCTUnwrap(result.trashedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath:file.path));XCTAssertTrue(FileManager.default.fileExists(atPath:destination.path))
        try JSONEncoder().encode(results).write(to:repository.appendingPathComponent("work/system-trash-receipt-\(UUID().uuidString).json"))
        // System Trash keeps this generated fixture; this test never empties or purges Trash.
    }
}
