import AppKit

enum PressIcon {
    static func menuImage()->NSImage {
        let image=NSImage(size:NSSize(width:20,height:20),flipped:false){_ in
            NSColor.black.setStroke();NSColor.black.setFill()
            let pad=NSBezierPath(roundedRect:NSRect(x:7,y:8,width:6,height:9),xRadius:3,yRadius:3);pad.fill()
            let wave=NSBezierPath();wave.move(to:NSPoint(x:3,y:8));wave.curve(to:NSPoint(x:17,y:8),controlPoint1:NSPoint(x:1,y:0),controlPoint2:NSPoint(x:19,y:0));wave.lineWidth=1.5;wave.lineCapStyle = .round;wave.stroke()
            return true
        }
        image.isTemplate=true;image.accessibilityDescription="PressTrans";return image
    }
}
