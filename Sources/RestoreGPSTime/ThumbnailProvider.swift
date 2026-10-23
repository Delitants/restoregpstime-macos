import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct ThumbnailRequest:Hashable {
    let url:URL
    let size:ThumbnailSize
    // Supplied from the already imported snapshot; no remote stat on the UI thread.
    let revision:String
    fileprivate var cacheKey:NSString {"\(url.standardizedFileURL.path)\u{0}\(size.rawValue)\u{0}\(revision)" as NSString}
}
final class ThumbnailResult {
    let image:NSImage?
    init(image:NSImage?) {self.image=image}
}

/// Owns only visible requests. Cancelled synchronous decoders still occupy their queue
/// slots until they return, so rapid scrolling can never create extra decoding workers.
@MainActor final class ThumbnailProvider {
    typealias Renderer = @Sendable (ThumbnailRequest,@escaping @Sendable ()->Bool)->NSImage?
    var onChange:(()->Void)?
    private let queue=OperationQueue()
    private let cache=NSCache<NSString,ThumbnailResult>()
    private let renderer:Renderer
    private var operations=[ThumbnailRequest:ThumbnailRenderOperation]()
    private var visible=Set<ThumbnailRequest>()
    init(renderer:Renderer?=nil) {
        self.renderer=renderer ?? {request,cancelled in Self.render(request,isCancelled:cancelled)}
        queue.name="RestoreGPSTime.visible-thumbnails";queue.maxConcurrentOperationCount=2
        queue.qualityOfService = .userInitiated
        cache.countLimit=256;cache.totalCostLimit=64*1024*1024
    }
    deinit {queue.cancelAllOperations()}
    func cachedResult(for request:ThumbnailRequest)->ThumbnailResult? {cache.object(forKey:request.cacheKey)}
    func setVisible(_ requests:[ThumbnailRequest]) {
        visible=Set(requests.filter {$0.size != .off})
        for (request,operation) in operations where !visible.contains(request) {
            operation.cancel();operations.removeValue(forKey:request)
        }
        for request in requests where visible.contains(request) && operations[request] == nil && cachedResult(for:request) == nil {
            let operation=ThumbnailRenderOperation(request:request,renderer:renderer)
            operation.didRender={[weak self,weak operation] image in
                Task {@MainActor [weak self,weak operation] in
                    guard let self,let operation,self.operations[request] === operation else {return}
                    self.operations.removeValue(forKey:request)
                    guard !operation.isCancelled,self.visible.contains(request) else {return}
                    let pixels=Int(request.size.points*2)
                    self.cache.setObject(ThumbnailResult(image:image),forKey:request.cacheKey,cost:image == nil ? 1:pixels*pixels*4)
                    self.onChange?()
                }
            }
            operations[request]=operation;queue.addOperation(operation)
        }
    }
    nonisolated private static func render(_ request:ThumbnailRequest,isCancelled:@escaping @Sendable ()->Bool)->NSImage? {
        guard !isCancelled(),request.size != .off else {return nil}
        let pixels=request.size.points*2
        // ImageIO recognizes file signatures directly. Launch Services may return a
        // dynamic UTType even for PNG in a helper/test process, so an extension-based
        // image gate would incorrectly discard otherwise supported photos.
        if let source=CGImageSourceCreateWithURL(request.url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary) {
            guard !isCancelled(),let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:pixels,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true] as CFDictionary),!isCancelled() else {return nil}
            return NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height))
        }
        guard !isCancelled() else {return nil}
        let type=UTType(filenameExtension:request.url.pathExtension)
        if type?.conforms(to:.movie) == true || type?.conforms(to:.video) == true || ["mov","mp4","m4v","avi","mts","m2ts"].contains(request.url.pathExtension.lowercased()) {
            let generator=AVAssetImageGenerator(asset:AVURLAsset(url:request.url))
            generator.appliesPreferredTrackTransform=true;generator.maximumSize=NSSize(width:pixels,height:pixels)
            guard !isCancelled(),let image=try? generator.copyCGImage(at:.zero,actualTime:nil),!isCancelled() else {return nil}
            return NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height))
        }
        return nil
    }
}

private final class ThumbnailRenderOperation:Operation,@unchecked Sendable {
    let request:ThumbnailRequest
    let renderer:ThumbnailProvider.Renderer
    var didRender:((NSImage?)->Void)?
    init(request:ThumbnailRequest,renderer:@escaping ThumbnailProvider.Renderer) {self.request=request;self.renderer=renderer}
    override func main() {
        guard !isCancelled else {return}
        autoreleasepool {
            let image=renderer(request,{[weak self] in self?.isCancelled ?? true})
            didRender?(image)
        }
    }
}
