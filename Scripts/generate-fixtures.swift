import Foundation
import CoreGraphics
import ImageIO
import AVFoundation
import CryptoKit

// Synthetic, redistributable fixtures. No user media is read.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.15, green: 0.45, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0,y: 0,width: 32,height: 32))
context.setFillColor(CGColor(red: 0.9, green: 0.45, blue: 0.2, alpha: 1)); context.fill(CGRect(x: 8,y: 8,width: 16,height: 16))
let image = context.makeImage()!
var entries = [[String:Any]]()
for (name,type) in [("paris.jpg","public.jpeg"),("paris.heic","public.heic"),("paris.tiff","public.tiff"),("paris.png","public.png")] {
    let url = destination.appendingPathComponent(name)
    guard !FileManager.default.fileExists(atPath: url.path) else { fatalError("Fixture exists; choose a fresh fixture directory: \(url.path)") }
    guard let writer = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else { fatalError("Encoder unavailable: \(type)") }
    let properties: [CFString:Any] = [
        kCGImagePropertyOrientation: 1,
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal:"2024:01:02 03:04:05",kCGImagePropertyExifOffsetTimeOriginal:"+02:00",kCGImagePropertyExifSubsecTimeOriginal:"123"],
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude:48.8566,kCGImagePropertyGPSLatitudeRef:"N",kCGImagePropertyGPSLongitude:2.3522,kCGImagePropertyGPSLongitudeRef:"E"]
    ]
    CGImageDestinationAddImage(writer,image,properties as CFDictionary)
    guard CGImageDestinationFinalize(writer) else { fatalError("Cannot encode \(type)") }
    entries.append(["id":name,"sha256":SHA256.hash(data: try Data(contentsOf:url)).map {String(format:"%02x",$0)}.joined(),"origin":"Generated geometric image; synthetic Paris GPS; no personal media","license":"MIT","container":type])
}
let movie = destination.appendingPathComponent("paris.mov")
guard !FileManager.default.fileExists(atPath:movie.path) else { fatalError("Movie fixture exists") }
let writer = try AVAssetWriter(outputURL:movie,fileType:.mov)
let creation = AVMutableMetadataItem(); creation.identifier = .quickTimeMetadataCreationDate; creation.value = "2024-01-02T03:04:05+02:00" as NSString; creation.dataType = "com.apple.metadata.datatype.UTF-8"
let location = AVMutableMetadataItem(); location.identifier = .quickTimeMetadataLocationISO6709; location.value = "+48.8566+002.3522/" as NSString; location.dataType = "com.apple.metadata.datatype.UTF-8"
writer.metadata = [creation,location]
let input = AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:32,AVVideoHeightKey:32])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:32,kCVPixelBufferHeightKey as String:32])
writer.add(input)
guard writer.startWriting() else { throw writer.error! }
writer.startSession(atSourceTime:.zero)
for frame in 0..<2 {
    let deadline = Date().addingTimeInterval(15)
    while !input.isReadyForMoreMediaData && Date() < deadline { Thread.sleep(forTimeInterval:0.01) }
    guard input.isReadyForMoreMediaData else { fatalError("Video encoder readiness timed out") }
    var pixel:CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault,32,32,kCVPixelFormatType_32ARGB,nil,&pixel)
    let buffer = pixel!
    CVPixelBufferLockBaseAddress(buffer,[])
    memset(CVPixelBufferGetBaseAddress(buffer),frame == 0 ? 80:160,CVPixelBufferGetDataSize(buffer))
    CVPixelBufferUnlockBaseAddress(buffer,[])
    guard adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(frame),timescale:1)) else { throw writer.error! }
}
writer.endSession(atSourceTime:CMTime(value:2,timescale:1)); input.markAsFinished()
let done = DispatchSemaphore(value:0)
writer.finishWriting { done.signal() }
guard done.wait(timeout:.now()+30) == .success, writer.status == .completed else { fatalError("Video fixture generation failed: \(String(describing: writer.error))") }
entries.append(["id":"paris.mov","sha256":SHA256.hash(data:try Data(contentsOf:movie)).map {String(format:"%02x",$0)}.joined(),"origin":"Generated two-frame H264 movie; synthetic Paris GPS; no personal media","license":"MIT","container":"MOV"])
let manifest:[String:Any] = ["schema":1,"fixtures":entries,"expectedCaptureInstant":"2024-01-02T01:04:05Z","expectedCountryCode":"FR","note":"Synthetic baseline fixtures do not qualify genuine Apple HDR/depth/Live Photo or camera RAW variants."]
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:destination.appendingPathComponent("manifest.json"))
print("Generated \(entries.count) synthetic fixtures.")
