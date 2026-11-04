import Foundation

/// Exact critically damped motion: no overshoot from rest, and continuous velocity on reversal.
/// omega=24 reaches ~95% in 200 ms; the small remaining tail settles without a hard stop.
public struct DisclosureMotion {
    public private(set) var value:Double
    public private(set) var velocity:Double=0
    public private(set) var target:Double
    public init(_ value:Double) {self.value=value;target=value}
    public mutating func retarget(_ target:Double) {self.target=target}
    public mutating func snap(_ value:Double) {self.value=value;target=value;velocity=0}
    public var settled:Bool {abs(value-target)<0.001 && abs(velocity)<0.02}
    public mutating func advance(_ seconds:Double) {
        guard seconds.isFinite,seconds>0 else{return}
        let omega=24.0,offset=value-target,c=velocity+omega*offset,decay=exp(-omega*seconds)
        value=target+(offset+c*seconds)*decay
        velocity=(velocity-omega*c*seconds)*decay
        if settled {snap(target)}
    }
}
