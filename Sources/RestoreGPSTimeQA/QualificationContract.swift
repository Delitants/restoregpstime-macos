import Foundation

public enum GateStatus:String,Codable,Sendable {case pass,fail,missing}
public struct QualificationGate:Codable,Sendable,Equatable {
    public let id:String,status:GateStatus,detail:String
    public init(_ id:String,_ status:GateStatus,_ detail:String) {self.id=id;self.status=status;self.detail=detail}
}
public struct QualificationHost:Codable,Sendable,Equatable {
    public let processArchitecture:String,hardwareARM:Bool?,translated:Bool?,osMajor:Int,osVersion:String,osBuild:String
    public init(processArchitecture:String,hardwareARM:Bool?,translated:Bool?,osMajor:Int,osVersion:String,osBuild:String) {self.processArchitecture=processArchitecture;self.hardwareARM=hardwareARM;self.translated=translated;self.osMajor=osMajor;self.osVersion=osVersion;self.osBuild=osBuild}
    public func isNative(architecture:String,osMajor:Int?=nil)->Bool {
        guard translated==false,let hardwareARM,processArchitecture==architecture,osMajor==nil || osMajor==self.osMajor else {return false}
        return architecture=="arm64" ? hardwareARM:(architecture=="x86_64" && !hardwareARM)
    }
}
public struct QualificationResult:Codable,Sendable {
    public let schema:Int,sourceCommit:String,appHash:String,hostLabel:String,host:QualificationHost,gates:[QualificationGate]
    public var stableReady:Bool {
        guard schema==1,sourceCommit.range(of:"^[0-9a-f]{40}$",options:.regularExpression) != nil,appHash.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil,Set(gates.map(\.id)).count==gates.count else {return false}
        let byID=Dictionary(uniqueKeysWithValues:gates.map {($0.id,$0.status)})
        return Self.requiredGates.allSatisfy {byID[$0] == .pass}
    }
    public static let requiredGates=["source-identity","runtime","fixture-manifest","baseline-regression","genuine-formats","large-video","volumes","native-arm64-macos13","native-x86_64-macos13","native-arm64-current","native-x86_64-current","native-ui","finder-services-droplets","finder-isolated-login","instruments-10000","relocated-offline","developer-id","notarization"]
    public init(sourceCommit:String,appHash:String,hostLabel:String,host:QualificationHost,gates:[QualificationGate]) {schema=1;self.sourceCommit=sourceCommit;self.appHash=appHash;self.hostLabel=hostLabel;self.host=host;self.gates=gates}
}

// The supplied regression source alone does not establish candidate identity.
enum RegressionBinding {
    static func accepts(sourceIdentityPassed:Bool,candidateArchitecture:String,processArchitecture:String,host:QualificationHost)->Bool {sourceIdentityPassed && candidateArchitecture==processArchitecture && host.isNative(architecture:candidateArchitecture)}
}
