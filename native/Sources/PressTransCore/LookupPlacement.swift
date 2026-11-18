import CoreGraphics

/// AppKit screen coordinates. Choose the side once so a streaming or expanding
/// lookup keeps its pointer attached to the same word.
public struct LookupPlacement {
    public static let minimumBodyHeight: CGFloat = 154
    public static let expandedBodyLimit: CGFloat = 560
    private static let margin: CGFloat = 12
    private static let wordGap: CGFloat = 6

    private let anchor: CGRect
    private let screen: CGRect
    private let tip: CGFloat
    public let below: Bool
    public let maximumBodyHeight: CGFloat

    public init(anchor: CGRect, screen: CGRect, tip: CGFloat) {
        self.anchor = anchor
        self.screen = screen
        self.tip = tip
        let screenLimit = max(1, screen.height - 40)
        guard tip > 0 else {
            below = true
            maximumBodyHeight = screenLimit
            return
        }

        let clearance = Self.margin + Self.wordGap + tip
        let lower = anchor.minY - screen.minY - clearance
        let upper = screen.maxY - anchor.maxY - clearance
        below = lower >= min(Self.expandedBodyLimit, screenLimit) || lower >= upper
        let room = below ? lower : upper
        // A selection can span nearly the entire screen. In that case keep the
        // controls usable, even if the panel must overlap part of the selection.
        maximumBodyHeight = room >= Self.minimumBodyHeight ? min(room, screenLimit) : screenLimit
    }

    public func frame(bodyHeight: CGFloat) -> CGRect {
        let height = min(bodyHeight, maximumBodyHeight) + tip
        let y = below ? anchor.minY - Self.wordGap - height : anchor.maxY + Self.wordGap
        let width: CGFloat = 380
        return CGRect(
            x: min(max(anchor.midX - width / 2, screen.minX + Self.margin), screen.maxX - Self.margin - width),
            y: min(max(y, screen.minY + Self.margin), screen.maxY - Self.margin - height),
            width: width, height: height
        )
    }
}
