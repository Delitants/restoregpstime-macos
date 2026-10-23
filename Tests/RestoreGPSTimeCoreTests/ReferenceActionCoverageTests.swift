import XCTest

final class ReferenceActionCoverageTests:CoreTestCase {
    func testActionMatrixHas31OwnedChecks() throws {
        let rows=try matrix("reference-actions.csv")
        XCTAssertEqual(rows.count,31)
        XCTAssertEqual(Set(rows.map {$0[0]}),Set((1...31).map {String(format:"A%02d",$0)}))
        try validateOwners(rows)
    }
    func testTwoToolsHaveIsolatedOwnedChecks() throws {
        let rows=try matrix("reference-tools.csv")
        XCTAssertEqual(Set(rows.map {$0[0]}),["X01","X02"])
        try validateOwners(rows)
    }
    private func matrix(_ name:String) throws -> [[String]] {
        let inventory=repository.appendingPathComponent("docs/acceptance/"+name)
        guard FileManager.default.fileExists(atPath:inventory.path) else {
            throw XCTSkip("Local reference inventory is not present.")
        }
        let text=try String(contentsOf:inventory,encoding:.utf8)
        // The first four inventory columns contain no quoted commas; later prose may.
        return try text.split(whereSeparator:\.isNewline).dropFirst().map {line in
            let columns=line.split(separator:",",maxSplits:4,omittingEmptySubsequences:false).map(String.init)
            guard columns.count==5 else {throw NSError(domain:"InvalidAcceptanceRow",code:1)}
            return Array(columns.prefix(4))
        }
    }
    private func validateOwners(_ rows:[[String]]) throws {
        for row in rows {
            XCTAssertFalse(row[3].isEmpty,"\(row[0]) has no owned check")
            for method in row[3].split(separator:";").map(String.init) {
                let parts=method.split(separator:".").map(String.init)
                guard parts.count==2 else {XCTFail("Invalid owned check for \(row[0]): \(method)");continue}
                let file=repository.appendingPathComponent("Tests/RestoreGPSTimeCoreTests/"+parts[0]+".swift")
                guard FileManager.default.fileExists(atPath:file.path) else {XCTFail("Missing test file for \(row[0]): \(method)");continue}
                let source=try String(contentsOf:file,encoding:.utf8)
                XCTAssertTrue(source.contains("func "+parts[1]+"("),"\(row[0]) points to a nonexistent check: \(method)")
            }
        }
    }
}
