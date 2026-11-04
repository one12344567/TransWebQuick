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
    NSGradient(starting:NSColor(red:0.97,green:0.98,blue:0.96,alpha:1),ending:NSColor(red:0.80,green:0.85,blue:0.82,alpha:1))!.draw(in:shape,angle:-90)
    let rim=NSBezierPath(roundedRect:NSRect(x:108,y:108,width:808,height:808),xRadius:182,yRadius:182)
    NSColor.white.withAlphaComponent(0.8).setStroke();rim.lineWidth=5;rim.stroke()
    // The waves flatten towards the contact point to suggest pressure, not radio transmission.
    for (width,height,y,alpha) in [(570.0,310.0,265.0,0.17),(440.0,224.0,308.0,0.34),(306.0,144.0,348.0,0.68)] {
        let wave=NSBezierPath(ovalIn:NSRect(x:512-width/2,y:y,width:width,height:height))
        wave.lineWidth = size <= 32 ? 20:15
        NSColor(red:0.13,green:0.36,blue:0.29,alpha:alpha).setStroke();wave.stroke()
    }
    let contact=NSBezierPath(roundedRect:NSRect(x:398,y:403,width:228,height:282),xRadius:114,yRadius:114)
    NSGraphicsContext.saveGraphicsState()
    let contactShadow=NSShadow();contactShadow.shadowColor=NSColor(red:0.08,green:0.23,blue:0.18,alpha:0.3);contactShadow.shadowBlurRadius=24;contactShadow.shadowOffset=NSSize(width:0,height:-20);contactShadow.set()
    NSColor(red:0.12,green:0.34,blue:0.26,alpha:1).setFill();contact.fill();NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting:NSColor(red:0.34,green:0.61,blue:0.46,alpha:1),ending:NSColor(red:0.09,green:0.29,blue:0.23,alpha:1))!.draw(in:contact,angle:-90)
    let glint=NSBezierPath();glint.move(to:NSPoint(x:447,y:628));glint.curve(to:NSPoint(x:532,y:653),controlPoint1:NSPoint(x:470,y:656),controlPoint2:NSPoint(x:502,y:662));glint.lineWidth=10;glint.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.46).setStroke();glint.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
}
