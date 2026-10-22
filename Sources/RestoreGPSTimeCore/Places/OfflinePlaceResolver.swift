import Foundation

public actor OfflinePlaceResolver {
    private let paths:RuntimePaths
    private var cache=[PlaceQuery:[PlaceMatch]]()
    private var dataID:SourceID?
    private var identity=""
    private let limiter=HelperLimiter.shared
    public init(paths:RuntimePaths) { self.paths=paths }
    public func lookup(_ query:PlaceQuery) async throws -> [PlaceMatch] {
        guard query.latitude.isFinite,query.longitude.isFinite,(-90...90).contains(query.latitude),(-180...180).contains(query.longitude),query.maxDistanceKM.isFinite,query.maxDistanceKM>0,query.maxDistanceKM<=20050,(1...10).contains(query.limit) else { throw RestoreError(.invalidInput,"Invalid coordinates, match distance, or candidate count.") }
        guard FileManager.default.fileExists(atPath:paths.database.path) else { throw RestoreError(.runtimeUnavailable,"The bundled offline place database is missing.") }
        let snapshot=try FileIdentityReader().snapshot(at:paths.database)
        if snapshot.id != dataID {
            identity="ExifTool 13.59 / GeoNames / Geolocation.dat SHA-256 "+(try FileIdentityReader().fingerprint(at:paths.database).contentHash)
            dataID=snapshot.id;cache.removeAll()
        }
        if let saved=cache[query] { return saved }
        let locale=Locale(identifier:"en_US_POSIX")
        let coordinates=String(format:"%.8f,%.8f",locale:locale,query.latitude,query.longitude)
        let distance=String(format:"%.8f",locale:locale,query.maxDistanceKM)
        let args=["-j","-G3:1","-a","-n","-api","Geolocation=\(coordinates),num=\(query.limit)","-api","GeolocMaxDist=\(distance)"]
        await limiter.acquire()
        let result:ProcessResult
        do { result=try await ProcessRunner().run(executable:paths.perl,arguments:paths.exifArguments(args),environment:paths.environment,timeout:30) }
        catch { await limiter.release();throw error }
        await limiter.release()
        guard result.exitStatus==0 else { throw RestoreError(.processFailed,"Offline lookup failed: "+String(decoding:result.stderr,as:UTF8.self)) }
        guard try FileIdentityReader().snapshot(at:paths.database).id==snapshot.id else { throw RestoreError(.conflict,"The place database changed during lookup. Preview again.") }
        let document=try MetadataDecoder().decode(result.stdout)
        if let error=document.tags["ExifTool:Error"]?.text { throw RestoreError(.processFailed,error) }
        var groups=[Int:[String:TagValue]]()
        for (key,value) in document.tags {
            let parts=key.split(separator:":").map(String.init)
            guard let tag=parts.last,tag.hasPrefix("Geolocation") else { continue }
            let index=parts.first?.hasPrefix("Doc")==true ? Int(parts[0].dropFirst(3)) ?? 0:0
            groups[index,default:[:]][tag]=value
        }
        var matches=[PlaceMatch]()
        for index in groups.keys.sorted() {
            let tags=groups[index]!
            guard let city=tags["GeolocationCity"]?.text,let country=tags["GeolocationCountry"]?.text,let km=tags["GeolocationDistance"]?.double,km<=query.maxDistanceKM else { continue }
            let code=tags["GeolocationCountryCode"]?.text ?? "",position=tags["GeolocationPosition"]?.text ?? ""
            let record=FileIdentityReader.hash(Data((identity+"|"+code+"|"+city+"|"+position).utf8))
            matches.append(.init(city:city,region:tags["GeolocationRegion"]?.text ?? "",country:country,countryCode:code,recordID:record,databaseIdentity:identity,distanceKM:km,origin:.database))
        }
        cache[query]=matches
        return matches
    }
    public func resolve(document:MetadataDocument,correction:PlaceCorrection?,queryDefaults:PlaceQueryDefaults=PlaceQueryDefaults()) async throws -> [PlaceMatch] {
        if let correction {
            let city=correction.city.trimmingCharacters(in:.whitespacesAndNewlines),country=correction.country.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !city.isEmpty || !country.isEmpty else { throw RestoreError(.invalidInput,"Enter a city or country for a manual place.") }
            return [.init(city:city,region:correction.region,country:country,countryCode:correction.countryCode,origin:.manual)]
        }
        let position=try MetadataCoordinates.read(document)
        return try await lookup(.init(latitude:position.0,longitude:position.1,maxDistanceKM:queryDefaults.maxDistanceKM,limit:queryDefaults.limit))
    }
}

public enum MetadataCoordinates {
    public static func read(_ document:MetadataDocument) throws -> (Double,Double) {
        var pairs=[(Double,Double)]()
        for group in ["GPS","Composite","XMP-exif"] {
            let latValue=document.tags[group+":GPSLatitude"],lonValue=document.tags[group+":GPSLongitude"]
            if latValue==nil && lonValue==nil { continue }
            guard let latitude=latValue?.double,let longitude=lonValue?.double else { throw RestoreError(.missingMetadata,"An existing GPS coordinate pair is incomplete or invalid.") }
            let lat=try signed(latitude,reference:document.tags[group+":GPSLatitudeRef"]?.text,positive:"N",negative:"S")
            let lon=try signed(longitude,reference:document.tags[group+":GPSLongitudeRef"]?.text,positive:"E",negative:"W")
            pairs.append((lat,lon))
        }
        for (key,value) in document.tags where key.hasSuffix(":GPSCoordinates") {
            if case .array(let items)=value,items.count>=2,let lat=items[0].double,let lon=items[1].double { pairs.append((lat,lon));continue }
            let text=value.text
            let regex=try NSRegularExpression(pattern:#"[+-]?\d+(?:\.\d+)?"#)
            let values=regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).compactMap { match->Double? in
                guard let range=Range(match.range,in:text) else {return nil};return Double(text[range])
            }
            guard values.count>=2 else { throw RestoreError(.missingMetadata,"Video GPS coordinates cannot be parsed.") }
            pairs.append((values[0],values[1]))
        }
        guard let first=pairs.first else { throw RestoreError(.missingMetadata,"No GPS coordinates are present. City names are not coordinate evidence.") }
        guard pairs.allSatisfy({$0.0.isFinite && $0.1.isFinite && (-90...90).contains($0.0) && (-180...180).contains($0.1)}) else { throw RestoreError(.invalidInput,"GPS coordinates are outside their valid range.") }
        guard pairs.allSatisfy({abs($0.0-first.0)<=0.000001 && abs($0.1-first.1)<=0.000001}) else { throw RestoreError(.conflict,"Different metadata groups contain conflicting GPS coordinates. Choose a manual place or correct the coordinates.") }
        return first
    }
    private static func signed(_ value:Double,reference:String?,positive:String,negative:String) throws -> Double {
        guard let reference else { return value }
        let ref=reference.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        guard ref==positive || ref==negative else { throw RestoreError(.invalidInput,"Invalid GPS hemisphere reference.") }
        if ref==positive && value<0 { throw RestoreError(.conflict,"GPS sign contradicts its hemisphere reference.") }
        return ref==negative ? -abs(value):value
    }
}
