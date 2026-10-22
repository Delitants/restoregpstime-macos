import Foundation
import CoreFoundation
import AppKit

// Fixed domain/key only. Tests inject an isolated backend and never invoke these writes.
public struct SystemFinderVisibilityBackend:FinderVisibilityBackend {
    private var domain:CFString {"com.apple.finder" as CFString}
    private var key:CFString {"AppleShowAllFiles" as CFString}
    public init() {}
    public func read() throws -> FinderPreferenceValue {
        guard CFPreferencesAppSynchronize(domain) else {throw RestoreError(.io,"Cannot refresh the Finder preference domain.")}
        guard let value=CFPreferencesCopyAppValue(key,domain) else {return .absent}
        if CFGetTypeID(value)==CFBooleanGetTypeID() {return .bool((value as! NSNumber).boolValue)}
        if let string=value as? String {return .string(string)}
        if let number=value as? NSNumber,!String(cString:number.objCType).contains("d"),!String(cString:number.objCType).contains("f"),let integer=Int(number.stringValue) {return .integer(integer)}
        throw RestoreError(.unsupported,"Finder visibility has an unsupported preference value type.")
    }
    public func write(_ value:FinderPreferenceValue) throws {
        let object:CFPropertyList?
        switch value {case .absent:object=nil;case .bool(let flag):object=flag ? kCFBooleanTrue:kCFBooleanFalse;case .string(let text):object=text as CFString;case .integer(let number):object=NSNumber(value:number)}
        CFPreferencesSetAppValue(key,object,domain)
        guard CFPreferencesAppSynchronize(domain) else {throw RestoreError(.io,"Cannot synchronize the selected Finder preference.")}
    }
    public func restart() async -> Bool {await restartFinder()}
    @MainActor private func restartFinder() async -> Bool {
        let existing=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.finder")
        for app in existing where !app.isTerminated {if !app.terminate() {return false}}
        for _ in 0..<50 {
            if existing.allSatisfy(\.isTerminated) {break}
            do {try await Task.sleep(nanoseconds:100_000_000)} catch {return false}
        }
        guard existing.allSatisfy(\.isTerminated) else {return false}
        let configuration=NSWorkspace.OpenConfiguration();configuration.activates=false
        do {_ = try await NSWorkspace.shared.openApplication(at:URL(fileURLWithPath:"/System/Library/CoreServices/Finder.app"),configuration:configuration);return true} catch {return false}
    }
}
