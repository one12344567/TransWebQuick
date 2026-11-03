import AppKit
import PressTransCore

@MainActor func checkOCR() throws {
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:960,pixelsHigh:240,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
    NSColor.white.setFill();NSRect(x:0,y:0,width:960,height:240).fill()
    let font=NSFont.systemFont(ofSize:36),attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:36),.foregroundColor:NSColor.black]
    ("Higher DM limits" as NSString).draw(at:NSPoint(x:40,y:130),withAttributes:attributes)
    NSGraphicsContext.restoreGraphicsState()
    let image=bitmap.cgImage!
    // A 2x Retina crop on a display to the left of the primary display.
    let region=CGRect(x:-800,y:120,width:480,height:120)
    let offset=("Higher DM " as NSString).size(withAttributes:attributes).width
    let width=("limits" as NSString).size(withAttributes:attributes).width
    let point=CGPoint(x:region.minX+(40+offset+width/2)/2,y:region.minY+(240-130-font.ascender/2)/2)
    let start=Date()
    let result=try ScreenTextRecognizer.recognize(image:image,region:region,point:point)
    precondition(result.word=="limits", "Wrong OCR target: \(result.word)")
    precondition(result.line.contains("Higher DM limits") && result.rect.contains(point))
    print("OCR raster check passed: limits, exact word bounds, line context, Retina / negative screen origin [\(Int(Date().timeIntervalSince(start)*1000)) ms]")
    do {
        _=try ScreenTextRecognizer.recognize(image:image,region:region,point:CGPoint(x:-795,y:125))
        preconditionFailure("Blank area must not return a nearby word")
    } catch ScreenTextRecognizer.RecognitionFailure.noText {}
    print("OCR blank-area rejection passed")
}
