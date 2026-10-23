import XCTest
@testable import RestoreGPSTime
@testable import RestoreGPSTimeCore

final class ComponentPreviewTests:AppTestCase {
    @MainActor func testLocationThenDatePreviewsRetainTheirOwnResultsAndComposeBoth() async throws {
        let input=try item(),model=AppModel(backend:FakeAppBackend(items:[input]))
        model.options.mode = .modifyInPlace;model.request.rename=NameTemplate()
        await model.importURLs([input.snapshot.url]);await model.preview(component:.places)
        XCTAssertEqual(model.rows.first?.proposedName,"France - Paris - 0001.jpg")
        XCTAssertNil(model.rows.first?.planned?.mutation.dates)
        XCTAssertFalse(model.canApply)
        XCTAssertEqual(model.pendingPreviewComponents,[.dates])
        await model.preview(component:.dates)
        XCTAssertEqual(model.rows.first?.proposedName,"France - Paris - 0001.jpg")
        XCTAssertEqual(model.rows.first?.planned?.mutation.dates?.creationDate,ISO8601DateFormatter().date(from:"2024-01-02T03:04:05Z"))
        XCTAssertTrue(model.canApply)
        XCTAssertEqual(model.plan?.request.rename.preserveOriginal,false)
        XCTAssertNotNil(model.plan?.request.dates)
        let unchanged=model.request;model.request=unchanged
        XCTAssertTrue(model.canApply,"A no-op binding write or tab navigation cannot invalidate the preview")
        model.request.dates?.shiftSeconds=3600
        XCTAssertFalse(model.canApply)
        XCTAssertEqual(model.rows.first?.proposedName,"France - Paris - 0001.jpg")
        XCTAssertEqual(model.pendingPreviewComponents,[.dates])
        await model.preview(component:.dates)
        XCTAssertTrue(model.canApply)
        XCTAssertEqual(model.rows.first?.planned?.mutation.dates?.creationDate,ISO8601DateFormatter().date(from:"2024-01-02T04:04:05Z"))
        XCTAssertEqual(model.rows.first?.proposedName,"France - Paris - 0001.jpg")
    }
    @MainActor func testDisabledDateSelectionDoesNotBlockLocationOnlyApply() async throws {
        let input=try item(validDate:false),model=AppModel(backend:FakeAppBackend(items:[input]))
        model.options.mode = .modifyInPlace;model.request.dates=nil;model.request.rename=NameTemplate()
        await model.importURLs([input.snapshot.url]);await model.preview(component:.places)
        XCTAssertTrue(model.canApply)
        XCTAssertEqual(model.rows.first?.proposedName,"France - Paris - 0001.jpg")
    }
    func testPreferencesRoundTripUserSettingsWithoutRetainingSourceSpecificState() throws {
        let suite="RestoreGPSTimeSettingsTests-"+UUID().uuidString,defaults=try XCTUnwrap(UserDefaults(suiteName:suite));defer {defaults.removePersistentDomain(forName:suite)}
        let store=AppPreferences(defaults:defaults)
        var request=OperationRequest();var date=DatePolicy();date.automaticTimeZone=true;date.timeZoneID="Europe/Madrid";request.dates=date;request.rename=NameTemplate();request.excludedSourceKeys=["old-file"];request.placeOverrides["old-file"] = .init(city:"Madrid",country:"Spain")
        var options=BatchOptions();options.mode = .modifyInPlace;options.backupMode = .metadata;options.outputRoot=workspace.appendingPathComponent("Copies");options.importRoots=[workspace]
        var discovery=DiscoveryOptions();discovery.recursive=true;discovery.includeHidden=true
        try store.save(request:request,options:options,discovery:discovery,appearance:2)
        let restored=try XCTUnwrap(store.load())
        XCTAssertEqual(restored.request.dates?.timeZoneID,"Europe/Madrid")
        XCTAssertFalse(restored.request.rename.preserveOriginal)
        XCTAssertTrue(restored.request.excludedSourceKeys.isEmpty);XCTAssertTrue(restored.request.placeOverrides.isEmpty)
        XCTAssertTrue(restored.options.importRoots.isEmpty)
        XCTAssertEqual(restored.options.backupMode,.metadata);XCTAssertEqual(restored.options.mode,.modifyInPlace)
        XCTAssertTrue(restored.discovery.recursive);XCTAssertTrue(restored.discovery.includeHidden);XCTAssertEqual(restored.appearance,2)
    }
}
