import Foundation

public struct RuntimePaths: Sendable {
    public let appBundle: URL
    public var runtimeRoot: URL { appBundle.appendingPathComponent("Contents/Resources/PerlRuntime") }
    public var perl: URL { appBundle.appendingPathComponent("Contents/Helpers/perl") }
    public var nativeModules: URL { appBundle.appendingPathComponent("Contents/PlugIns/PerlModules") }
    public var exifToolRoot: URL { appBundle.appendingPathComponent("Contents/Resources/ExifTool") }
    public var exifTool: URL { exifToolRoot.appendingPathComponent("exiftool") }
    public var database: URL { exifToolRoot.appendingPathComponent("lib/Image/ExifTool/Geolocation.dat") }
    public init(appBundle: URL) { self.appBundle = appBundle }
    public var modulePaths: [String] {
        let root = runtimeRoot.appendingPathComponent("lib/perl5/5.44.0")
        let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return [root.path] + children.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Config.pm").path) }.map(\.path) + [nativeModules.path]
    }
    public var environment: [String:String] { ["PATH":"/usr/bin:/bin", "LC_ALL":"C", "TZ":"UTC"] }
    public func perlArguments(program: String, arguments: [String] = []) -> [String] {
        modulePaths.flatMap { ["-I", $0] } + ["-e", "BEGIN { my $r = shift @ARGV; @INC = grep { index($_, $r . '/') == 0 } @INC; } " + program, appBundle.path] + arguments
    }
    public func exifArguments(_ arguments: [String]) -> [String] {
        perlArguments(program: "$0 = shift @ARGV; do $0; die $@ if $@;", arguments: [exifTool.path, "-config", ""] + arguments)
    }
}

public struct RuntimeLocator {
    public init() {}
    public func locate(in appBundle: URL) throws -> RuntimePaths {
        let paths = RuntimePaths(appBundle: appBundle.standardizedFileURL)
        guard FileManager.default.isExecutableFile(atPath: paths.perl.path),
              FileManager.default.fileExists(atPath: paths.exifTool.path),
              FileManager.default.fileExists(atPath: paths.database.path) else {
            throw RestoreError(.runtimeUnavailable, "The bundled metadata runtime is missing. Reinstall this RestoreGPSTime build.")
        }
        return paths
    }
}
