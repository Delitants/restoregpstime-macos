import Foundation
import Darwin

/// Combines already inspected component results. It never resolves capture dates,
/// looks up locations, or chooses new sequence numbers.
public struct BatchPlanComposer:Sendable {
    public init() {}
    public func combine(components:[PreviewComponent:BatchPlan],request:OperationRequest,options:BatchOptions) async throws -> BatchPlan {
        let selected=PreviewComponent.allCases.filter {$0.isSelected(in:request)}
        let missing=selected.filter {components[$0]==nil}
        guard missing.isEmpty else {throw RestoreError(.invalidInput,"Preview the selected changes in: "+missing.map(\.title).joined(separator:", ")+".")}
        guard let first=selected.compactMap({components[$0]}).first else {throw RestoreError(.invalidInput,"Select at least one change to apply.")}
        if request.removeGPS && request.location != nil {throw RestoreError(.invalidInput,"Choose either location output or location removal in one batch.")}
        if request.stripMetadata && (!request.tags.isEmpty || request.location != nil || request.dates?.targets.contains(.capture)==true) {throw RestoreError(.invalidInput,"Metadata stripping cannot be combined with metadata additions.")}
        try BatchPlanner.validateStorageRoots(snapshots:first.groups.flatMap(\.items).map {$0.source.snapshot},options:options)
        let firstGroups=Set(first.groups.map(Self.groupKey))
        var maps=[PreviewComponent:[String:PlannedItem]](),groups=[PreviewComponent:[String:PlannedGroup]]()
        for component in selected {
            let plan=components[component]!
            guard plan.request==component.request(from:request),plan.dependencies==first.dependencies,plan.options.mode==options.mode,Set(plan.groups.map(Self.groupKey))==firstGroups else {throw RestoreError(.conflict,"A selected preview no longer matches this batch. Preview "+component.title+" again.")}
            if component == .dates,(plan.options.referenceRoot != options.referenceRoot || plan.options.allowReferenceBasenameFallback != options.allowReferenceBasenameFallback) {throw RestoreError(.conflict,"Reference settings changed. Preview Dates & time again.")}
            var items=[String:PlannedItem](),byGroup=[String:PlannedGroup]()
            for group in plan.groups {
                byGroup[Self.groupKey(group)]=group
                for item in group.items {
                    guard items.updateValue(item,forKey:item.name.sourceKey)==nil else {throw RestoreError(.conflict,"A preview contains duplicate source reservations.")}
                }
            }
            maps[component]=items;groups[component]=byGroup
        }
        var combined=[PlannedGroup]()
        for group in first.groups {
            try Task.checkCancellation()
            let key=Self.groupKey(group),parts=selected.compactMap {groups[$0]?[key]}
            let keys=Set(parts.flatMap {$0.items.map { $0.name.sourceKey }}).sorted()
            var outputs=[PlannedItem](),reasons=Array(Set(parts.flatMap {part in
                let itemReasons=Set(part.items.flatMap(\.blockingReasons))
                return part.blockingReasons.filter {!itemReasons.contains($0)}
            }))
            if request.finder.contains(.locked(false)) {reasons.removeAll {$0=="The file is locked. Explicitly include Unlock to change it."}}
            for sourceKey in keys {
                let fragments=selected.compactMap {maps[$0]?[sourceKey]}
                guard let original=fragments.first else {continue}
                guard fragments.allSatisfy({$0.source==original.source && $0.metadata==original.metadata}) else {throw RestoreError(.conflict,"The source differs between tab previews. Import it again: "+original.source.snapshot.url.lastPathComponent)}
                let dates=maps[.dates]?[sourceKey]
                let location=maps[.places]?[sourceKey]
                let editing=maps[.metadata]?[sourceKey]
                let finder=maps[.finder]?[sourceKey]
                var tags=[TagMutation](),tagValues=[String:TagMutation]()
                for tag in fragments.flatMap({$0.mutation.tags}) {
                    let id:String;switch tag {case .set(let key,_),.remove(let key):id=key.rawValue}
                    if let previous=tagValues[id] {guard previous==tag else {throw RestoreError(.conflict,"Selected tabs propose conflicting values for "+id+".")}}
                    else {tags.append(tag);tagValues[id]=tag}
                }
                let mutation=MutationPlan(dates:dates?.mutation.dates,tags:tags,removeGPS:editing?.mutation.removeGPS ?? false,stripMetadata:editing?.mutation.stripMetadata ?? false,finder:finder?.mutation.finder ?? [],outputKind:original.mutation.outputKind,profile:original.mutation.profile,allowedMetadataChanges:.init(tags:Set(tagValues.keys),removesGPS:editing?.mutation.removeGPS ?? false,stripsDescriptive:editing?.mutation.stripMetadata ?? false))
                let chosenComponent=location != nil ? PreviewComponent.places:selected.first(where:{maps[$0]?[sourceKey] != nil})!
                let chosen=location ?? original
                var proposedURL=chosen.name.finalURL
                // A sidecar produced by another tab follows the already reviewed
                // media name; it must never be left under the old source stem.
                let mediaName=original.mutation.outputKind == .xmpSidecar ? maps[.places]?[original.source.snapshot.id.physicalKey]?.name:nil
                if let mediaName {proposedURL=mediaName.finalURL.deletingPathExtension().appendingPathExtension("xmp")}
                if options.mode == .saveCopies {
                    let nameComponent=mediaName == nil ? chosenComponent:PreviewComponent.places
                    let oldRoot=components[nameComponent]!.options.outputRoot ?? DestinationContext.previewRoot
                    let path=try FileSystemPath.relativeComponents(of:proposedURL,under:oldRoot)
                    proposedURL=path.reduce(DestinationContext.previewRoot) {$0.appendingPathComponent($1)}
                }
                var itemReasons=Array(Set(fragments.flatMap(\.blockingReasons)))
                if request.finder.contains(.locked(false)) {itemReasons.removeAll {$0=="The file is locked. Explicitly include Unlock to change it."}}
                if options.mode == .saveCopies {itemReasons.removeAll {Self.destinationReasons.contains($0)}}
                itemReasons.removeAll {$0=="Recovery originals cannot be inputs to this batch."}
                var destinationAnchor=options.mode == .saveCopies ? nil:chosen.destinationAnchor
                if mediaName != nil {
                    itemReasons.removeAll {$0=="The selected XMP sidecar path is already occupied or reserved."}
                    if options.mode == .modifyInPlace {
                        if SecureFS.exists(proposedURL) {itemReasons.append("The selected XMP sidecar path is already occupied or reserved.")}
                        do {destinationAnchor=try BatchPlanner.anchor(for:proposedURL)} catch {itemReasons.append(error.localizedDescription)}
                    }
                }
                if mutation.changesContent {
                    do {try TagRegistry().validate(MetadataMutationDriver.expandedTags(mutation,document:original.metadata),profile:mutation.profile)}
                    catch {itemReasons.append(error.localizedDescription)}
                }
                if let recovery=options.recoveryRoot,BatchPlanner.isWithin(original.source.snapshot.url,recovery) {itemReasons.append("Recovery originals cannot be inputs to this batch.")}
                var capabilities=[String:CapabilityDecision]()
                for fragment in fragments {capabilities.merge(fragment.capabilities,uniquingKeysWith:{$1})}
                let name=NameReservation(groupID:group.id,sourceKey:sourceKey,originalURL:chosen.name.originalURL,finalURL:proposedURL,sequence:chosen.name.sequence,wasTruncated:chosen.name.wasTruncated,needsTemporaryRename:chosen.name.needsTemporaryRename,blockingReason:itemReasons.first)
                outputs.append(.init(source:original.source,metadata:original.metadata,resolution:dates?.resolution,place:location?.place ?? original.place,placeCandidates:location?.placeCandidates ?? original.placeCandidates,name:name,mutation:mutation,capabilities:capabilities,destinationAnchor:destinationAnchor,blockingReasons:itemReasons))
                reasons+=itemReasons
            }
            let excluded=parts.contains {$0.eligibility == .excluded}
            combined.append(.init(id:group.id,evidence:group.evidence,items:outputs,eligibility:excluded ? .excluded:(reasons.isEmpty ? .eligible:.blocked),blockingReasons:Array(Set(reasons)).sorted()))
        }
        var initialOptions=options
        let pending=options.mode == .saveCopies
        if pending {initialOptions.outputRoot=nil}
        let plan=BatchPlan(optionsDigest:try BatchPlanner.settingsDigest(request:request,options:initialOptions),frozenNow:first.frozenNow,dependencies:first.dependencies,request:request,options:initialOptions,groups:combined,destinationPending:pending)
        if pending,let folder=options.outputRoot {return try await bindDestination(plan,to:folder)}
        return plan
    }
    private static let destinationReasons:Set<String>=[
        "A destination name is already occupied; choose another template or output folder.",
        "An input is already inside the output folder.",
        "The previewed name is not supported by this destination volume. Update the Location names preview.",
        "Two previewed files have the same destination name.",
        "The previewed destination name is already occupied. Choose another folder or update the Location names preview.",
        "The selected XMP sidecar path is already occupied or reserved."
    ]
    private static func groupKey(_ group:PlannedGroup)->String {Set(group.items.map {$0.source.snapshot.id.physicalKey}).sorted().joined(separator:"|")}

    public func bindDestination(_ plan:BatchPlan,to folder:URL) async throws -> BatchPlan {
        guard plan.options.mode == .saveCopies else {throw RestoreError(.invalidInput,"An output folder is only used for Save copies.")}
        let root=folder.standardizedFileURL
        guard try FileIdentityReader().snapshot(at:root).kind == .directory else {throw RestoreError(.invalidInput,"Choose an available output folder.")}
        let previous=plan.options.outputRoot ?? DestinationContext.previewRoot
        let rules=try VolumeNamingRules.detect(at:root)
        var claimed=Set<String>(),result=[PlannedGroup](),existingNames=[String:Set<String>]()
        for group in plan.groups {
            try Task.checkCancellation()
            var items=[PlannedItem](),groupReasons=group.blockingReasons
            for item in group.items {
                let components=try FileSystemPath.relativeComponents(of:item.name.finalURL,under:previous)
                guard !components.isEmpty else {throw RestoreError(.conflict,"A previewed output has no filename.")}
                let target=components.reduce(root) {$0.appendingPathComponent($1)}
                var reasons=item.blockingReasons
                if components.contains(where:{$0.utf8.count>rules.maxNameBytes || !NameTemplate.Parsed.validComponent($0)}) {reasons.append("The previewed name is not supported by this destination volume. Update the Location names preview.")}
                if !claimed.insert(rules.collisionKey(target.path)).inserted {reasons.append("Two previewed files have the same destination name.")}
                if BatchPlanner.isWithin(item.source.snapshot.url,root) {reasons.append("An input is already inside the output folder.")}
                var anchor:DestinationAnchor?
                do {
                    anchor=try BatchPlanner.anchor(for:target)
                    let parent=target.deletingLastPathComponent()
                    if existingNames[parent.path]==nil {
                        existingNames[parent.path]=SecureFS.exists(parent) ? Set(try FileManager.default.contentsOfDirectory(at:parent,includingPropertiesForKeys:nil).map {rules.collisionKey($0.lastPathComponent)}):[]
                    }
                    if existingNames[parent.path]!.contains(rules.collisionKey(target.lastPathComponent)) {reasons.append("The previewed destination name is already occupied. Choose another folder or update the Location names preview.")}
                } catch {reasons.append(error.localizedDescription)}
                let name=NameReservation(groupID:group.id,sourceKey:item.name.sourceKey,originalURL:item.name.originalURL,finalURL:target,sequence:item.name.sequence,wasTruncated:item.name.wasTruncated,needsTemporaryRename:false,blockingReason:reasons.first)
                items.append(.init(source:item.source,metadata:item.metadata,resolution:item.resolution,place:item.place,placeCandidates:item.placeCandidates,name:name,mutation:item.mutation,capabilities:item.capabilities,destinationAnchor:anchor,blockingReasons:Array(Set(reasons)).sorted()))
                groupReasons+=reasons
            }
            result.append(.init(id:group.id,evidence:group.evidence,items:items,eligibility:group.eligibility == .excluded ? .excluded:(groupReasons.isEmpty ? .eligible:.blocked),blockingReasons:Array(Set(groupReasons)).sorted()))
        }
        var options=plan.options;options.outputRoot=root
        return .init(optionsDigest:try BatchPlanner.settingsDigest(request:plan.request,options:options),frozenNow:plan.frozenNow,dependencies:plan.dependencies,request:plan.request,options:options,groups:result)
    }
}
