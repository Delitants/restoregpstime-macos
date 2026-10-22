import Foundation

public protocol Clock:Sendable { func now() -> Date }
public struct SystemClock:Clock { public init() {};public func now()->Date { Date() } }
public struct FixedClock:Clock { public let value:Date;public init(_ value:Date) { self.value=value };public func now()->Date { value } }
