import Foundation

// Only new, explicitly selected sidecars use this no-media profile. Existing XMP is read-only.
struct XMPIntegrity {
    func signature(_ reader:BoundedMediaReader) throws -> MediaIntegritySignature {
        guard reader.size<=16_777_216 else {throw RestoreError(.unsupported,"XMP exceeds the bounded packet size.")}
        var data=Data(),offset:UInt64=0
        while offset<reader.size {let count=Int(min(reader.size-offset,1_048_576));data.append(try reader.bytes(offset,count));offset+=UInt64(count)}
        guard let text=String(data:data,encoding:.utf8),!text.contains("<!DOCTYPE"),!text.contains("<!ENTITY") else {throw RestoreError(.unsupported,"XMP must be UTF-8 without DTD or entity declarations.")}
        let document:XMLDocument
        do {document=try XMLDocument(data:data,options:[.nodeLoadExternalEntitiesNever])} catch {throw RestoreError(.malformedMetadata,"Invalid XMP XML packet.")}
        guard let root=document.rootElement() else {throw RestoreError(.malformedMetadata,"XMP has no document element.")}
        let rdfURI="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
        let isRDF=root.localName=="RDF" && root.uri==rdfURI
        guard isRDF || root.localName=="xmpmeta" && root.uri=="adobe:ns:meta/" else {throw RestoreError(.unsupported,"The XMP packet has no qualified RDF root.")}
        if !isRDF {
            let elements=(root.children ?? []).compactMap {$0 as? XMLElement}
            guard elements.count==1,elements[0].localName=="RDF",elements[0].uri==rdfURI else {throw RestoreError(.unsupported,"The XMP wrapper must contain exactly one RDF document.")}
        }
        var count=0
        func visit(_ element:XMLElement,depth:Int) throws {
            count+=1
            guard depth<=64,count<=100000 else {throw RestoreError(.unsupported,"XMP nesting or node count exceeds the bounded profile.")}
            for child in element.children ?? [] {if let node=child as? XMLElement {try visit(node,depth:depth+1)}}
        }
        try visit(root,depth:0)
        var digest=MediaDigest();digest.field("validated new XMP RDF sidecar; no encoded media")
        return digest.signature(profile:"XMP",validator:"xmp-new-sidecar-v1")
    }
}
