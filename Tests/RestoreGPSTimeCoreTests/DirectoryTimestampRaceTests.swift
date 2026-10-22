import XCTest
import Darwin
@testable import RestoreGPSTimeCore
final class DirectoryTimestampRaceTests:TransactionTestCase {
    private func setBirth(_ url:URL,nanos:Int) throws {
        var state=stat();guard lstat(url.path,&state)==0 else {throw SecureFS.error("Read fixture folder times")}
        var list=attrlist();list.bitmapcount=UInt16(ATTR_BIT_MAP_COUNT);list.commonattr=attrgroup_t(ATTR_CMN_CRTIME|ATTR_CMN_MODTIME)
        var times=[timespec(tv_sec:1_577_836_800,tv_nsec:nanos),state.st_mtimespec]
        let fd=open(url.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);guard fd>=0 else {throw SecureFS.error("Open fixture folder")};defer {close(fd)}
        guard times.withUnsafeMutableBytes({fsetattrlist(fd,&list,$0.baseAddress,$0.count,0)})==0 else {throw SecureFS.error("Set fixture folder birth time")}
    }
    func testUnselectedFolderBirthNanosecondEditIsNotPromotedAsOwnChange() async throws {
        let child=try item("folder/child.HEIC"),folder=child.snapshot.url.deletingLastPathComponent()
        try setBirth(folder,nanos:123_456_780)
        let snapshot=try FileIdentityReader().snapshot(at:folder),input=InspectedItem(snapshot:snapshot,metadata:.init(tags:[:])),plan=try await transactionPlan([child,input]),faults=TransactionFaults()
        var changed=false
        faults.callback={point in if point == .afterMember(0),!changed {changed=true;try self.setBirth(folder,nanos:123_456_781)}}
        let report=try await requireReport(plan,faults:faults)
        XCTAssertTrue(changed);XCTAssertFalse(report.success)
        let after=try FileIdentityReader().snapshot(at:folder)
        XCTAssertEqual(after.creationDate,snapshot.creationDate,"The edit is below the precision of the display Date.")
        XCTAssertEqual(after.creationTimestamp?.nanoseconds,123_456_781,"Do not restore or normalize an unselected externally edited birth time.")
        let recovery=try await RecoveryCoordinator(root:recoveryRoot,driver:TransactionTestDriver()).restore(batchID:plan.id,choice:.originalLocations)
        XCTAssertFalse(recovery.isComplete);XCTAssertEqual(try FileIdentityReader().snapshot(at:folder).creationTimestamp?.nanoseconds,123_456_781)
    }
}
