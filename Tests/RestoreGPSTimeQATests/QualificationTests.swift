import XCTest
@testable import RestoreGPSTimeQA
final class QualificationTests:XCTestCase {
    let arm=QualificationHost(processArchitecture:"arm64",hardwareARM:true,translated:false,osMajor:27,osVersion:"27.0",osBuild:"test")
    func testMissingNativeHostDoesNotPass() {
        XCTAssertTrue(arm.isNative(architecture:"arm64"));XCTAssertFalse(arm.isNative(architecture:"x86_64"));XCTAssertFalse(arm.isNative(architecture:"arm64",osMajor:13))
        let rosetta=QualificationHost(processArchitecture:"x86_64",hardwareARM:true,translated:true,osMajor:13,osVersion:"13.0",osBuild:"test")
        XCTAssertFalse(rosetta.isNative(architecture:"x86_64",osMajor:13))
        let intel=QualificationHost(processArchitecture:"x86_64",hardwareARM:false,translated:false,osMajor:13,osVersion:"13.0",osBuild:"test")
        XCTAssertTrue(intel.isNative(architecture:"x86_64",osMajor:13))
    }
    func testRegressionRequiresCandidateArchitectureAndSourceIdentity() {
        XCTAssertFalse(RegressionBinding.accepts(sourceIdentityPassed:false,candidateArchitecture:"arm64",processArchitecture:"arm64",host:arm))
        XCTAssertFalse(RegressionBinding.accepts(sourceIdentityPassed:true,candidateArchitecture:"x86_64",processArchitecture:"arm64",host:arm))
        XCTAssertTrue(RegressionBinding.accepts(sourceIdentityPassed:true,candidateArchitecture:"arm64",processArchitecture:"arm64",host:arm))
    }
    func testRealFormatMatrixRequiresEvidence() {
        let gates=QualificationResult.requiredGates.map {QualificationGate($0,.pass,"proof")}
        func result(_ gates:[QualificationGate])->QualificationResult {.init(sourceCommit:String(repeating:"a",count:40),appHash:String(repeating:"b",count:64),hostLabel:"local",host:arm,gates:gates)}
        XCTAssertTrue(result(gates).stableReady)
        XCTAssertFalse(result(gates.filter {$0.id != "genuine-formats"}).stableReady)
        XCTAssertFalse(result(gates.map {$0.id=="native-ui" ? QualificationGate($0.id,.missing,"Mac locked"):$0}).stableReady)
        XCTAssertFalse(result(gates+[gates[0]]).stableReady)
        XCTAssertFalse(result(gates.map {$0.id=="runtime" ? QualificationGate($0.id,.fail,"failed"):$0}).stableReady)
    }
}
