import CoreGraphics
import PressTransCore

func checkLookupPlacement() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    func verify(_ word: CGRect, on screen: CGRect, below: Bool, fullHeight: Bool) {
        let placement = LookupPlacement(anchor: word, screen: screen, tip: 10)
        precondition(placement.below == below)
        let heights = Array(stride(from: 154, through: 560, by: 2))
        for height in heights + heights.reversed() {
            let frame = placement.frame(bodyHeight: CGFloat(height))
            precondition(screen.insetBy(dx: 12, dy: 12).contains(frame))
            precondition(!frame.intersects(word))
            let gap = below ? word.minY - frame.maxY : frame.minY - word.maxY
            precondition(abs(gap - 6) < 0.001)
        }
        let expanded = placement.frame(bodyHeight: 560)
        precondition((expanded.height == 570) == fullHeight)
        precondition(expanded.height >= 164)
    }

    verify(CGRect(x: 100, y: 200, width: 40, height: 18), on: screen, below: false, fullHeight: true)
    verify(CGRect(x: 50, y: 600, width: 40, height: 18), on: screen, below: true, fullHeight: true)
    verify(CGRect(x: 100, y: 425, width: 40, height: 18), on: screen, below: false, fullHeight: false)
    let second = CGRect(x: -1440, y: -250, width: 1440, height: 900)
    for x in [second.minX, second.maxX - 36] {
        verify(CGRect(x: x, y: second.minY, width: 36, height: 19), on: second, below: false, fullHeight: true)
        verify(CGRect(x: x, y: second.maxY - 19, width: 36, height: 19), on: second, below: true, fullHeight: true)
    }
    let tallSelection = LookupPlacement(anchor: screen.insetBy(dx: 120, dy: 64), screen: screen, tip: 10)
    precondition(screen.insetBy(dx: 12, dy: 12).contains(tallSelection.frame(bodyHeight: 560)))
    precondition(tallSelection.frame(bodyHeight: 154).height == 164)
    let manual = LookupPlacement(anchor: CGRect(x: 300, y: 200, width: 0, height: 0), screen: screen, tip: 0)
    precondition(manual.below && manual.frame(bodyHeight: 560).height == 560)
    print("Lookup placement checks passed: anchored expansion and reversal, screen edges, external display, tall selections, manual lookup")
}
