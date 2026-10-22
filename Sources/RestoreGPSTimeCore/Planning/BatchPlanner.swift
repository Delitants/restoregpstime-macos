import Foundation
import Darwin

public struct BatchPlanner:Sendable {
    let dependencies:DependencyIdentity
    let clock:any Clock
    let reader:MetadataReader?
    public init(dependencies:DependencyIdentity,clock:any Clock=SystemClock(),reader:MetadataReader?=nil) {self.dependencies=dependencies;self.clock=clock;self.reader=reader}
    public func preview(items:[InspectedItem],request:OperationRequest,options:BatchOptions) async throws -> BatchPlan {
        let now=clock.now()
        let worker=Task.detached(priority:.userInitiated) {try await build(items:items,request:request,options:options,now:now)}
        return try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
    }
    private func build(items:[InspectedItem],request:OperationRequest,options:BatchOptions,now:Date) async throws -> BatchPlan {
        if let query=request.placeQuery {
            guard query.maxDistanceKM.isFinite,query.maxDistanceKM>0,query.maxDistanceKM<=20050,(1...10).contains(query.limit) else {throw RestoreError(.invalidInput,"Invalid offline lookup radius or candidate count.")}
        }
        if request.trashHiddenFiles {throw RestoreError(.invalidInput,"Trash uses a separate scoped preview and cannot run in a mutation batch.")}
        if request.removeGPS && request.location != nil {throw RestoreError(.invalidInput,"Choose either location output or location removal in one batch.")}
        if request.stripMetadata && (!request.tags.isEmpty || request.location != nil || request.dates?.embeddedDateRequested == true) {throw RestoreError(.invalidInput,"Metadata stripping cannot be combined with metadata additions.")}
        if options.mode == .saveCopies && options.outputRoot == nil {throw RestoreError(.invalidInput,"Choose the Save Copies folder.")}
        let selectedDirectories=items.filter {$0.snapshot.kind == .directory}
        for root in [options.mode == .saveCopies ? options.outputRoot:nil,options.recoveryRoot].compactMap({$0}) {
            var status=stat()
            if lstat(root.path,&status) != 0,errno==ENOENT {
                let parent=try FileIdentityReader().snapshot(at:Self.existingParent(of:root))
                if selectedDirectories.contains(where:{$0.snapshot.id.physicalKey==parent.id.physicalKey}) {throw RestoreError(.conflict,"Creating the output or recovery folder here would change a selected source directory. Choose an existing folder or another parent.")}
            }
        }
        let identityReader=FileIdentityReader(),capabilities=CapabilityRegistry()
        var resolved=[InspectedItem](),errors=[String:[String]](),dateErrors=[String:String](),fingerprints=[String:SourceFingerprint]()
        for var item in items {
            try Task.checkCancellation()
            let key=item.snapshot.id.physicalKey
            if let override=request.placeOverrides[key] {item.place=override}
            do {
                let fingerprint=try identityReader.fingerprint(at:item.snapshot.url)
                fingerprints[key]=fingerprint
                if fingerprint.snapshot != item.snapshot {errors[key,default:[]].append("The source changed after inspection. Import it again.")}
            } catch {errors[key,default:[]].append(error.localizedDescription)}
            if let policy=request.dates {
                var context=ReferenceDateContext(clock:FixedClock(now));context.datePolicy=policy;context.metadata=item.metadata;context.reader=reader
                context.referenceRoot=options.referenceRoot;context.inputRoot=options.importRoots.first;context.allowBasenameFallback=options.allowReferenceBasenameFallback
                do {item.dateResolution=try await ReferenceDateResolver().resolve(source:policy.source,snapshot:item.snapshot,context:context)}
                catch {dateErrors[key]=error.localizedDescription}
            }
            resolved.append(item)
        }
        let groups=try AssetGrouper().group(items:resolved,overrides:request.groups).map {group -> AssetGroup in
            guard let policy=request.dates,case .automaticCapture=policy.source,let primary=group.primary.dateResolution,group.members.count>1 else {return group}
            let members=group.members.map {member -> InspectedItem in
                guard member.metadata.profile.family == .unknown,["xmp","aae"].contains(member.snapshot.url.pathExtension.lowercased()) else {return member}
                var linked=member
                linked.dateResolution = .init(source:primary.source,original:primary.original,instant:primary.instant,offsetSeconds:primary.offsetSeconds,fractionalPrecision:primary.fractionalPrecision,interpretation:primary.interpretation+"; linked primary: "+group.primary.snapshot.url.lastPathComponent,warnings:primary.warnings,exactTimestamp:primary.exactTimestamp)
                dateErrors[member.snapshot.id.physicalKey]=nil
                return linked
            }
            return try AssetGroup(members:members,evidence:group.evidence)
        }
        let rules:VolumeNamingRules
        if let output=options.outputRoot,options.mode == .saveCopies {rules=try VolumeNamingRules.detect(at:try Self.existingParent(of:output))}
        else {rules=try resolved.first.map {try VolumeNamingRules.detect(at:$0.snapshot.url.deletingLastPathComponent())} ?? VolumeNamingRules()}
        let reservations=try NameAllocator().reserve(groups:groups,destinations:.init(root:options.outputRoot,saveCopies:options.mode == .saveCopies,importRoots:options.importRoots,rules:rules),template:request.rename)
        let orderedIDs=reservations.reduce(into:[UUID]()) {if $0.last != $1.groupID {$0.append($1.groupID)}}
        var byGroup=[UUID:AssetGroup]();for group in groups {byGroup[group.id]=group}
        var names=[String:NameReservation]();for name in reservations {names[name.sourceKey]=name}
        var claimed=Set(reservations.map {rules.collisionKey($0.finalURL.path)})
        var planned=[PlannedGroup](),index=0
        for groupID in orderedIDs {
            guard let group=byGroup[groupID] else {continue}
            let excluded=group.members.contains {request.excludedSourceKeys.contains($0.snapshot.id.physicalKey)}
            var plannedItems=[PlannedItem](),groupErrors=[String]()
            for item in group.members {
                let key=item.snapshot.id.physicalKey
                guard let name=names[key] else {throw RestoreError(.invalidInput,"Missing filename reservation.")}
                var reasons=(errors[key] ?? [])+(dateErrors[key].map {[$0]} ?? []),decisions=[String:CapabilityDecision](),dateMutation:DateMutation?
                if let reason=name.blockingReason {reasons.append(reason)}
                if options.mode == .modifyInPlace && !request.isFinderNotificationOnly && item.snapshot.kind == .regular && item.snapshot.id.linkCount>1 {reasons.append("In-place changes to multiply linked files are blocked. Save an independent copy.")}
                if options.mode == .modifyInPlace && !request.isFinderNotificationOnly && item.snapshot.isLocked && !request.finder.contains(.locked(false)) {reasons.append("The file is locked. Explicitly include Unlock to change it.")}
                if let recovery=options.recoveryRoot,Self.isWithin(item.snapshot.url,recovery) {reasons.append("Recovery originals cannot be inputs to this batch.")}
                if let output=options.outputRoot,options.mode == .saveCopies,Self.isWithin(item.snapshot.url,output) {reasons.append("An input is already inside the output folder.")}
                if let policy=request.dates,let resolution=item.dateResolution {
                    do {dateMutation=try DateMutationPlanner().plan(resolution:resolution,policy:policy,snapshot:item.snapshot,sequenceIndex:index)}
                    catch {reasons.append(error.localizedDescription)}
                }
                var tags=request.tags
                if let location=request.location {
                    if let place=item.place ?? group.primary.place {
                        do {
                            var locationOptions=location
                            if request.metadataDestination == .xmpSidecar {locationOptions.destination = .xmp}
                            tags+=try LocationTagPlanner().plan(match:place,document:item.metadata,options:locationOptions)
                        } catch {reasons.append(error.localizedDescription)}
                    } else {reasons.append("No selected nearest place or manual place is available.")}
                }
                let embedded=dateMutation?.embeddedDate != nil || dateMutation?.removeEmbeddedDates == true || !tags.isEmpty
                let metadataSidecar=request.metadataDestination == .xmpSidecar && embedded
                if request.metadataDestination == .xmpSidecar && (request.removeGPS || request.stripMetadata) {reasons.append("A sidecar cannot remove metadata from its source.")}
                for operation in [OperationKind.filesystemDates,.rename,.finderAttributes,.embeddedWrite,.removeGPS,.stripMetadata] {
                    let wanted:Bool
                    switch operation {
                    case .filesystemDates:wanted=dateMutation?.creationDate != nil || dateMutation?.modificationDate != nil
                    case .rename:wanted = !request.rename.preserveOriginal
                    case .finderAttributes:wanted = !request.finder.isEmpty
                    case .embeddedWrite:wanted=embedded && !metadataSidecar
                    case .removeGPS:wanted=request.removeGPS
                    case .stripMetadata:wanted=request.stripMetadata
                    }
                    if wanted {
                        let decision=capabilities.decision(for:operation,document:item.metadata,snapshot:item.snapshot);decisions[operation.rawValue]=decision
                        if !decision.isSupported {reasons.append(decision.reason)}
                    }
                }
                var tagIDs=Set<String>()
                for tag in tags {
                    let id:String;switch tag {case .set(let key,_),.remove(let key):id=key.rawValue}
                    if TagID(rawValue:id)==nil || !tagIDs.insert(id).inserted {reasons.append("Invalid or duplicate metadata destination: \(id).")}
                }
                var anchor:DestinationAnchor?
                do {anchor=try Self.anchor(for:name.finalURL)} catch {reasons.append(error.localizedDescription)}
                var sourceDates=dateMutation
                if metadataSidecar {sourceDates?.embeddedDate=nil;sourceDates?.embeddedTimestamp=nil;sourceDates?.removeEmbeddedDates=false}
                let mutation=MutationPlan(dates:sourceDates,tags:metadataSidecar ? []:tags,removeGPS:request.removeGPS,stripMetadata:request.stripMetadata,finder:request.finder,profile:item.metadata.profile,allowedMetadataChanges:.init(tags:metadataSidecar ? []:tagIDs,removesGPS:request.removeGPS,stripsDescriptive:request.stripMetadata))
                do {try await Self.qualifyMetadata(mutation,document:item.metadata,source:item.snapshot)} catch {reasons.append(error.localizedDescription)}
                let source=fingerprints[key] ?? .init(snapshot:item.snapshot,contentHash:"")
                plannedItems.append(.init(source:source,metadata:item.metadata,resolution:item.dateResolution,place:item.place,placeCandidates:item.placeCandidates,name:name,mutation:mutation,capabilities:decisions,destinationAnchor:anchor,blockingReasons:reasons))
                if metadataSidecar {
                    let target=name.finalURL.deletingPathExtension().appendingPathExtension("xmp")
                    var sidecarReasons=[String]();var st=stat()
                    if !claimed.insert(rules.collisionKey(target.path)).inserted || lstat(target.path,&st)==0 {sidecarReasons.append("The selected XMP sidecar path is already occupied or reserved.")}
                    if tags.contains(where:{ switch $0 {case .set(let id,_),.remove(let id):return !id.rawValue.hasPrefix("XMP-")} }) {sidecarReasons.append("Only XMP descriptive tags can be written to the selected sidecar.")}
                    let sidecarDocument=MetadataDocument(tags:[:],profile:.init(identifier:"XMP",family:.unknown))
                    let support=capabilities.decision(for:.embeddedWrite,document:sidecarDocument,snapshot:item.snapshot)
                    if !support.isSupported {sidecarReasons.append(support.reason)}
                    let sidecarName=NameReservation(groupID:group.id,sourceKey:key+":xmp",originalURL:item.snapshot.url,finalURL:target,sequence:name.sequence,wasTruncated:name.wasTruncated,needsTemporaryRename:false,blockingReason:sidecarReasons.first)
                    var sidecarDates=dateMutation
                    sidecarDates?.creationDate=nil;sidecarDates?.creationTimestamp=nil
                    sidecarDates?.modificationDate=nil;sidecarDates?.modificationTimestamp=nil
                    let sidecarMutation=MutationPlan(dates:sidecarDates,tags:tags,outputKind:.xmpSidecar,profile:sidecarDocument.profile,allowedMetadataChanges:.init(tags:tagIDs))
                    do {try await Self.qualifyMetadata(sidecarMutation,document:sidecarDocument,source:item.snapshot)} catch {sidecarReasons.append(error.localizedDescription)}
                    plannedItems.append(.init(source:source,metadata:sidecarDocument,resolution:item.dateResolution,place:item.place,placeCandidates:item.placeCandidates,name:sidecarName,mutation:sidecarMutation,capabilities:["embeddedWrite":support],destinationAnchor:anchor,blockingReasons:sidecarReasons))
                    reasons+=sidecarReasons
                }
                groupErrors+=reasons
            }
            planned.append(.init(id:group.id,evidence:group.evidence,items:plannedItems,eligibility:excluded ? .excluded:(groupErrors.isEmpty ? .eligible:.blocked),blockingReasons:Array(Set(groupErrors)).sorted()))
            index+=1
        }
        return .init(optionsDigest:try Self.settingsDigest(request:request,options:options),frozenNow:now,dependencies:dependencies,request:request,options:options,groups:planned)
    }
    public static func settingsDigest(request:OperationRequest,options:BatchOptions) throws -> String {
        struct Settings:Encodable {let request:OperationRequest;let options:BatchOptions}
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        var object=try JSONSerialization.jsonObject(with:encoder.encode(Settings(request:request,options:options))) as! [String:Any]
        var requestObject=object["request"] as! [String:Any]
        requestObject["excludedSourceKeys"]=request.excludedSourceKeys.sorted()
        var overrides=requestObject["groups"] as! [String:Any];overrides["unlinkedSourceKeys"]=request.groups.unlinkedSourceKeys.sorted();requestObject["groups"]=overrides;object["request"]=requestObject
        return FileIdentityReader.hash(try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]))
    }
    static func qualifyMetadata(_ mutation:MutationPlan,document:MetadataDocument,source:FileSnapshot) async throws {
        guard mutation.changesContent else {return}
        guard source.kind == .regular,document.diagnostics.isEmpty else {throw RestoreError(.unsupported,"Embedded metadata changes require an available ordinary file without metadata diagnostics.")}
        try document.requireQualifiedLayout()
        if mutation.profile.identifier=="XMP",mutation.outputKind != .xmpSidecar {throw RestoreError(.unsupported,"XMP writing is qualified for newly generated sidecars. Existing sidecars remain read-only.")}
        if mutation.stripMetadata {try MetadataStripProfiles().validateStrip(profile:mutation.profile);try MetadataStripProfiles().qualifyStrip(document:document)}
        try TagRegistry().validate(MetadataMutationDriver.expandedTags(mutation,document:document),profile:mutation.profile)
        if mutation.outputKind != .xmpSidecar {_ = try await MediaIntegrityValidator().signature(at:source.url,profile:mutation.profile)}
    }
    static func isWithin(_ url:URL,_ root:URL)->Bool {let path=url.standardizedFileURL.path,base=root.standardizedFileURL.path;return path==base || base=="/" || path.hasPrefix(base+"/")}
    static func existingParent(of url:URL) throws -> URL {
        try FileSystemPath.existingAncestor(of:url).parent
    }
    static func anchor(for target:URL) throws -> DestinationAnchor {
        let parent=try existingParent(of:target.deletingLastPathComponent()),snapshot=try FileIdentityReader().snapshot(at:parent)
        guard snapshot.kind == .directory else {throw RestoreError(.conflict,"The destination parent is linked, unavailable or not a directory.")}
        return .init(requestedURL:parent,resolvedURL:try FileSystemPath.canonicalDirectory(parent),identity:snapshot.id)
    }
}
private extension DatePolicy {var embeddedDateRequested:Bool {targets.contains(.capture)}}
