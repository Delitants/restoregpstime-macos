import Foundation

struct LegacyFinderInfo {
    let data:Data
    init(_ data:Data?) {self.data=data ?? Data(repeating:0,count:32)}
    func applying(_ mutations:[FinderMutation]) throws -> Data {
        guard data.count==32 else {throw RestoreError(.unsupported,"FinderInfo must contain exactly 32 bytes.")}
        var result=data
        for mutation in mutations {
            switch mutation {
            case .creator(let code),.fileType(let code):
                guard code.count==4 else {throw RestoreError(.invalidInput,"Legacy creator/type codes require exactly four bytes.")}
                let start:Int;if case .creator=mutation {start=4} else {start=0}
                result.replaceSubrange(start..<start+4,with:code)
            case .label(let value):
                guard (0...7).contains(value) else {throw RestoreError(.invalidInput,"Finder labels range from zero to seven.")}
                result[9]=(result[9]&0xf1)|UInt8(value<<1)
            case .extensionHidden(let value):result[9]=value ? result[9]|0x10:result[9]&0xef
            default:break
            }
        }
        return result
    }
}
