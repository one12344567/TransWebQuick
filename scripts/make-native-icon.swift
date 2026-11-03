import AppKit
import Foundation
let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
let variants:[(String,Int)]=[("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)]
for (name,size) in variants {
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
    let scale=CGFloat(size)/1024;let transform=AffineTransform(scale:scale);(transform as NSAffineTransform).concat()
    let shape=NSBezierPath(roundedRect:NSRect(x:100,y:100,width:824,height:824),xRadius:190,yRadius:190)
    NSGraphicsContext.saveGraphicsState()
    let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.22);shadow.shadowBlurRadius=25;shadow.shadowOffset=NSSize(width:0,height:-12);shadow.set()
    NSColor(red:0.16,green:0.27,blue:0.23,alpha:1).setFill();shape.fill();NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting:NSColor(red:0.35,green:0.52,blue:0.40,alpha:1),ending:NSColor(red:0.12,green:0.25,blue:0.21,alpha:1))!.draw(in:shape,angle:-65)
    let glyph="P" as NSString
    glyph.draw(at:NSPoint(x:310,y:205),withAttributes:[.font:NSFont.systemFont(ofSize:580,weight:.semibold),.foregroundColor:NSColor(red:0.96,green:0.98,blue:0.92,alpha:1)])
    for (y,width,alpha) in [(220.0,235.0,0.9),(166.0,140.0,0.45)] {
        let path=NSBezierPath();path.move(to:NSPoint(x:512-width/2,y:y));path.line(to:NSPoint(x:512+width/2,y:y));path.lineWidth=17;path.lineCapStyle = .round
        NSColor.white.withAlphaComponent(alpha).setStroke();path.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
}
