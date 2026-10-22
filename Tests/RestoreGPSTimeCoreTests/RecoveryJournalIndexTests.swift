import XCTest
@testable import RestoreGPSTimeCore
final class RecoveryJournalIndexTests:TransactionTestCase {
    func testPointLookupReadsOnlyTheRequestedManifestAndRejectsLinks() async throws {
        let input=try item("journal.HEIC"),plan=try await transactionPlan([input]),group=try XCTUnwrap(plan.groups.first)
        let journal=try RecoveryJournal(root:recoveryRoot,batchID:plan.id),record=RecoveryRecord(batchID:plan.id,group:group,options:plan.options)
        try journal.persist(record)
        let unrelated=journal.recordURL(groupID:UUID());try Data("invalid unrelated record".utf8).write(to:unrelated)
        XCTAssertEqual(try journal.record(groupID:group.id),record)
        XCTAssertNil(try journal.record(groupID:UUID()))
        try FileManager.default.removeItem(at:journal.recordURL(groupID:group.id))
        try FileManager.default.createSymbolicLink(at:journal.recordURL(groupID:group.id),withDestinationURL:unrelated)
        XCTAssertThrowsError(try journal.record(groupID:group.id))
    }
}
