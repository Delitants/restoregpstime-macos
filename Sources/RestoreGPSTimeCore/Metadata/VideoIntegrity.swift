import Foundation
import AVFoundation
import CoreMedia
import CoreFoundation
import CryptoKit

struct VideoIntegrity {
    func signature(at url:URL,profile:String) async throws -> MediaIntegritySignature {
        let asset=AVURLAsset(url:url),tracks=try await asset.load(.tracks)
        guard !tracks.isEmpty,tracks.count<=64 else {throw RestoreError(.unsupported,"Video track count is outside the qualified profile.")}
        var payload=SHA256(),structure=SHA256(),totalBytes=0,totalSamples=0
        structure.field("asset-duration");time(try await asset.load(.duration),into:&structure)
        for track in tracks.sorted(by:{$0.trackID<$1.trackID}) {
            try Task.checkCancellation()
            let mediaType=track.mediaType
            guard mediaType == .video || mediaType == .audio else {throw RestoreError(.unsupported,"Metadata, GPS, caption and auxiliary video tracks need separate fixture qualification.")}
            structure.field("track:\(track.trackID):\(mediaType.rawValue)")
            let transform=try await track.load(.preferredTransform),size=try await track.load(.naturalSize),range=try await track.load(.timeRange)
            structure.field([transform.a,transform.b,transform.c,transform.d,transform.tx,transform.ty,size.width,size.height].map {String(describing:$0)}.joined(separator:","))
            time(range.start,into:&structure);time(range.duration,into:&structure)
            structure.field(String(try await track.load(.naturalTimeScale)))
            structure.field(String(try await track.load(.nominalFrameRate)))
            let segments=try await track.load(.segments)
            guard segments.count<=100000 else {throw RestoreError(.unsupported,"Video segment count exceeds its bound.")}
            for segment in segments {structure.field("segment:\(segment.isEmpty)");time(segment.timeMapping.source.start,into:&structure);time(segment.timeMapping.source.duration,into:&structure);time(segment.timeMapping.target.start,into:&structure);time(segment.timeMapping.target.duration,into:&structure)}
            let associations=try await track.load(.availableTrackAssociationTypes)
            for type in associations.sorted(by:{$0.rawValue<$1.rawValue}) {
                let related=try await track.loadAssociatedTracks(ofType:type)
                structure.field("association:\(type.rawValue):"+related.map {String($0.trackID)}.sorted().joined(separator:","))
            }
            let formats=try await track.load(.formatDescriptions)
            for format in formats {
                structure.field("format:\(CMFormatDescriptionGetMediaType(format)):\(CMFormatDescriptionGetMediaSubType(format))")
                if let extensions=CMFormatDescriptionGetExtensions(format) {structure.update(data:try canonical(extensions))}
            }
            let reader=try AVAssetReader(asset:asset),output=AVAssetReaderTrackOutput(track:track,outputSettings:nil)
            output.alwaysCopiesSampleData=false
            guard reader.canAdd(output) else {throw RestoreError(.unsupported,"Stored video/audio samples cannot be read without decoding.")}
            reader.add(output);defer {reader.cancelReading()}
            guard reader.startReading() else {throw RestoreError(.unsupported,"Cannot read stored samples: "+(reader.error?.localizedDescription ?? "unknown media error"))}
            var index=0
            while let sample=output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                try autoreleasepool {
                    structure.field("sample:\(track.trackID):\(index):\(CMSampleBufferGetNumSamples(sample))")
                    time(CMSampleBufferGetPresentationTimeStamp(sample),into:&structure);time(CMSampleBufferGetDecodeTimeStamp(sample),into:&structure);time(CMSampleBufferGetDuration(sample),into:&structure)
                    for mode in [kCMAttachmentMode_ShouldPropagate,kCMAttachmentMode_ShouldNotPropagate] {
                        if let attachments=CMCopyDictionaryOfAttachments(allocator:kCFAllocatorDefault,target:sample,attachmentMode:mode) {structure.field("buffer-attachments:\(mode)");structure.update(data:try canonical(attachments))}
                    }
                    if CMSampleBufferGetNumSamples(sample)==0 {
                        guard (CMSampleBufferGetDataBuffer(sample).map {CMBlockBufferGetDataLength($0)} ?? 0)==0,CMSampleBufferGetImageBuffer(sample)==nil else {throw RestoreError(.unsupported,"A marker-only buffer contains unqualified media data.")}
                        return
                    }
                    var needed=0
                    let timingStatus=CMSampleBufferGetSampleTimingInfoArray(sample,entryCount:0,arrayToFill:nil,entriesNeededOut:&needed)
                    guard [noErr,kCMSampleBufferError_ArrayTooSmall].contains(timingStatus),needed>=0,needed<=1000000 else {throw RestoreError(.unsupported,"Unqualified sample timing layout.")}
                    if needed>0 {
                        var timing=[CMSampleTimingInfo](repeating:CMSampleTimingInfo(duration:.invalid,presentationTimeStamp:.invalid,decodeTimeStamp:.invalid),count:needed)
                        guard CMSampleBufferGetSampleTimingInfoArray(sample,entryCount:needed,arrayToFill:&timing,entriesNeededOut:nil)==noErr else {throw RestoreError(.malformedMetadata,"Cannot inventory stored sample timings.")}
                        for item in timing {time(item.duration,into:&structure);time(item.presentationTimeStamp,into:&structure);time(item.decodeTimeStamp,into:&structure)}
                    }
                    var sizesNeeded=0
                    let sizeStatus=CMSampleBufferGetSampleSizeArray(sample,entryCount:0,arrayToFill:nil,entriesNeededOut:&sizesNeeded)
                    let emptyMarker=CMSampleBufferGetNumSamples(sample)==0 && sizesNeeded==0 && (CMSampleBufferGetDataBuffer(sample).map {CMBlockBufferGetDataLength($0)} ?? 0)==0
                    let validSizeStatus=[noErr,kCMSampleBufferError_ArrayTooSmall].contains(sizeStatus) || (emptyMarker && sizeStatus==kCMSampleBufferError_BufferHasNoSampleSizes)
                    guard validSizeStatus,sizesNeeded>=0,sizesNeeded<=1000000,CMSampleBufferGetImageBuffer(sample)==nil else {throw RestoreError(.unsupported,"Unqualified stored sample-size/layout table (status \(sizeStatus)).")}
                    if sizesNeeded>0 {
                        var sizes=[Int](repeating:0,count:sizesNeeded)
                        guard CMSampleBufferGetSampleSizeArray(sample,entryCount:sizesNeeded,arrayToFill:&sizes,entriesNeededOut:nil)==noErr else {throw RestoreError(.malformedMetadata,"Cannot inventory stored sample sizes.")}
                        for size in sizes {structure.field(UInt64(size))}
                    }
                    if let attachments=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:false) {structure.update(data:try canonical(attachments))}
                    if let data=CMSampleBufferGetDataBuffer(sample) {
                        let length=CMBlockBufferGetDataLength(data);payload.field("\(track.trackID):\(index):\(length)");var at=0
                        while at<length {
                            try Task.checkCancellation();let n=min(length-at,1_048_576);var bytes=Data(count:n)
                            let status=bytes.withUnsafeMutableBytes {CMBlockBufferCopyDataBytes(data,atOffset:at,dataLength:n,destination:$0.baseAddress!)}
                            guard status==kCMBlockBufferNoErr else {throw RestoreError(.malformedMetadata,"Cannot read stored compressed sample data.")}
                            payload.update(data:bytes);at+=n
                        }
                        totalBytes+=length
                    } else if CMSampleBufferGetNumSamples(sample)>0 {throw RestoreError(.unsupported,"The sample output requires decoded image buffers; this profile is read-only.")}
                }
                index+=1;totalSamples+=1
            }
            guard reader.status == .completed else {throw RestoreError(.malformedMetadata,"Stored sample reading did not complete: "+(reader.error?.localizedDescription ?? "reader stopped"))}
            structure.field("samples:\(track.trackID):\(index)")
        }
        guard totalSamples>0,totalBytes>0 else {throw RestoreError(.unsupported,"The video has no verifiable stored media samples.")}
        return .init(profile:profile,validator:"avfoundation-stored-samples-v1",payloadHash:payload.finalize().hex,structureHash:structure.finalize().hex)
    }
    private func time(_ value:CMTime,into hash:inout SHA256) {hash.field("\(value.value)/\(value.timescale):\(value.flags.rawValue):\(value.epoch)")}
    private func canonical(_ object:Any) throws -> Data {
        var entries=0
        func normalize(_ object:Any,depth:Int) throws -> TagValue {
            entries+=1;guard depth<=32,entries<=100000 else {throw RestoreError(.unsupported,"Media format/attachment structure exceeds its bound.")}
            if let data=object as? Data {guard data.count<=1_048_576 else {throw RestoreError(.unsupported,"A format/attachment blob exceeds its bound.")};return .object(["binary":.string(data.base64EncodedString())])}
            if let value=object as? String {return .string(value)}
            if let value=object as? NSNumber {return TagValue.fromJSON(value)}
            if let values=object as? [Any] {return .array(try values.map {try normalize($0,depth:depth+1)})}
            if let values=object as? [String:Any] {var result=[String:TagValue]();for key in values.keys.sorted() {result[key]=try normalize(values[key]!,depth:depth+1)};return .object(result)}
            throw RestoreError(.unsupported,"A media format/attachment contains an unqualified value type.")
        }
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        return try encoder.encode(normalize(object,depth:0))
    }
}
