import XCTest
import Darwin
@testable import RestoreGPSTimeCore

final class CompactBackupTests:TransactionTestCase {
    private func compactPlan(_ items:[InspectedItem],mode:BackupMode = .metadata,rename:Bool=false) async throws -> BatchPlan {
        var request=OperationRequest();var dates=DatePolicy();dates.source = .specific(try utc("2020-02-03T04:05:06Z"));dates.targets = .modification;request.dates=dates
        if rename {request.rename=NameTemplate()}
        var settings=try options(mode:.modifyInPlace);settings.recoveryRoot=recoveryRoot;settings.backupMode=mode
        return try await planner().preview(items:items,request:request,options:settings)
    }
    func testLegacyPolicyDefaultsFull() throws {
        XCTAssertEqual(try JSONDecoder().decode(BatchOptions.self,from:JSONEncoder().encode(BatchOptions())).effectiveBackupMode,.full)
    }
    func testCompactRenameRestoresExactBytesAttributesAndRemovesHeldMedia() async throws {
        let input=try item("compact/a.HEIC"),before=try FileIdentityReader().fingerprint(at:input.snapshot.url),plan=try await compactPlan([input],rename:true)
        let report=try await requireReport(plan);XCTAssertTrue(report.success)
        let record=try XCTUnwrap(RecoveryJournal(root:recoveryRoot,batchID:plan.id).records().first)
        XCTAssertNil(record.members[0].backupURL)
        for member in record.members {for url in [member.stageURL,member.heldOriginalURL].compactMap({$0}) {XCTAssertFalse(SecureFS.exists(url))}}
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(outcome.isComplete,"\(outcome.conflicts)")
        let after=try FileIdentityReader().fingerprint(at:input.snapshot.url)
        XCTAssertEqual(before.contentHash,after.contentHash);XCTAssertTrue(SecureFS.attributesEqual(before.snapshot,after.snapshot))
        let restored=try XCTUnwrap(RecoveryJournal(root:recoveryRoot,batchID:plan.id).records().first)
        for member in restored.members {for url in [member.restoreStageURL,member.recoveryRetiredURL,member.backupURL].compactMap({$0}) {XCTAssertFalse(SecureFS.exists(url))}}
    }
    func testCompactNewerOutputRefused() async throws {
        let input=try item("tamper/a.HEIC"),plan=try await compactPlan([input]);let report=try await requireReport(plan);XCTAssertTrue(report.success)
        try Data("newer edit".utf8).write(to:input.snapshot.url)
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertFalse(outcome.isComplete);XCTAssertEqual(try Data(contentsOf:input.snapshot.url),Data("newer edit".utf8))
    }
    func testNoneDisallowsCompletedUndo() async throws {
        let input=try item("none/a.HEIC"),plan=try await compactPlan([input],mode:.none);let report=try await requireReport(plan);XCTAssertTrue(report.success)
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertFalse(outcome.isComplete);XCTAssertTrue(outcome.conflicts.joined().contains("No backup"))
    }
    func testSelectedFileLeavesIndependentOutputUnchanged() async throws {
        let a=try item("selection/a.HEIC"),b=try item("selection/b.HEIC"),plan=try await compactPlan([a,b]);let report=try await requireReport(plan);XCTAssertTrue(report.success)
        let bAfter=try FileIdentityReader().fingerprint(at:b.snapshot.url)
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations,selectedSourceKeys:[a.snapshot.id.physicalKey])
        XCTAssertTrue(outcome.isComplete,"\(outcome.conflicts)");XCTAssertEqual(outcome.restored.count,1);XCTAssertEqual(bAfter,try FileIdentityReader().fingerprint(at:b.snapshot.url))
    }
    func testReverseDeltaRecoversShiftedPayloadAndRejectsOversize() throws {
        let original=workspace.appendingPathComponent("original"),output=workspace.appendingPathComponent("output"),restored=workspace.appendingPathComponent("restored")
        let bytes=Data((0..<1_000_000).map {UInt8(truncatingIfNeeded:($0 &* 7919) ^ ($0 >> 7))})
        try bytes.write(to:original);try (Data("rewritten-header".utf8)+bytes.dropFirst(40)).write(to:output)
        let delta=try ReverseDelta.capture(original:original,output:output)
        XCTAssertLessThan(delta.literalBytes,150_000)
        try delta.restore(output:output,to:restored);XCTAssertEqual(try Data(contentsOf:restored),bytes)
        try Data(repeating:7,count:bytes.count).write(to:output)
        XCTAssertThrowsError(try ReverseDelta.capture(original:original,output:output))
    }
    func testSmallGeneratedJPEGEmbeddedRewriteRestoresExactOriginal() async throws {
        let url=workspace.appendingPathComponent("generated.jpg");try FileManager.default.copyItem(at:fixture("paris.jpg"),to:url)
        let paths=try RuntimeLocator().locate(in:testApp),snapshot=try FileIdentityReader().snapshot(at:url)
        let input=InspectedItem(snapshot:snapshot,metadata:try await MetadataReader(paths:paths).read(snapshot:snapshot))
        let before=try FileIdentityReader().fingerprint(at:url)
        var request=OperationRequest();request.tags=[.set(TagID(rawValue:"XMP-dc:Description-x-default")!,.string("Compact exact undo"))]
        var settings=try options(mode:.modifyInPlace);settings.recoveryRoot=recoveryRoot;settings.backupMode = .metadata
        let plan=try await planner().preview(items:[input],request:request,options:settings)
        let expected=self.identity,driver=MetadataMutationDriver(paths:paths),executor=BatchExecutor(driver:driver,validator:.init(dependencies:{expected}))
        var result:BatchReport?
        for await event in executor.execute(plan) {if case .finished(let report)=event {result=report}}
        XCTAssertTrue(try XCTUnwrap(result).success,"\(result!.results)")
        guard result?.success==true else {return}
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(outcome.isComplete,"\(outcome.conflicts)")
        let actual=try FileIdentityReader().fingerprint(at:url)
        XCTAssertEqual(actual.contentHash,before.contentHash);XCTAssertTrue(SecureFS.attributesEqual(actual.snapshot,before.snapshot))
    }
    func testRawXattrsPermissionsACLAndNanosecondDatesRestore() async throws {
        let base=try item("attributes/a.HEIC"),url=base.snapshot.url,data=Data([0,255,13,0,128])
        XCTAssertEqual(data.withUnsafeBytes {setxattr(url.path,"org.restoregpstime.test",$0.baseAddress,data.count,0,0)},0)
        XCTAssertEqual(chmod(url.path,0o640),0)
        let chmodACL=Process();chmodACL.executableURL=URL(fileURLWithPath:"/bin/chmod")
        chmodACL.arguments=["+a",NSUserName()+" allow read,write",url.path]
        try chmodACL.run();chmodACL.waitUntilExit();XCTAssertEqual(chmodACL.terminationStatus,0)
        let input=InspectedItem(snapshot:try FileIdentityReader().snapshot(at:url),metadata:base.metadata,place:base.place)
        XCTAssertNotNil(input.snapshot.aclText)
        let before=try FileIdentityReader().fingerprint(at:url),plan=try await compactPlan([input])
        let report=try await requireReport(plan);XCTAssertTrue(report.success,"\(report.results)")
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(outcome.isComplete,"\(outcome.conflicts)")
        let after=try FileIdentityReader().fingerprint(at:url)
        XCTAssertTrue(SecureFS.attributesEqual(before.snapshot,after.snapshot))
    }
    func testCompactAndNoneRecoverInterruptedCommit() async throws {
        for mode in [BackupMode.metadata,.none] {
            for rename in [false,true] {
                let input=try item("crash-\(mode)-\(rename)/a.HEIC"),before=try FileIdentityReader().fingerprint(at:input.snapshot.url),plan=try await compactPlan([input],mode:mode,rename:rename)
                let report=try await requireReport(plan,faults:TransactionFaults(.persistedStep(rename ? .retired:.swapped,index:0),crash:true))
                XCTAssertFalse(report.success)
                let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
                XCTAssertTrue(outcome.isComplete,"\(mode)/\(rename): \(outcome.conflicts)")
                let after=try FileIdentityReader().fingerprint(at:input.snapshot.url)
                XCTAssertEqual(after.contentHash,before.contentHash);XCTAssertTrue(SecureFS.attributesEqual(after.snapshot,before.snapshot))
            }
        }
    }
    func testLinkedSelectionRestoresEverySibling() async throws {
        let a=try item("linked/A.HEIC",id:"pair"),b=try item("linked/A.MOV",family:.video,id:"pair"),plan=try await compactPlan([a,b])
        XCTAssertEqual(plan.eligibleGroups.count,1)
        let report=try await requireReport(plan);XCTAssertTrue(report.success)
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations,selectedSourceKeys:[a.snapshot.id.physicalKey])
        XCTAssertTrue(outcome.isComplete,"\(outcome.conflicts)");XCTAssertEqual(outcome.restored.count,2)
    }
    func testCompactDatabaseTamperingRefusesAllWrites() async throws {
        let input=try item("database-tamper/a.HEIC"),plan=try await compactPlan([input])
        let report=try await requireReport(plan);XCTAssertTrue(report.success)
        let after=try FileIdentityReader().fingerprint(at:input.snapshot.url),journal=try RecoveryJournal(root:recoveryRoot,batchID:plan.id)
        try Data(repeating:0,count:8192).write(to:journal.batchDirectory.appendingPathComponent("compact.sqlite"))
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertFalse(outcome.isComplete);XCTAssertEqual(after,try FileIdentityReader().fingerprint(at:input.snapshot.url))
    }
    func testCrashAfterCleanupDeletionStillRestoresFromDatabase() async throws {
        let input=try item("cleanup-crash/a.HEIC"),plan=try await compactPlan([input]),faults=TransactionFaults()
        let journal=try RecoveryJournal(root:recoveryRoot,batchID:plan.id)
        faults.callback={point in
            if point == .beforeJournalSync,let record=try journal.records().first,record.compactCleanup==false,let stage=record.members.first?.stageURL,!SecureFS.exists(stage) {throw SimulatedInterruption()}
        }
        let report=try await requireReport(plan,faults:faults);XCTAssertFalse(report.success)
        XCTAssertEqual(try journal.records().first?.compactCleanup,false)
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(outcome.isComplete,"\(outcome.conflicts)")
    }

    func testMetadataRecoversAtEveryTransactionPhase() async throws {
        for phase in [RecoveryPhase.prepared,.backedUp,.staged,.verified,.committing,.committed] {
            let input=try item("phase-\(phase)/a.HEIC"),before=try FileIdentityReader().fingerprint(at:input.snapshot.url),plan=try await compactPlan([input])
            let report=try await requireReport(plan,faults:TransactionFaults(.persisted(phase),crash:true));XCTAssertFalse(report.success)
            let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
            XCTAssertTrue(outcome.isComplete,"\(phase): \(outcome.conflicts)")
            let after=try FileIdentityReader().fingerprint(at:input.snapshot.url)
            XCTAssertEqual(after.contentHash,before.contentHash);XCTAssertTrue(SecureFS.attributesEqual(after.snapshot,before.snapshot))
        }
    }
    func testSeparateCompactRestorePreservesOutputAndAllowsLaterUndo() async throws {
        let input=try item("separate/a.HEIC"),before=try FileIdentityReader().fingerprint(at:input.snapshot.url),plan=try await compactPlan([input])
        let report=try await requireReport(plan);XCTAssertTrue(report.success)
        let after=try FileIdentityReader().fingerprint(at:input.snapshot.url),output=workspace.appendingPathComponent("separate-output")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let coordinator=RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver())
        let outcome=try await coordinator.restore(batchID:plan.id,choice:.separateFolder(output))
        XCTAssertTrue(outcome.isComplete,"\(outcome.conflicts)");XCTAssertEqual(outcome.restored.count,1)
        if let restored=outcome.restored.first {XCTAssertEqual(try FileIdentityReader().fingerprint(at:restored).contentHash,before.contentHash)}
        XCTAssertEqual(after,try FileIdentityReader().fingerprint(at:input.snapshot.url))
        let undo=try await coordinator.restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(undo.isComplete,"\(undo.conflicts)")
    }

    func testMetadataDirectoryAndChildUndoRestoresFinalLocks() async throws {
        let child=try item("directory/child.HEIC"),folder=child.snapshot.url.deletingLastPathComponent()
        let directory=InspectedItem(snapshot:try FileIdentityReader().snapshot(at:folder),metadata:.init(tags:[:]))
        let before=try FileIdentityReader().snapshot(at:folder)
        var request=OperationRequest();request.finder=[.locked(true)]
        var dates=DatePolicy();dates.source = .specific(try utc("2020-02-03T04:05:06Z"));dates.targets = .modification;request.dates=dates
        var settings=try options(mode:.modifyInPlace);settings.recoveryRoot=recoveryRoot;settings.importRoots=[folder];settings.backupMode = .metadata
        let plan=try await planner().preview(items:[directory,child],request:request,options:settings),expected=self.identity
        let driver=AttributeMutationDriver(paths:RuntimePaths(appBundle:testApp)),executor=BatchExecutor(driver:driver,validator:.init(dependencies:{expected}))
        defer {_ = chflags(folder.path,0);_ = chflags(child.snapshot.url.path,0)}
        var result:BatchReport?
        for await event in executor.execute(plan) {if case .finished(let report)=event {result=report}}
        XCTAssertTrue(try XCTUnwrap(result).success,"\(result!.results)")
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertTrue(outcome.isComplete,"\(outcome.conflicts)");XCTAssertTrue(SecureFS.attributesEqual(try FileIdentityReader().snapshot(at:folder),before))
    }

    func testNoBackupCompletedDirectoryRefusalDoesNotUnlockAnything() async throws {
        let child=try item("no-backup-directory/child.HEIC"),folder=child.snapshot.url.deletingLastPathComponent()
        let directory=InspectedItem(snapshot:try FileIdentityReader().snapshot(at:folder),metadata:.init(tags:[:]))
        var request=OperationRequest();request.finder=[.locked(true)]
        var settings=try options(mode:.modifyInPlace);settings.recoveryRoot=recoveryRoot;settings.importRoots=[folder];settings.backupMode = BackupMode.none
        let plan=try await planner().preview(items:[directory,child],request:request,options:settings),expected=self.identity
        let driver=AttributeMutationDriver(paths:RuntimePaths(appBundle:testApp)),executor=BatchExecutor(driver:driver,validator:.init(dependencies:{expected}))
        defer {_ = chflags(folder.path,0);_ = chflags(child.snapshot.url.path,0)}
        var result:BatchReport?
        for await event in executor.execute(plan) {if case .finished(let report)=event {result=report}}
        XCTAssertTrue(try XCTUnwrap(result).success,"\(result!.results)")
        let before=try FileIdentityReader().fingerprint(at:folder)
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertFalse(outcome.isComplete);XCTAssertEqual(before,try FileIdentityReader().fingerprint(at:folder))
    }

    func testAttributeOnlyLargeFileDatabaseContainsZeroMediaFragments() async throws {
        let base=try item("large/a.HEIC"),url=base.snapshot.url
        try Data(repeating:0xa5,count:2*1024*1024).write(to:url)
        let input=InspectedItem(snapshot:try FileIdentityReader().snapshot(at:url),metadata:base.metadata,place:base.place),plan=try await compactPlan([input])
        let report=try await requireReport(plan);XCTAssertTrue(report.success)
        let journal=try RecoveryJournal(root:recoveryRoot,batchID:plan.id),record=try XCTUnwrap(journal.records().first)
        let payload=try CompactBackupStore(journal:journal).payload(record.members[0],record:record)
        XCTAssertEqual(payload.delta?.literalBytes,0)
        let database=try FileIdentityReader().snapshot(at:journal.batchDirectory.appendingPathComponent("compact.sqlite"))
        XCTAssertLessThan(database.id.size,65536)
    }

    func testMissingOutputExplainsCompactPayloadDependency() async throws {
        let input=try item("missing/a.HEIC"),plan=try await compactPlan([input])
        let report=try await requireReport(plan);XCTAssertTrue(report.success)
        let removed=input.snapshot.url.deletingLastPathComponent().appendingPathComponent("removed-media")
        try FileManager.default.moveItem(at:input.snapshot.url,to:removed)
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertFalse(outcome.isComplete);XCTAssertTrue(outcome.conflicts.joined().contains("Compact undo"))
        XCTAssertFalse(SecureFS.exists(input.snapshot.url));XCTAssertTrue(SecureFS.exists(removed))
    }

    func testCommittedJournalAlreadyContainsDurableCleanupIntent() async throws {
        for mode in [BackupMode.metadata,.none] {
            let input=try item("intent-\(mode)/a.HEIC"),plan=try await compactPlan([input],mode:mode)
            let report=try await requireReport(plan,faults:TransactionFaults(.persisted(.committed),crash:true));XCTAssertFalse(report.success)
            let record=try XCTUnwrap(RecoveryJournal(root:recoveryRoot,batchID:plan.id).records().first)
            XCTAssertEqual(record.compactCleanup,false)
        }
    }

    private func lockedParentFixture(_ prefix:String,locked:Bool=true) async throws -> (URL,InspectedItem,InspectedItem,BatchPlan,AttributeMutationDriver) {
        let child=try item("\(prefix)/child.HEIC"),sibling=try item("\(prefix)/sibling.HEIC"),folder=child.snapshot.url.deletingLastPathComponent()
        let directory=InspectedItem(snapshot:try FileIdentityReader().snapshot(at:folder),metadata:.init(tags:[:]))
        var request=OperationRequest();if locked {request.finder=[.locked(true)]}
        var dates=DatePolicy();dates.source = .specific(try utc("2020-02-03T04:05:06Z"));dates.targets = .modification;request.dates=dates
        var settings=try options(mode:.modifyInPlace);settings.recoveryRoot=recoveryRoot;settings.importRoots=[folder];settings.backupMode = .metadata
        let plan=try await planner().preview(items:[directory,child,sibling],request:request,options:settings),expected=self.identity
        let driver=AttributeMutationDriver(paths:RuntimePaths(appBundle:testApp)),executor=BatchExecutor(driver:driver,validator:.init(dependencies:{expected}))
        var result:BatchReport?
        for await event in executor.execute(plan) {if case .finished(let report)=event {result=report}}
        XCTAssertTrue(try XCTUnwrap(result).success,"\(result!.results)")
        return (folder,child,sibling,plan,driver)
    }
    func testSelectedChildUndoCoordinatesUnselectedLockedParentOnly() async throws {
        let (folder,child,sibling,plan,driver)=try await lockedParentFixture("selected-child")
        defer {_ = chflags(folder.path,0);_ = chflags(child.snapshot.url.path,0);_ = chflags(sibling.snapshot.url.path,0)}
        let parentAfter=try FileIdentityReader().snapshot(at:folder),siblingAfter=try FileIdentityReader().fingerprint(at:sibling.snapshot.url)
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations,selectedSourceKeys:[child.snapshot.id.physicalKey])
        XCTAssertTrue(outcome.isComplete,"\(outcome.conflicts)");XCTAssertEqual(outcome.restored.count,1)
        XCTAssertTrue(SecureFS.attributesEqual(try FileIdentityReader().snapshot(at:folder),parentAfter))
        XCTAssertEqual(try FileIdentityReader().fingerprint(at:sibling.snapshot.url),siblingAfter)
        XCTAssertTrue(SecureFS.attributesEqual(try FileIdentityReader().snapshot(at:child.snapshot.url),child.snapshot))
        let parentRecord=try XCTUnwrap(RecoveryJournal(root:recoveryRoot,batchID:plan.id).records().first {$0.members.first?.item.source.snapshot.kind == .directory})
        XCTAssertFalse(parentRecord.members[0].restored)
    }
    func testSelectedChildConflictRelocksUnselectedAncestor() async throws {
        let (folder,child,sibling,plan,driver)=try await lockedParentFixture("selected-conflict")
        defer {_ = chflags(folder.path,0);_ = chflags(child.snapshot.url.path,0);_ = chflags(sibling.snapshot.url.path,0)}
        let parentAfter=try FileIdentityReader().snapshot(at:folder)
        XCTAssertEqual(chflags(child.snapshot.url.path,0),0)
        let changed=try FileIdentityReader().fingerprint(at:child.snapshot.url)
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations,selectedSourceKeys:[child.snapshot.id.physicalKey])
        XCTAssertFalse(outcome.isComplete)
        XCTAssertTrue(SecureFS.attributesEqual(try FileIdentityReader().snapshot(at:folder),parentAfter))
        XCTAssertEqual(try FileIdentityReader().fingerprint(at:child.snapshot.url),changed)
    }

    func testSelectedChildKeepsUnselectedUnlockedParentRecoverable() async throws {
        let (folder,child,_,plan,driver)=try await lockedParentFixture("selected-unlocked",locked:false)
        let parentAfter=try FileIdentityReader().snapshot(at:folder)
        let coordinator=RecoveryCoordinator(root:recoveryRoot,driver:driver)
        let childUndo=try await coordinator.restore(batchID:plan.id,choice:.originalLocations,selectedSourceKeys:[child.snapshot.id.physicalKey])
        XCTAssertTrue(childUndo.isComplete,"\(childUndo.conflicts)")
        XCTAssertTrue(SecureFS.attributesEqual(try FileIdentityReader().snapshot(at:folder),parentAfter))
        let parent=try XCTUnwrap(plan.groups.flatMap(\.items).first {$0.source.snapshot.kind == .directory})
        let parentUndo=try await coordinator.restore(batchID:plan.id,choice:.originalLocations,selectedSourceKeys:[parent.name.sourceKey])
        XCTAssertTrue(parentUndo.isComplete,"\(parentUndo.conflicts)")
    }
    func testSelectedChildResumesPersistedAncestorUnlockIntent() async throws {
        let (folder,child,sibling,plan,driver)=try await lockedParentFixture("selected-resume")
        defer {_ = chflags(folder.path,0);_ = chflags(child.snapshot.url.path,0);_ = chflags(sibling.snapshot.url.path,0)}
        let journal=try RecoveryJournal(root:recoveryRoot,batchID:plan.id)
        var record=try XCTUnwrap(journal.records().first {$0.members.first?.item.source.snapshot.kind == .directory})
        let before=try FileIdentityReader().fingerprint(at:folder)
        record.members[0].directoryCoordination=before;try journal.persist(record)
        XCTAssertEqual(chflags(folder.path,before.snapshot.flags & ~UInt32(UF_IMMUTABLE)),0)
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:driver).restore(batchID:plan.id,choice:.originalLocations,selectedSourceKeys:[child.snapshot.id.physicalKey])
        XCTAssertTrue(outcome.isComplete,"\(outcome.conflicts)")
        XCTAssertTrue(SecureFS.attributesEqual(try FileIdentityReader().snapshot(at:folder),before.snapshot))
        XCTAssertNil(try journal.record(groupID:record.groupID)?.members[0].directoryCoordination)
    }
    func testSelectedChildRacePreservesNewAncestorAttributesAndRelocks() async throws {
        let (folder,child,sibling,plan,driver)=try await lockedParentFixture("selected-race")
        defer {_ = chflags(folder.path,0);_ = chflags(child.snapshot.url.path,0);_ = chflags(sibling.snapshot.url.path,0)}
        let value=Data("new external attribute".utf8),faults=TransactionFaults()
        faults.callback={point in if case .afterMember=point {
            guard value.withUnsafeBytes({setxattr(folder.path,"org.restoregpstime.concurrent",$0.baseAddress,value.count,0,0)})==0 else {throw SecureFS.error("Fixture concurrent ancestor attribute")}
            throw RestoreError(.io,"Fixture conflict after output exchange")
        }}
        let outcome=try await RecoveryCoordinator(root:recoveryRoot,driver:driver,options:.init(checkpoint:faults.check)).restore(batchID:plan.id,choice:.originalLocations,selectedSourceKeys:[child.snapshot.id.physicalKey])
        XCTAssertFalse(outcome.isComplete)
        let parent=try FileIdentityReader().snapshot(at:folder)
        XCTAssertTrue(parent.isLocked);XCTAssertNotNil(parent.xattrHashes["org.restoregpstime.concurrent"])
    }

}
