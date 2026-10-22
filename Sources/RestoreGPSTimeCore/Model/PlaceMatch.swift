import Foundation

public enum PlaceOrigin:String,Codable,Sendable { case database,manual }
public struct PlaceMatch:Codable,Equatable,Sendable {
    public let city:String,region:String,country:String,countryCode:String
    public let recordID:String,databaseIdentity:String
    public let distanceKM:Double?
    public let origin:PlaceOrigin
    public var displayName:String { [city,country].filter {!$0.isEmpty}.joined(separator:", ") }
    public init(city:String,region:String="",country:String,countryCode:String="",recordID:String="manual",databaseIdentity:String="manual",distanceKM:Double?=nil,origin:PlaceOrigin = .manual) {
        self.city=city;self.region=region;self.country=country;self.countryCode=countryCode;self.recordID=recordID;self.databaseIdentity=databaseIdentity;self.distanceKM=distanceKM;self.origin=origin
    }
}
