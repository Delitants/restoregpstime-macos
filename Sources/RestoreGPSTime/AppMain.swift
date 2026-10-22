import SwiftUI
import RestoreGPSTimeCore

@main
struct RestoreGPSTimeApp: App {
    @State private var runtimeStatus = "Checking bundled metadata runtime…"
    var body: some Scene {
        WindowGroup("RestoreGPSTime") {
            VStack(spacing: 18) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 48)).foregroundStyle(.blue)
                Text("RestoreGPSTime").font(.largeTitle.bold())
                Text("Photo and video dates. Place names. Your files, restored.").foregroundStyle(.secondary)
                Text(runtimeStatus).font(.callout).textSelection(.enabled)
                Text("Development build • File processing is not available in this foundation build.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 720, minHeight: 420)
            .padding(40)
            .task {
                do {
                    let identity = try await RuntimeProbe().inspect(paths: RuntimeLocator().locate(in: Bundle.main.bundleURL))
                    runtimeStatus = "ExifTool \(identity.exifToolVersion) • Offline place database ready"
                } catch { runtimeStatus = error.localizedDescription }
            }
        }
    }
}
