import Foundation

public actor MetadataMutationDriver:MutationDriver {
    let paths:RuntimePaths
    let reader:MetadataReader,writer:ExifToolWriter
    let registry=TagRegistry(),integrity=MediaIntegrityValidator()
    public init(paths:RuntimePaths) {self.paths=paths;reader=MetadataReader(paths:paths);writer=ExifToolWriter(paths:paths)}
    public func apply(_ mutation:MutationPlan,to stage:URL) async throws -> StageVerification {
        if !mutation.changesContent {return .init(contentHash:try FileIdentityReader().fingerprint(at:stage).contentHash,integrityValidator:"sha256-v1")}
        try StageOwnership.shared.require(stage)
        let explicit=Set(mutation.tags.map {tag->String in switch tag {case .set(let id,_),.remove(let id):return id.rawValue}})
        guard explicit==mutation.allowedMetadataChanges.tags,mutation.removeGPS==mutation.allowedMetadataChanges.removesGPS,mutation.stripMetadata==mutation.allowedMetadataChanges.stripsDescriptive else {throw RestoreError(.invalidInput,"The metadata mutation is outside its frozen tag/operation scope.")}
        let original=try FileIdentityReader().snapshot(at:stage),before=try await reader.read(snapshot:original)
        guard before.profile.identifier==mutation.profile.identifier else {throw RestoreError(.conflict,"The stage container differs from the previewed profile.")}
        if mutation.profile.identifier=="XMP" {
            guard mutation.outputKind == .xmpSidecar,!before.tags.keys.contains(where:{$0.hasPrefix("XMP-") && $0 != "XMP-x:XMPToolkit"}) else {throw RestoreError(.unsupported,"The XMP write profile accepts only new, empty sidecar stages.")}
        }
        guard before.diagnostics.isEmpty else {throw RestoreError(.unsupported,"This metadata layout has backend diagnostics and remains read-only: "+before.diagnostics.joined(separator:"; "))}
        if mutation.stripMetadata {
            try MetadataStripProfiles().validateStrip(profile:mutation.profile);try MetadataStripProfiles().qualifyStrip(document:before)
            guard mutation.tags.isEmpty,mutation.dates?.embeddedDate==nil else {throw RestoreError(.invalidInput,"Stripping cannot also add embedded metadata.")}
        }
        let tags=try Self.expandedTags(mutation,document:before)
        try registry.validate(tags,profile:mutation.profile)
        let beforeSignature=try await integrity.signature(at:stage,profile:mutation.profile)
        let overhead=UInt64(67_108_864)
        let capacity=original.id.size.addingReportingOverflow(overhead)
        guard !capacity.overflow else {throw RestoreError(.unsupported,"Stage size exceeds supported capacity accounting.")}
        try SecureFS.requireSpace(at:stage.deletingLastPathComponent(),bytes:capacity.partialValue)
        let archive=try FileAttributeArchive.capture(stage)
        if mutation.stripMetadata {
            let order=before.tags["File:ExifByteOrder"]?.text
            let endian=(order=="II" || order=="MM") ? ["-ExifByteOrder=\(order!)"]:[]
            try await writer.run(["-overwrite_original_in_place","-P","-n","-api","NoMandatory=1","-all=","--JFIF:all"]+endian+["-tagsFromFile","@"]+MetadataStripProfiles.preservedSelectors,to:stage)
        }
        else {
            let direct=mutation.removeGPS ? tags.filter {tag in if case .remove(let id)=tag {return !id.rawValue.hasPrefix("XMP-")};return true}:tags
            _ = try await writer.write(direct,to:stage,profile:mutation.profile)
            if mutation.removeGPS {try await writer.removeXMPLocation(to:stage)}
        }
        try SecureFS.applyMetadata(original,from:archive,to:try SecureFS.canonical(stage))
        let after=try await reader.read(snapshot:FileIdentityReader().snapshot(at:stage)),afterSignature=try await integrity.signature(at:stage,profile:mutation.profile)
        try integrity.verify(before:beforeSignature,after:afterSignature,allowedChanges:mutation.allowedMetadataChanges)
        if mutation.removeGPS {try MetadataStripProfiles().verifyLocationRemoved(in:after)}
        try Self.verifyDiff(before:before,after:after,tags:tags,stripping:mutation.stripMetadata)
        let final=try FileIdentityReader().fingerprint(at:stage)
        guard SecureFS.attributesEqual(final.snapshot,original,flags:original.flags & ~UInt32(0x2)) else {throw RestoreError(.verificationFailed,"Unselected filesystem attributes changed during metadata writing.")}
        return .init(contentHash:final.contentHash,integrityValidator:afterSignature.validator,verifiedTags:after.tags,notes:["Stored media and unselected attributes verified."])
    }
    public func restoreAttributes(_ snapshot:FileSnapshot,to stage:URL) async throws {
        let archive=try FileAttributeArchive.capture(stage)
        guard try FileIdentityReader().snapshot(at:archive).xattrHashes==snapshot.xattrHashes else {throw RestoreError(.verificationFailed,"Recovery stage extended attributes differ from the retained original.")}
        try SecureFS.applyMetadata(snapshot,from:archive,to:try SecureFS.canonical(stage))
    }
    public static func expandedTags(_ mutation:MutationPlan,document:MetadataDocument) throws -> [TagMutation] {
        var tags=mutation.tags
        if mutation.removeGPS {
            guard !tags.contains(where:{if case .set(let id,_)=$0 {return MetadataStripProfiles.looksLikeLocation(id.rawValue)};return false}) else {throw RestoreError(.invalidInput,"Location removal cannot also add location fields.")}
            tags+=try MetadataStripProfiles().locationRemovals(in:document)
        }
        if let date=mutation.dates,date.embeddedDate != nil || date.removeEmbeddedDates {tags+=try EmbeddedDateTags().mutations(date,profile:mutation.profile,document:document)}
        return tags
    }
    static func verifyDiff(before:MetadataDocument,after:MetadataDocument,tags:[TagMutation],stripping:Bool) throws {
        let registry=TagRegistry()
        var selected=Set<String>()
        for mutation in tags {
            let id:TagID;switch mutation {case .set(let tag,_),.remove(let tag):id=tag}
            let (actual,_)=try registry.definition(id)
            selected.insert(actual)
            for suffix in ["-x-default","-und"] where actual.hasSuffix(suffix) {selected.insert(String(actual.dropLast(suffix.count)))}
        }
        let generated:Set<String>=["XMP-x:XMPToolkit","ExifIFD:ExifVersion","ExifIFD:FlashpixVersion"]
        let offsets:Set<String>=["QuickTime:MediaDataOffset","QuickTime:MediaDataSize","QuickTime:MovieDataOffset","QuickTime:MovieDataSize","IFD0:StripOffsets","IFD0:TileOffsets","IFD1:ThumbnailOffset"]
        for key in Set(before.tags.keys).union(after.tags.keys) where before.tags[key] != after.tags[key] {
            if ["File:","System:","Composite:","ExifTool:"].contains(where:{key.hasPrefix($0)}) || selected.contains(key) || offsets.contains(key) {continue}
            if key=="XMP-x:XMPToolkit" {continue}
            if before.profile.identifier=="WEBP" && after.profile.identifier=="WEBP" && key=="RIFF:WebP_Flags" {continue} // All rendering feature bits are covered by webp-chunks-v1.
            if before.profile.family == .video && key=="QuickTime:HandlerType" {
                let metadataHandlers:Set<String>=["mdir","mdta"]
                if [before.tags[key],after.tags[key]].compactMap({$0}).allSatisfy({metadataHandlers.contains($0.text)}) {continue}
            } // Creating/removing a container metadata directory may change its metadata handler; track handlers are protected by the media validator.
            if generated.contains(key),before.tags[key]==nil {continue}
            if key=="Photoshop:IPTCDigest" {continue}
            if stripping && !MetadataStripProfiles.protectedTag(key) && after.tags[key]==nil {continue}
            throw RestoreError(.verificationFailed,"An unselected metadata field changed: \(key).")
        }
        guard after.diagnostics.isEmpty else {throw RestoreError(.verificationFailed,"Metadata read-back has diagnostics: "+after.diagnostics.joined(separator:"; "))}
    }
}
