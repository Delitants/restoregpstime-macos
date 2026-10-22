import Foundation
import Darwin
import RestoreGPSTimeCore

struct RecoveryBatch:Identifiable,Sendable {
    let batchID:UUID,createdAt:Date,groups:Int,incompleteGroups:Int,phases:[String]
    var id:UUID {batchID}
}
// A read-only catalogue: browsing never creates recovery folders or replays a write.
actor RecoveryBrowser {
    func scan(root:URL) throws -> [RecoveryBatch] {
        let fd=open(root.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        if fd<0 && errno==ENOENT {return []}
        guard fd>=0 else {throw failure("Open recovery folder")};defer {close(fd)}
        try checkDirectory(fd)
        var batches=[RecoveryBatch]()
        for name in try names(fd) {
            try Task.checkCancellation()
            guard let id=UUID(uuidString:name),name==id.uuidString else {continue}
            let batch=openat(fd,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
            guard batch>=0 else {throw failure("Open recovery batch")};defer {close(batch)}
            try checkDirectory(batch)
            let groups=openat(batch,"groups",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
            guard groups>=0 else {throw failure("Open recovery records")};defer {close(groups)}
            try checkDirectory(groups)
            var records=[RecoveryHeader]()
            for file in try names(groups) where file.hasSuffix(".json") {
                try Task.checkCancellation()
                let handleFD=openat(groups,file,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
                guard handleFD>=0 else {throw failure("Read recovery record")}
                let handle=FileHandle(fileDescriptor:handleFD,closeOnDealloc:true);defer {try? handle.close()}
                var state=stat()
                guard fstat(handleFD,&state)==0,state.st_mode & S_IFMT==S_IFREG,state.st_uid==getuid(),state.st_mode & 0o077==0,state.st_nlink==1,state.st_size<=67_108_864 else {throw failure("Unsafe recovery record")}
                let data=try handle.read(upToCount:67_108_865) ?? Data()
                guard data.count<=67_108_864 else {throw failure("Oversized recovery record")}
                let record=try JSONDecoder().decode(RecoveryHeader.self,from:data)
                guard record.schema==1,record.batchID==id,file==record.groupID.uuidString+".json" else {throw failure("Recovery record identity mismatch")}
                records.append(record)
            }
            guard let first=records.min(by:{$0.createdAt<$1.createdAt}) else {continue}
            batches.append(.init(batchID:id,createdAt:first.createdAt,groups:records.count,incompleteGroups:records.filter {$0.phase != .committed && $0.phase != .restored}.count,phases:Array(Set(records.map {$0.phase.rawValue})).sorted()))
        }
        return batches.sorted {a,b in
            if (a.incompleteGroups>0) != (b.incompleteGroups>0) {return a.incompleteGroups>0}
            return a.createdAt>b.createdAt
        }
    }
    private func names(_ fd:Int32) throws -> [String] {
        guard let directory=fdopendir(dup(fd)) else {throw failure("List recovery directory")};defer {closedir(directory)}
        var values=[String]()
        while let entry=readdir(directory) {
            let name=withUnsafePointer(to:&entry.pointee.d_name) {pointer in pointer.withMemoryRebound(to:CChar.self,capacity:Int(NAME_MAX)+1) {String(cString:$0)}}
            if name=="." || name==".." {continue}
            values.append(name)
            guard values.count<=100_000 else {throw failure("Recovery directory exceeds catalogue limit")}
        }
        return values.sorted()
    }
    private func checkDirectory(_ fd:Int32) throws {
        var value=stat()
        guard fstat(fd,&value)==0,value.st_uid==getuid(),value.st_mode & 0o022==0 else {throw failure("Recovery directory is not private to this account")}
    }
    private func failure(_ text:String)->RestoreError {.init(.invalidInput,text+". Choose the private recovery folder created by RestoreGPSTime.")}
}

private struct RecoveryHeader:Decodable {let schema:Int,batchID:UUID,groupID:UUID,createdAt:Date,phase:RecoveryPhase}
