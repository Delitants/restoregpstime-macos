import Foundation

struct RAWIntegrity {
    func signature(_ reader:BoundedMediaReader,profile:ContainerProfile) throws -> MediaIntegritySignature {
        throw RestoreError(.unsupported,"\(profile.identifier) remains read-only until a model/container profile proves every image-bearing RAW extent. A generic TIFF/BMFF hash does not qualify a camera RAW variant.")
    }
}
