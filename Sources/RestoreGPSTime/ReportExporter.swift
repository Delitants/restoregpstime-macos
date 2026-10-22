import Foundation
import RestoreGPSTimeCore

struct ReportExporter {
    func export(_ report:BatchReport,to url:URL,includeCoordinates:Bool=false) throws {
        let entries=report.plan.groups.flatMap {group -> [[String:Any]] in
            let result=report.results.first {$0.groupID==group.id}
            return group.items.map {item in
                var changes=[String:[String:Any]]()
                for mutation in (try? MetadataMutationDriver.expandedTags(item.mutation,document:item.metadata)) ?? item.mutation.tags {
                    let id:TagID,value:TagValue?
                    switch mutation {case .set(let key,let tag):id=key;value=tag;case .remove(let key):id=key;value=nil}
                    if !includeCoordinates && Self.coordinateField(id.rawValue) {continue}
                    changes[id.rawValue]=value.map {["operation":"set","value":Self.json($0)]} ?? ["operation":"remove"]
                }
                var row:[String:Any]=["groupID":group.id.uuidString,"sourceName":item.source.snapshot.url.lastPathComponent,"sourcePath":item.source.snapshot.url.path,"outputPath":item.name.finalURL.path,"status":result?.status.rawValue ?? group.eligibility.rawValue,"messages":result?.errors ?? group.blockingReasons,"creationBefore":Self.date(item.source.snapshot.creationDate,exact:item.source.snapshot.creationTimestamp),"modificationBefore":Self.date(item.source.snapshot.modificationDate,exact:item.source.snapshot.modificationTimestamp),"metadataChanges":changes]
                row["operations"]=["removeGPS":item.mutation.removeGPS,"stripMetadata":item.mutation.stripMetadata,"dateNotes":item.mutation.dates?.notes ?? []]
                if let recovery=result?.recoveryURL {row["recoveryURL"]=recovery.path}
                if let date=item.mutation.dates?.creationDate {row["plannedCreation"]=Self.date(date,exact:item.mutation.dates?.creationTimestamp)}
                if let date=item.mutation.dates?.modificationDate {row["plannedModification"]=Self.date(date,exact:item.mutation.dates?.modificationTimestamp)}
                if let date=item.mutation.dates?.embeddedDate {row["plannedCapture"]=Self.date(date,exact:item.mutation.dates?.embeddedTimestamp)}
                if let place=item.place {row["placeName"]=place.displayName;row["placeOrigin"]=place.origin.rawValue;if let km=place.distanceKM {row["nearestPlaceDistanceKM"]=km}}
                if includeCoordinates,let coordinates=try? MetadataCoordinates.read(item.metadata) {row["latitude"]=coordinates.0;row["longitude"]=coordinates.1}
                return row
            }
        }
        let data:Data
        switch url.pathExtension.lowercased() {
        case "json":
            let object:[String:Any]=["schema":1,"application":"RestoreGPSTime","batchID":report.batchID.uuidString,"startedAt":Self.date(report.startedAt),"finishedAt":Self.date(report.finishedAt),"saveMode":report.plan.options.mode.rawValue,"cancelled":report.cancelled,"includesCoordinateFields":includeCoordinates,"recoveryRoot":report.plan.options.recoveryRoot?.path ?? "","entries":entries]
            data=try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys])
        case "csv":
            var columns=["sourceName","sourcePath","outputPath","status","creationBefore","plannedCreation","modificationBefore","plannedModification","plannedCapture","placeName","messages","metadataChanges","operations","recoveryURL"]
            if includeCoordinates {columns += ["latitude","longitude"]}
            var lines=[columns.map(Self.cell).joined(separator:",")]
            for row in entries {lines.append(try columns.map {key -> String in
                guard let value=row[key] else {return Self.cell("")}
                let text:String
                if let string=value as? String {text=string}
                else if JSONSerialization.isValidJSONObject(value) {text=String(decoding:try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]),as:UTF8.self)}
                else {text=String(describing:value)}
                return Self.cell(text)
            }.joined(separator:","))}
            data=Data((lines.joined(separator:"\r\n")+"\r\n").utf8)
        default:throw RestoreError(.invalidInput,"Choose a JSON or CSV report filename.")
        }
        try data.write(to:url,options:.atomic)
    }
    private static func coordinateField(_ name:String)->Bool {
        let value=name.lowercased()
        return value.contains("gps") || value.contains("latitude") || value.contains("longitude") || value.contains("locationiso6709") || value.contains("locationinformation")
    }
    private static func json(_ value:TagValue)->Any {
        switch value {
        case .string(let text):return text
        case .integer(let number):return number
        case .real(let number):return number
        case .bool(let flag):return flag
        case .array(let values):return values.map(json)
        case .object(let object):return object.mapValues(json)
        case .null:return NSNull()
        }
    }
    private static func date(_ value:Date,exact:FileTimestamp?=nil)->String {
        let formatter=ISO8601DateFormatter();formatter.timeZone=TimeZone(secondsFromGMT:0)
        if let exact {
            formatter.formatOptions=[.withInternetDateTime]
            let base=formatter.string(from:Date(timeIntervalSince1970:Double(exact.seconds)))
            guard base.hasSuffix("Z") else {return "epoch seconds \(exact.seconds), nanoseconds \(exact.nanoseconds)"}
            return String(base.dropLast())+"."+String(format:"%09d",exact.nanoseconds)+"Z"
        }
        formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return formatter.string(from:value)
    }
    private static func cell(_ value:String)->String {
        let trimmed=value.drop(while:{$0==" "})
        let dangerous=trimmed.first.map {"=+-@\t\r\n".contains($0)} ?? false
        let text=(dangerous ? "'":"")+value
        return "\""+text.replacingOccurrences(of:"\"",with:"\"\"")+"\""
    }
}
