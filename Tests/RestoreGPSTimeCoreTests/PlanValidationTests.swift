import XCTest
@testable import RestoreGPSTimeCore

final class PlanValidationTests:PlanningTestCase {
    func testIdentityOrContentChangeConflicts() async throws {
        let input=try item("a.HEIC"),plan=try await preview(input),identity=self.identity
        try Data("external edit".utf8).write(to:input.snapshot.url)
        let validation=await PlanValidator(dependencies:{identity}).revalidate(plan)
        XCTAssertFalse(validation.isValid);XCTAssertEqual(validation.conflicts.first?.error.code,.conflict)
    }
    func testNewDestinationOrDependencyConflicts() async throws {
        let plan=try await preview(item("a.HEIC")),identity=self.identity
        let name=try XCTUnwrap(plan.groups.first?.items.first?.name)
        try Data("external destination".utf8).write(to:name.finalURL)
        let output=await PlanValidator(dependencies:{identity}).revalidate(plan)
        XCTAssertFalse(output.isValid)
        let dependency=await PlanValidator(dependencies:{DependencyIdentity(engineHash:"changed",databaseHash:identity.databaseHash,capabilityHash:identity.capabilityHash)}).revalidate(plan)
        XCTAssertFalse(dependency.isValid)
    }
    func testHardlinkAndLockedInPlaceBlock() async throws {
        let input=try item("a.HEIC")
        try FileManager.default.linkItem(at:input.snapshot.url,to:workspace.appendingPathComponent("other.HEIC"))
        let current=try item("a.HEIC")
        let plan=try await preview(current,mode:.modifyInPlace)
        XCTAssertEqual(plan.groups.first?.eligibility,.blocked)
    }
}
