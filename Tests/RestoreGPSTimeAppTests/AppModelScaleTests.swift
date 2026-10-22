import XCTest
@testable import RestoreGPSTime
@testable import RestoreGPSTimeCore

final class AppModelScaleTests:XCTestCase {
    @MainActor func testFinalResultsStayResponsiveAndPreserveRows() async throws {try await check(count:10000,burst:false)}
    @MainActor func testBurstEventsStayResponsiveAndPreserveRows() async throws {try await check(count:10000,burst:true)}
    @MainActor private func check(count:Int,burst:Bool) async throws {
        let now=Date(),base=URL(fileURLWithPath:"/tmp/model-only-synthetic-fixtures"),identity=DependencyIdentity(engineHash:"test",databaseHash:"test",capabilityHash:"test")
        var items=[InspectedItem](),groups=[PlannedGroup]()
        for i in 0..<count {
            let sourceID=SourceID(device:1,inode:UInt64(i+1),size:0,modified:now,changed:now,linkCount:1,volumeID:"synthetic")
            let url=base.appendingPathComponent("\(i).jpg"),snapshot=FileSnapshot(url:url,id:sourceID,kind:.regular,creationDate:now,modificationDate:now,flags:0,permissions:0o600,ownerID:501,groupID:20,xattrHashes:[:],finderInfo:nil,aclText:nil)
            let metadata=MetadataDocument(tags:[:]),id=UUID();items.append(.init(snapshot:snapshot,metadata:metadata))
            let name=NameReservation(groupID:id,sourceKey:sourceID.physicalKey,originalURL:url,finalURL:url,sequence:nil,wasTruncated:false,needsTemporaryRename:false,blockingReason:nil)
            let item=PlannedItem(source:.init(snapshot:snapshot,contentHash:"synthetic"),metadata:metadata,resolution:nil,place:nil,name:name,mutation:MutationPlan(),capabilities:[:],destinationAnchor:nil,blockingReasons:[])
            groups.append(.init(id:id,evidence:"Model-only performance fixture",items:[item],eligibility:.eligible,blockingReasons:[]))
        }
        let plan=BatchPlan(optionsDigest:"synthetic",frozenNow:now,dependencies:identity,request:OperationRequest(),options:BatchOptions(),groups:groups)
        let model=AppModel(backend:ScaleBackend(items:items,plan:plan,burst:burst));await model.importURLs([base]);await model.preview()
        XCTAssertTrue(model.canApply)
        var done=false
        let heartbeat=Task { @MainActor in
            var longest:Double=0
            while !done {
                let tick=DispatchTime.now().uptimeNanoseconds
                try await Task.sleep(nanoseconds:1_000_000)
                longest=max(longest,Double(DispatchTime.now().uptimeNanoseconds-tick)/1e9)
            }
            return longest
        }
        await Task.yield()
        let start=DispatchTime.now().uptimeNanoseconds
        await model.applyPreview();done=true
        let longest=try await heartbeat.value
        let elapsed=Double(DispatchTime.now().uptimeNanoseconds-start)/1e9
        XCTAssertLessThan(longest,0.250,"Model event handling must not consume a 250ms main-actor slice; no media or file I/O is involved")
        XCTAssertEqual(model.rows.count,count);XCTAssertEqual(model.phase,.finished)
        XCTAssertEqual(model.rows.filter {$0.status=="failed"}.count,count/2)
        XCTAssertEqual(model.rows.filter {$0.issue=="Synthetic failure"}.count,count/2)
        print("Model-only \(count) rows; burst=\(burst); elapsed=\(elapsed)s; longest actor wait=\(longest)s; native Instruments acceptance is separate")
    }
}
private struct ScaleBackend:AppBackend {
    let items:[InspectedItem],plan:BatchPlan,burst:Bool
    func inspect(_ urls:[URL],options:DiscoveryOptions) async throws -> [InspectedItem] {items}
    func preview(items:[InspectedItem],request:OperationRequest,options:BatchOptions) async throws -> BatchPlan {plan}
    func execute(_ plan:BatchPlan) async -> AsyncStream<BatchEvent> {
        let results=plan.groups.enumerated().map {index,group in GroupResult(groupID:group.id,status:index%2==0 ? .committed:.failed,errors:index%2==0 ? []:["Synthetic failure"])}
        return AsyncStream {stream in
            if burst {for result in results {stream.yield(.progress(result.groupID,phase:"Synthetic progress"));stream.yield(.group(result))}}
            stream.yield(.finished(.init(plan:plan,startedAt:Date(),results:results,cancelled:false)));stream.finish()
        }
    }
    func cancel(_ id:UUID) async {}
    func restore(batchID:UUID,choice:RecoveryChoice) async throws -> RecoveryOutcome {.init(batchID:batchID,restored:[],conflicts:[])}
}
