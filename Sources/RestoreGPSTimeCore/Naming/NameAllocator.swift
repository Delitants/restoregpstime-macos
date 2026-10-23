import Foundation
import Darwin

public struct NameAllocator {
    public init() {}
    public func reserve(groups:[AssetGroup],destinations:DestinationContext,template:NameTemplate=NameTemplate()) throws -> [NameReservation] {
        let parsed=try template.parsed(),rules=destinations.rules
        guard rules.maxNameBytes>0,rules.maxNameBytes<=65535 else {throw RestoreError(.invalidInput,"Invalid volume filename limit.")}
        if destinations.saveCopies && destinations.root == nil { throw RestoreError(.invalidInput,"Choose a destination for Save Copies.") }
        var roots=[URL](),labels=[String:String](),usedLabels=Set<String>()
        for root in destinations.importRoots.map({$0.standardizedFileURL}).sorted(by:{$0.path<$1.path}) where !roots.contains(where:{$0.path==root.path}) {
            roots.append(root);let base=root.lastPathComponent.isEmpty ? "Root":root.lastPathComponent
            var label=base,index=1
            while !usedLabels.insert(rules.collisionKey(label)).inserted {index+=1;label=base+String(format:" - %04d",index)}
            labels[root.path]=label
        }
        roots.sort {$0.path.count>$1.path.count}
        func relative(_ item:InspectedItem)->String {
            let url=item.snapshot.url.standardizedFileURL
            guard let root=roots.first(where:{url.path==$0.path || url.path.hasPrefix($0.path+"/")}) else {return url.lastPathComponent}
            let suffix=String(url.path.dropFirst(root.path.count)).trimmingCharacters(in:CharacterSet(charactersIn:"/"))
            return labels[root.path]!+(suffix.isEmpty ? "":"/"+suffix)
        }
        func parent(_ item:InspectedItem)->URL {
            guard destinations.saveCopies,let root=destinations.root else {return item.snapshot.url.deletingLastPathComponent()}
            return root.appendingPathComponent(relative(item)).deletingLastPathComponent()
        }
        var existing=[String:[String:[URL]]](),reserved=Set<String>(),placeNext=[String:Int](),result=[NameReservation]()
        func occupied(_ target:URL,by item:InspectedItem) throws -> Bool {
            if destinations.provisional {return false}
            let parent=target.deletingLastPathComponent().standardizedFileURL,key=rules.collisionKey(target.lastPathComponent)
            if existing[parent.path] == nil {
                var map=[String:[URL]]();var status=stat()
                if lstat(parent.path,&status)==0 {
                    guard status.st_mode & S_IFMT == S_IFDIR else {throw RestoreError(.conflict,"A destination parent is not a directory.")}
                    for child in try FileManager.default.contentsOfDirectory(at:parent,includingPropertiesForKeys:nil) {map[rules.collisionKey(child.lastPathComponent),default:[]].append(child)}
                } else if errno != ENOENT {throw RestoreError(.io,"Cannot inspect destination: \(parent.path)")}
                existing[parent.path]=map
            }
            guard let entries=existing[parent.path]![key] else {return false}
            if destinations.saveCopies {return true}
            // Only this source name may be replaced by its own staged file.
            return entries.contains {$0.standardizedFileURL.path != item.snapshot.url.standardizedFileURL.path}
        }
        func capture(_ group:AssetGroup)->FileTimestamp? {
            guard let resolution=group.primary.dateResolution else {return nil}
            return resolution.exactTimestamp ?? (try? FileTimestamp(date:resolution.instant))
        }
        let ordered=groups.sorted {
            let ad=capture($0),bd=capture($1)
            if let ad,let bd,ad != bd {return ad<bd}
            if (ad != nil) != (bd != nil) {return ad != nil}
            let a=relative($0.primary).precomposedStringWithCanonicalMapping,b=relative($1.primary).precomposedStringWithCanonicalMapping
            if a != b {return a<b};return $0.primary.snapshot.url.path.utf8.lexicographicallyPrecedes($1.primary.snapshot.url.path.utf8)
        }
        for group in ordered {
            if Task.isCancelled {throw RestoreError(.cancelled,"Naming cancelled.")}
            let place=group.primary.place
            let placeKey=rules.collisionKey((place?.country ?? "")+"\u{0}"+(place?.city ?? ""))
            var sequence=placeNext[placeKey] ?? 1
            var accepted=[NameReservation]()
            do {
                while true {
                    var candidates=[NameReservation](),keys=Set<String>(),collision=false
                    for item in group.members {
                        let rendered:(String,Bool)=template.preserveOriginal ? (item.snapshot.url.lastPathComponent,false) : try parsed.render(item:item,place:place,sequence:sequence,limit:rules.maxNameBytes)
                        guard rendered.0.utf8.count<=rules.maxNameBytes,NameTemplate.Parsed.validComponent(rendered.0) else {throw RestoreError(.invalidInput,"The original filename is invalid on the destination volume.")}
                        let target=parent(item).appendingPathComponent(rendered.0).standardizedFileURL,key=rules.collisionKey(target.path)
                        guard keys.insert(key).inserted else {throw RestoreError(.conflict,"Linked files would have the same destination name and extension.")}
                        if try reserved.contains(key) || occupied(target,by:item) {collision=true}
                        let source=item.snapshot.url.standardizedFileURL
                        candidates.append(.init(groupID:group.id,sourceKey:item.snapshot.id.physicalKey,originalURL:source,finalURL:target,sequence:template.preserveOriginal ? nil:sequence,wasTruncated:rendered.1,needsTemporaryRename:!destinations.saveCopies && source.path != target.path && rules.collisionKey(source.path)==key,blockingReason:nil))
                    }
                    if !collision {accepted=candidates;reserved.formUnion(keys);break}
                    guard !template.preserveOriginal,parsed.width != nil,sequence<1_000_000_000 else {throw RestoreError(.conflict,"A destination name is already occupied; choose another template or output folder.")}
                    sequence+=1
                }
                if !template.preserveOriginal {placeNext[placeKey]=sequence+1}
            } catch let error as RestoreError where error.code != .cancelled {
                accepted=group.members.map { item in .init(groupID:group.id,sourceKey:item.snapshot.id.physicalKey,originalURL:item.snapshot.url,finalURL:parent(item).appendingPathComponent(item.snapshot.url.lastPathComponent),sequence:nil,wasTruncated:false,needsTemporaryRename:false,blockingReason:error.detail) }
            }
            result+=accepted
        }
        return result
    }
}
