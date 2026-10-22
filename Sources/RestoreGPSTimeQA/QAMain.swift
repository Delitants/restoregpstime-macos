import Foundation
import Darwin
@main struct QAMain {
    static func main() async {
        do {
            let args=Array(CommandLine.arguments.dropFirst());var values=[String:String](),i=0
            while i<args.count {guard ["--app","--fixture-manifest","--evidence-dir","--host-label"].contains(args[i]),i+1<args.count,values[args[i]]==nil else {throw QAUsage()};values[args[i]]=args[i+1];i+=2}
            guard let app=values["--app"],let fixtures=values["--fixture-manifest"],let output=values["--evidence-dir"] else {throw QAUsage()}
            if let label=values["--host-label"] {setenv("RESTOREGPSTIME_QA_HOST_LABEL",label,1)}
            let result=try await QualificationRunner().run(appURL:URL(fileURLWithPath:app),fixtureManifest:URL(fileURLWithPath:fixtures),output:URL(fileURLWithPath:output))
            for gate in result.gates {print("\(gate.status.rawValue): \(gate.id) — \(gate.detail)")}
            exit(result.stableReady ? 0:2)
        } catch {fputs("Qualification stopped: \(error)\nUsage: RestoreGPSTimeQA --app PATH --fixture-manifest PATH --evidence-dir FRESH_PATH --host-label LABEL\n",stderr);exit(1)}
    }
}
private struct QAUsage:Error {}
