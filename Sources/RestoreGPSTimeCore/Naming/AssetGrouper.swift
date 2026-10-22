import Foundation

public struct AssetGrouper {
    public init() {}
    public func group(items:[InspectedItem],overrides:GroupOverrides=GroupOverrides()) throws -> [AssetGroup] {
        var unique=[String:InspectedItem]()
        for item in items where unique[item.snapshot.id.physicalKey] == nil { unique[item.snapshot.id.physicalKey]=item }
        let sorted=unique.values.sorted {$0.snapshot.url.path < $1.snapshot.url.path}
        var groups=[[InspectedItem]](),evidence=[String](),assigned=Set<String>()
        func append(_ members:[InspectedItem],_ why:String) {
            groups.append(members);evidence.append(why)
            assigned.formUnion(members.map {$0.snapshot.id.physicalKey})
        }
        for keys in overrides.forcedGroups {
            guard keys.count>1,Set(keys).count==keys.count,keys.allSatisfy({unique[$0]?.snapshot.kind == .regular && !assigned.contains($0) && !overrides.unlinkedSourceKeys.contains($0)}) else { throw RestoreError(.invalidInput,"Explicit asset groups require ordinary files and cannot contain unknown, duplicate, or unlinked files.") }
            append(keys.compactMap {unique[$0]}.sorted {$0.snapshot.url.path < $1.snapshot.url.path},"Explicit user grouping")
        }
        let idTags=["Apple:ContentIdentifier","Keys:ContentIdentifier","QuickTime:ContentIdentifier","XMP-apple-fi:ContentIdentifier"]
        var identifiers=[String:[InspectedItem]]()
        for item in sorted where !assigned.contains(item.snapshot.id.physicalKey) && !overrides.unlinkedSourceKeys.contains(item.snapshot.id.physicalKey) {
            let ids=Set(idTags.compactMap {item.metadata.tags[$0]?.text}.filter {!$0.isEmpty})
            if ids.count==1,let identifier=ids.first { identifiers[identifier,default:[]].append(item) }
        }
        for identifier in identifiers.keys.sorted() {
            let matches=identifiers[identifier]!
            let photos=matches.filter {$0.metadata.profile.family == .photo || $0.metadata.profile.family == .raw}
            let videos=matches.filter {$0.metadata.profile.family == .video}
            if photos.count==1 && videos.count==1 && matches.count==2 { append(photos+videos,"Matching capture content identifier") }
        }
        let sidecars=sorted.filter {["xmp","aae"].contains($0.snapshot.url.pathExtension.lowercased()) && !assigned.contains($0.snapshot.id.physicalKey) && !overrides.unlinkedSourceKeys.contains($0.snapshot.id.physicalKey)}
        let sidecarKeys=Set(sidecars.map {$0.snapshot.id.physicalKey})
        for item in sorted where !assigned.contains(item.snapshot.id.physicalKey) && !sidecarKeys.contains(item.snapshot.id.physicalKey) { append([item],"Independent file") }
        // A sidecar belongs only to one unambiguous media group in its own directory.
        var stems=[String:Set<Int>]()
        for (index,members) in groups.enumerated() {
            for item in members where item.metadata.profile.family != .unknown && !overrides.unlinkedSourceKeys.contains(item.snapshot.id.physicalKey) {
                let url=item.snapshot.url.standardizedFileURL
                for stem in [url.lastPathComponent,url.deletingPathExtension().lastPathComponent] {
                    stems[url.deletingLastPathComponent().path+"/"+stem.precomposedStringWithCanonicalMapping,default:[]].insert(index)
                }
            }
        }
        for item in sidecars {
            let url=item.snapshot.url.standardizedFileURL
            let key=url.deletingLastPathComponent().path+"/"+url.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
            if let matches=stems[key],matches.count==1,let index=matches.first { groups[index].append(item);evidence[index]+="; unique same-stem sidecar" }
            else { append([item],"Unpaired sidecar (no unique media group)") }
        }
        return try groups.enumerated().map {try AssetGroup(members:$0.element,evidence:evidence[$0.offset])}
    }
}
