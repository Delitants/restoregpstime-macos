import XCTest
@testable import RestoreGPSTimeCore

class NamingTestCase:CoreTestCase {
    func item(_ name:String,family:ContainerFamily = .photo,id:String?=nil,place:PlaceMatch?=PlaceMatch(city:"Paris",country:"France")) throws -> InspectedItem {
        let url=workspace.appendingPathComponent(name)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        if !FileManager.default.fileExists(atPath:url.path) { try Data("payload-\(name)".utf8).write(to:url) }
        return .init(snapshot:try FileIdentityReader().snapshot(at:url),metadata:.init(tags:id.map {["Apple:ContentIdentifier":.string($0)]} ?? [:],profile:.init(identifier:family == .video ? "MOV":"HEIC",family:family)),place:place)
    }
    func destination(_ name:String="output",rules:VolumeNamingRules=VolumeNamingRules()) throws -> DestinationContext {
        let root=workspace.appendingPathComponent(name);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        return .init(root:root,saveCopies:true,rules:rules)
    }
}
final class AssetGroupTests:NamingTestCase {
    func testLivePhotoAndSidecarShareBase() throws {
        let groups=try AssetGrouper().group(items:[item("IMG.HEIC",id:"pair"),item("IMG.MOV",family:.video,id:"pair"),item("IMG.xmp",family:.unknown)])
        XCTAssertEqual(groups.count,1);XCTAssertEqual(groups.first?.members.count,3)
        let names=try NameAllocator().reserve(groups:groups,destinations:destination()).map {$0.finalURL.deletingPathExtension().lastPathComponent}
        XCTAssertEqual(Set(names),["France - Paris - 0001"])
    }
    func testUnrelatedSameStemIsNotLivePhoto() throws {
        let groups=try AssetGrouper().group(items:[item("IMG.HEIC"),item("IMG.MOV",family:.video)])
        XCTAssertEqual(groups.count,2)
    }
    func testExplicitUnlinkOverridesIdentifiers() throws {
        let a=try item("A.HEIC",id:"pair"),b=try item("A.MOV",family:.video,id:"pair")
        var overrides=GroupOverrides();overrides.unlinkedSourceKeys=[a.snapshot.id.physicalKey]
        XCTAssertEqual(try AssetGrouper().group(items:[a,b],overrides:overrides).count,2)
    }
}
