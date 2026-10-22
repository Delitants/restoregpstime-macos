import XCTest
import Darwin
@testable import RestoreGPSTimeCore

final class DateUnicodeRegressionTests:CoreTestCase {
    func testUnicodeCompanionSubsecondsProduceErrorsInsteadOfTraps() throws {
        let document=MetadataDocument(tags:["ExifIFD:DateTimeOriginal":.string("2024:01:02 03:04:05Z"),"ExifIFD:SubSecTimeOriginal":.string("١٢٣")])
        XCTAssertThrowsError(try CaptureDateResolver().resolve(document:document,snapshot:FileIdentityReader().snapshot(at:fixture("paris.jpg")),policy:DatePolicy()))
    }
    func testUnicodeAndMalformedDateDigitsProduceErrorsInsteadOfTraps() throws {
        for text in ["٢٠٢٤:01:02 03:04:05Z","2024:０１:02 03:04:05Z","2024:01:02 03:04:05.١٢٣Z","2024:01:02 03:04:05+٠٢:00","2024:01:02 03:04:xxZ"] {
            XCTAssertThrowsError(try WallClockParser().parse(text),text)
        }
        XCTAssertEqual(try WallClockParser().parse("2024:01:02 03:04:05.123456789+02:00").nanoseconds,123456789)
    }
}
final class AliasPathTests:TransactionTestCase {
    func testMissingRecoveryRootsUseExactPrivateAliasComponents() throws {
        let temporary=URL(fileURLWithPath:"/private/tmp/RestoreGPSTime-Alias-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:true)
        defer {if (testRun?.totalFailureCount ?? 0)==0 {try? FileManager.default.removeItem(at:temporary)} else {print("Retained alias fixture: "+temporary.path)}}
        for base in [try FileSystemPath.canonicalDirectory(workspace),temporary] {
            let root=base.appendingPathComponent("Missing scope été/Recovery",isDirectory:true)
            let journal=try RecoveryJournal(root:root,batchID:UUID())
            XCTAssertEqual(journal.root.path,try FileSystemPath.canonicalDirectory(base).path+"/Missing scope été/Recovery")
            XCTAssertTrue(FileManager.default.fileExists(atPath:root.path),"The configured recovery root must contain its journal")
        }
    }
    func testPrivateAliasOutputMatchesTheFrozenPath() async throws {
        let input=try item("input.HEIC"),base=try FileSystemPath.canonicalDirectory(workspace)
        var settings=try options();settings.outputRoot=base.appendingPathComponent("New Output/subfolder",isDirectory:true);settings.recoveryRoot=base.appendingPathComponent("Recovery",isDirectory:true)
        let plan=try await planner().preview(items:[input],request:OperationRequest(),options:settings),entry=try XCTUnwrap(plan.groups.first?.items.first)
        XCTAssertEqual(try Committer.target(entry).path,base.path+"/New Output/subfolder/input.HEIC")
        let report=try await requireReport(plan)
        XCTAssertTrue(report.success,String(describing:report.results))
        XCTAssertTrue(FileManager.default.fileExists(atPath:settings.outputRoot!.appendingPathComponent("input.HEIC").path))
    }
}
final class RecoveryRaceRegressionTests:TransactionTestCase {
    func testInPlaceDisplacedOutputEditConflictsWithoutReverseExchange() async throws {
        let input=try item("swap-edit.HEIC"),plan=try await transactionPlan([input])
        let report=try await requireReport(plan);XCTAssertTrue(report.success)
        let journal=try RecoveryJournal(root:recoveryRoot,batchID:plan.id),record=try XCTUnwrap(journal.records().first)
        let retained=try XCTUnwrap(record.members.first?.stageURL).deletingLastPathComponent().appendingPathComponent("0.restore-stage")
        let newer=Data("Newer edited displaced inode must survive without exchanging back".utf8),faults=TransactionFaults()
        faults.callback={point in if point == .afterMember(0) {let handle=try FileHandle(forWritingTo:retained);defer {try? handle.close()};try handle.truncate(atOffset:0);try handle.write(contentsOf:newer);try handle.synchronize()}}
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver(),options:.init(checkpoint:faults.check)).restoreGroup(record,journal:journal)
        XCTAssertFalse(outcome.isComplete);XCTAssertEqual(try Data(contentsOf:retained),newer)
        XCTAssertEqual(try Data(contentsOf:input.snapshot.url),Data("payload-swap-edit.HEIC".utf8))
        let repeated=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertFalse(repeated.isComplete);XCTAssertEqual(try Data(contentsOf:retained),newer)
    }
    func testPostRetirementEditConflictsAndKeepsBothVersions() async throws {
        for occupied in [false,true] {
            let input=try item("post-\(occupied).HEIC"),plan=try await transactionPlan([input],mode:.saveCopies)
            let report=try await requireReport(plan),output=try XCTUnwrap(report.results.first?.outputs.first)
            let journal=try RecoveryJournal(root:recoveryRoot,batchID:plan.id),record=try XCTUnwrap(journal.records().first)
            let retained=try XCTUnwrap(record.members.first?.stageURL).deletingLastPathComponent().appendingPathComponent("0.restored-output")
            let newer=Data("Newer edit through an open inode after retirement".utf8),other=Data("Unrelated new occupant at the original path".utf8),faults=TransactionFaults()
            faults.callback={point in if point == .afterMember(0) {
                let handle=try FileHandle(forWritingTo:retained);defer {try? handle.close()};try handle.truncate(atOffset:0);try handle.write(contentsOf:newer);try handle.synchronize()
                if occupied {try other.write(to:output,options:.withoutOverwriting)}
            }}
            let result=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver(),options:.init(checkpoint:faults.check)).restoreGroup(record,journal:journal)
            XCTAssertFalse(result.isComplete)
            XCTAssertEqual(try? Data(contentsOf:output),occupied ? other:newer)
            if occupied {XCTAssertEqual(try? Data(contentsOf:retained),newer)}
            let repeated=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
            XCTAssertFalse(repeated.isComplete)
        }
    }
    func testNewerOutputAfterRecoveryJournalBoundaryStaysInPlaceAndConflicts() async throws {
        let input=try item("restore.HEIC"),plan=try await transactionPlan([input],mode:.saveCopies)
        let report=try await requireReport(plan),output=try XCTUnwrap(report.results.first?.outputs.first)
        let ordinary=try RecoveryJournal(root:recoveryRoot,batchID:plan.id),record=try XCTUnwrap(ordinary.records().first),injected=RecoveryEditInjector()
        let newer=Data("Newer external edit must remain at its current path".utf8)
        let journal=try RecoveryJournal(root:recoveryRoot,batchID:plan.id,checkpoint:{point in
            if point == .beforeJournalSync,injected.claim() {try newer.write(to:output,options:.atomic)}
        })
        let result=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restoreGroup(record,journal:journal)
        XCTAssertFalse(result.isComplete);XCTAssertFalse(result.conflicts.isEmpty)
        XCTAssertEqual(try? Data(contentsOf:output),newer)
        XCTAssertFalse(try XCTUnwrap(ordinary.record(groupID:record.groupID)).members.contains(where:\.restored))
        let repeatResult=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertFalse(repeatResult.isComplete);XCTAssertEqual(try? Data(contentsOf:output),newer)
    }
}
private final class RecoveryEditInjector:@unchecked Sendable {
    private let lock=NSLock();private var used=false
    func claim()->Bool {lock.lock();defer {lock.unlock()};if used {return false};used=true;return true}
}
