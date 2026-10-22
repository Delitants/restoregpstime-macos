import Foundation

public struct PlaceQuery:Codable,Hashable,Sendable {
    public let latitude:Double,longitude:Double,maxDistanceKM:Double
    public let limit:Int
    public init(latitude:Double,longitude:Double,maxDistanceKM:Double=25,limit:Int=3) { self.latitude=latitude;self.longitude=longitude;self.maxDistanceKM=maxDistanceKM;self.limit=limit }
}
public struct PlaceQueryDefaults:Codable,Equatable,Sendable {
    public var maxDistanceKM:Double=25
    public var limit:Int=3
    public init() {}
}
public struct PlaceCorrection:Codable,Equatable,Sendable {
    public let city:String,region:String,country:String,countryCode:String
    public init(city:String,region:String="",country:String,countryCode:String="") { self.city=city;self.region=region;self.country=country;self.countryCode=countryCode }
}
