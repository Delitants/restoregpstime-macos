import Foundation
import RestoreGPSTimeCore

/// Preferences contain reusable settings, never an executable plan or input identities.
struct AppPreferences {
    struct State {let request:OperationRequest,options:BatchOptions,discovery:DiscoveryOptions,appearance:Int}
    private struct Discovery:Codable {
        var recursive:Bool,enumerateRootContents:Bool,includeFiles:Bool,includeFolders:Bool,includeHidden:Bool
        init(_ value:DiscoveryOptions) {recursive=value.recursive;enumerateRootContents=value.enumerateRootContents;includeFiles=value.includeFiles;includeFolders=value.includeFolders;includeHidden=value.includeHidden}
        var value:DiscoveryOptions {var value=DiscoveryOptions();value.recursive=recursive;value.enumerateRootContents=enumerateRootContents;value.includeFiles=includeFiles;value.includeFolders=includeFolders;value.includeHidden=includeHidden;return value}
    }
    private struct Saved:Codable {let schema:Int,request:OperationRequest,options:BatchOptions,discovery:Discovery,appearance:Int}
    let defaults:UserDefaults
    init(defaults:UserDefaults = .standard) {self.defaults=defaults}
    func save(request:OperationRequest,options:BatchOptions,discovery:DiscoveryOptions,appearance:Int) throws {
        var reusable=request;reusable.excludedSourceKeys=[];reusable.placeOverrides=[:];reusable.groups=GroupOverrides()
        var paths=options;paths.importRoots=[]
        let data=try JSONEncoder().encode(Saved(schema:1,request:reusable,options:paths,discovery:Discovery(discovery),appearance:appearance))
        defaults.set(data,forKey:"operationSettings.v1")
    }
    func load() throws -> State? {
        guard let data=defaults.data(forKey:"operationSettings.v1") else {return nil}
        guard data.count<16_777_216 else {throw RestoreError(.invalidInput,"Saved settings are too large; defaults are in use.")}
        let saved=try JSONDecoder().decode(Saved.self,from:data)
        guard saved.schema==1 else {throw RestoreError(.invalidInput,"Saved settings use an unsupported version; defaults are in use.")}
        return .init(request:saved.request,options:saved.options,discovery:saved.discovery.value,appearance:(0...2).contains(saved.appearance) ? saved.appearance:0)
    }
}
