import XCTest
import Darwin
@testable import RestoreGPSTime
@testable import RestoreGPSTimeCore

final class BatchHelperFaultTests:AppTestCase {
    private var repo:URL {URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func inputs() throws -> [URL] {
        try ["one.jpg","two.jpg"].map {name in
            let url=workspace.appendingPathComponent(name)
            try FileManager.default.copyItem(at:repo.appendingPathComponent("Tests/Fixtures/paris.jpg"),to:url)
            return url
        }
    }
    private func faultRuntime(records:Data,mode:String) throws -> RuntimePaths {
        let original=ProcessInfo.processInfo.environment["RESTOREGPSTIME_TEST_APP_BUNDLE"].map {URL(fileURLWithPath:$0)} ?? URL(fileURLWithPath:"/Applications/RestoreGPSTime.app")
        let app=workspace.appendingPathComponent("Fault Runtime.app")
        try FileManager.default.copyItem(at:original,to:app)
        let paths=RuntimePaths(appBundle:app),folder=paths.perl.deletingLastPathComponent()
        try FileManager.default.moveItem(at:paths.perl,to:folder.appendingPathComponent("perl-real"))
        try records.write(to:folder.appendingPathComponent("fault.json"))
        let script="""
        #!/bin/sh
        folder=$(dirname "$0")
        if [ -e "$folder/slow" ]; then
          echo $$ > "$folder/child-$$.pid"
          exec /bin/sleep 20
        fi
        count=0; after=0
        for arg do
          if [ "$after" = 1 ]; then count=$((count+1)); fi
          if [ "$arg" = '--' ]; then after=1; fi
        done
        if [ "$count" -gt 1 ]; then
          /bin/cat "$folder/fault.json"
          echo 'Injected batch helper failure' >&2
          exit \(mode == "nonzero" ? "1":"0")
        fi
        exec "$folder/perl-real" "$@"
        """
        try Data(script.utf8).write(to:paths.perl)
        try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:paths.perl.path)
        return paths
    }
    func testMismatchedBatchFallsBackWithoutAssigningWrongMetadata() async throws {
        let urls=try inputs(),paths=try faultRuntime(records:Data("[]".utf8),mode:"malformed")
        let result=try await LiveAppBackend(paths:paths).inspectDetailed(urls,options:DiscoveryOptions(),progress:{_ in})
        XCTAssertEqual(result.items.count,2)
        for item in result.items {
            XCTAssertEqual(item.metadata.profile.identifier,"JPEG")
            XCTAssertEqual(item.metadata.tags["SourceFile"]?.text,item.snapshot.url.path)
            XCTAssertTrue(item.metadata.diagnostics.isEmpty)
        }
    }
    func testNonzeroBatchWithOnlyAWarningIsNotTreatedAsSuccess() async throws {
        let urls=try inputs()
        let records=try JSONSerialization.data(withJSONObject:urls.enumerated().map {index,url in
            ["SourceFile":url.path,"File:FileType":"JPEG","ExifTool:Warning":index==0 ? "Warning alone is not a process error":""]
        })
        let paths=try faultRuntime(records:records,mode:"nonzero"),snapshots=try urls.map {try FileIdentityReader().snapshot(at:$0)}
        do {_ = try await MetadataReader(paths:paths).readBatch(snapshots:snapshots);XCTFail("A warning cannot explain a failed batch process")} catch {}
        let result=try await LiveAppBackend(paths:paths).inspectDetailed(urls,options:DiscoveryOptions(),progress:{_ in})
        XCTAssertTrue(result.items.allSatisfy {$0.metadata.diagnostics.isEmpty})
    }
    func testActiveAndWaitingBatchCancellationTerminatesChildrenAndReleasesPermits() async throws {
        let urls=try inputs(),paths=try faultRuntime(records:Data("[]".utf8),mode:"malformed")
        let marker=paths.perl.deletingLastPathComponent().appendingPathComponent("slow")
        try Data().write(to:marker)
        let reader=MetadataReader(paths:paths),snapshots=try urls.map {try FileIdentityReader().snapshot(at:$0)}
        let tasks=(0..<3).map {_ in Task {try await reader.readBatch(snapshots:snapshots)}}
        var pids=[Int32]()
        for _ in 0..<300 {
            pids=try FileManager.default.contentsOfDirectory(at:marker.deletingLastPathComponent(),includingPropertiesForKeys:nil).filter {$0.lastPathComponent.hasPrefix("child-")}.compactMap {try? String(contentsOf:$0).trimmingCharacters(in:.whitespacesAndNewlines)}.compactMap(Int32.init)
            if pids.count==2 {break};try await Task.sleep(nanoseconds:10_000_000)
        }
        XCTAssertEqual(pids.count,2)
        tasks.forEach {$0.cancel()}
        for task in tasks {do {_ = try await task.value;XCTFail("Cancelled batch returned metadata")} catch {}}
        let metrics=await reader.metrics();XCTAssertEqual(metrics.active,0);XCTAssertEqual(metrics.helperLaunches,2)
        for pid in pids {XCTAssertEqual(kill(pid,0),-1);XCTAssertEqual(errno,ESRCH)}
        try FileManager.default.removeItem(at:marker)
        let subsequent=try await reader.read(snapshot:snapshots[0])
        XCTAssertEqual(subsequent.profile.identifier,"JPEG")
    }
    func testCancelledLiveImportDoesNotLaunchIndividualFallbacks() async throws {
        let urls=try inputs(),paths=try faultRuntime(records:Data("[]".utf8),mode:"malformed")
        let folder=paths.perl.deletingLastPathComponent();try Data().write(to:folder.appendingPathComponent("slow"))
        let backend=LiveAppBackend(paths:paths)
        let task=Task {try await backend.inspectDetailed(urls,options:DiscoveryOptions(),progress:{_ in})}
        var children=[URL]()
        for _ in 0..<300 {
            children=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter {$0.lastPathComponent.hasPrefix("child-")}
            if children.count==1 {break};try await Task.sleep(nanoseconds:10_000_000)
        }
        XCTAssertEqual(children.count,1);task.cancel()
        do {_ = try await task.value;XCTFail("Cancelled import returned files")} catch {}
        let after=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter {$0.lastPathComponent.hasPrefix("child-")}
        XCTAssertEqual(after.count,1)
    }
}
