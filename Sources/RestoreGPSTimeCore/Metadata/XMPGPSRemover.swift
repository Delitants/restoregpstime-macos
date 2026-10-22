import Foundation

struct XMPGPSRemover {
    func clean(_ data:Data) throws -> Data? {
        guard data.count<=16_777_216,let text=String(data:data,encoding:.utf8) else {throw RestoreError(.unsupported,"Only bounded UTF-8 XMP packets are qualified for selective location removal.")}
        guard !text.contains("<!DOCTYPE"),!text.contains("<!ENTITY") else {throw RestoreError(.unsupported,"XMP documents with DTD/entity declarations remain read-only.")}
        let document=try XMLDocument(data:data,options:[.nodePreserveAll,.nodeLoadExternalEntitiesNever])
        var changed=false,nodes=0
        func geographic(_ node:XMLNode,owner:XMLElement)->Bool {
            let name=node.localName ?? node.name?.split(separator:":").last.map(String.init) ?? ""
            let uri=node.uri ?? node.name.flatMap {owner.resolveNamespace(forName:$0)?.stringValue} ?? ""
            switch uri {
            case "http://ns.adobe.com/exif/1.0/":return MetadataStripProfiles.gpsFields.contains(name)
            case "http://ns.adobe.com/photoshop/1.0/":return ["City","State","Country"].contains(name)
            case "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/":return ["Location","CountryCode"].contains(name)
            default:return false
            }
        }
        func visit(_ element:XMLElement,depth:Int) throws {
            nodes+=1;guard depth<=64,nodes<=100000 else {throw RestoreError(.unsupported,"XMP structure exceeds the bounded removal profile.")}
            for attribute in element.attributes ?? [] where geographic(attribute,owner:element) {attribute.detach();changed=true}
            for child in element.children ?? [] {
                guard let value=child as? XMLElement else {continue}
                if geographic(value,owner:element) {value.detach();changed=true} else {try visit(value,depth:depth+1)}
            }
        }
        guard let root=document.rootElement() else {throw RestoreError(.malformedMetadata,"XMP has no document element.")}
        try visit(root,depth:0)
        if !changed {return nil}
        return Data(root.xmlString(options:.nodePreserveAll).utf8)
    }
}
