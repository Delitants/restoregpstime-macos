import Foundation

public struct RuntimeIdentity: Codable, Sendable {
    public let exifToolVersion: String
    public let perlVersion: String
    public let loadedPaths: [String]
    public let architecture: String
    public let sourceHashes: [String:String]
}

public struct RuntimeProbe {
    public init() {}
    public func inspect(paths: RuntimePaths) async throws -> RuntimeIdentity {
        let runner = ProcessRunner()
        let perl = try await runner.run(executable: paths.perl, arguments: paths.perlArguments(program: "print $^V, qq(\\n), join(qq(\\n), @INC)"), environment: paths.environment, timeout: 15)
        let exif = try await runner.run(executable: paths.perl, arguments: paths.exifArguments(["-ver"]), environment: paths.environment, timeout: 15)
        guard perl.exitStatus == 0, exif.exitStatus == 0 else {
            throw RestoreError(.runtimeUnavailable, "Bundled runtime probe failed: \(String(decoding: perl.stderr + exif.stderr, as: UTF8.self))")
        }
        let lines = perl.text.split(separator: "\n").map(String.init)
        let handle=try FileHandle(forReadingFrom:paths.perl)
        let header=try handle.read(upToCount:8) ?? Data();try handle.close()
        guard header.count==8 else { throw RestoreError(.runtimeUnavailable,"Invalid bundled interpreter header.") }
        let cpu=header[4..<8].enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << UInt32(8*$1.offset)) }
        let architecture=cpu==0x0100000c ? "arm64" : (cpu==0x01000007 ? "x86_64":"unknown")
        let receiptURL=paths.appBundle.appendingPathComponent("Contents/Resources/runtime-identity.json")
        let receipt=try JSONDecoder().decode(Receipt.self,from:Data(contentsOf:receiptURL))
        let hashes=Dictionary(uniqueKeysWithValues:receipt.dependencyLock.dependencies.map {($0.name,$0.sha256)})
        return RuntimeIdentity(exifToolVersion: exif.text.trimmingCharacters(in: .whitespacesAndNewlines), perlVersion: (lines.first ?? "").replacingOccurrences(of: "v", with: ""), loadedPaths: Array(lines.dropFirst()),architecture:architecture,sourceHashes:hashes)
    }
}

private struct Receipt:Decodable { let dependencyLock:Lock }
private struct Lock:Decodable { let dependencies:[Dependency] }
private struct Dependency:Decodable { let name:String;let sha256:String }
