import CoreGraphics
import Foundation

/// A single stationary click may fire once. Dragging, multi-clicks and long holds never qualify.
public struct PressGesture: Sendable {
    public var threshold: Float = 350
    private var origin: CGPoint?
    private var began: Double = 0
    private var fired: Double = -.infinity
    public init() {}
    public mutating func down(at point:CGPoint, clicks:Int, time:Double) {
        origin = clicks == 1 ? point:nil; began=time
    }
    public mutating func up() {origin=nil}
    public mutating func move(to point:CGPoint) {
        if let origin, hypot(point.x-origin.x,point.y-origin.y)>7 {self.origin=nil}
    }
    public mutating func pressure(_ value:Float, time:Double) -> CGPoint? {
        guard let point=origin else{return nil}
        guard time>=began, time-began<0.65 else {origin=nil;return nil}
        guard value.isFinite, value>=threshold, value<10000, time-fired>0.8 else{return nil}
        origin=nil;fired=time;return point
    }
}
