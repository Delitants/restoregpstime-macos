import Foundation

public actor PlaceCorrectionStore {
    private var corrections=[String:PlaceCorrection]()
    public init() {}
    public func set(_ correction:PlaceCorrection?,for sourceKeys:[String]) {
        for key in sourceKeys { corrections[key]=correction }
    }
    public func correction(for sourceKey:String)->PlaceCorrection? { corrections[sourceKey] }
    public func clear() { corrections.removeAll() }
}
