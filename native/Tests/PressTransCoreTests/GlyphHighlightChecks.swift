import AppKit
import CoreText
import PressTransCore

@MainActor func checkGlyphHighlight() throws {
    let info=CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    let space=CGColorSpace(name:CGColorSpace.sRGB)!
    var previews:[CGImage]=[]
    var times:[Double]=[]
    for (text,dark,colored) in [("高亮",false,false),("highlight",false,false),("高亮",true,false),("highlight",false,true)] {
        for (size,scale) in [(30.0,1),(30.0,2),(14.0,1),(14.0,2)] {
            let width=320*scale,height=100*scale
            let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:space,bitmapInfo:info)!
            context.scaleBy(x:CGFloat(scale),y:CGFloat(scale))
            context.setFillColor((dark ? NSColor(white:0.12,alpha:1):NSColor.white).cgColor)
            context.fill(CGRect(x:0,y:0,width:320,height:100))
            let line=CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:[.font:NSFont.systemFont(ofSize:size),.foregroundColor:dark ? NSColor.white:colored ? NSColor.systemBlue:NSColor.black]))
            context.textPosition=CGPoint(x:25,y:42);CTLineDraw(line,context)
            let source=context.makeImage()!
            // Deliberately oversized AX line box, offset from the top and from the screen origin.
            let region=CGRect(x:-700,y:130,width:320,height:100)
            let target=CGRect(x:-678,y:151,width:230,height:52)
            let began=Date()
            let result=GlyphHighlight.render(image:source,region:region,targets:[target])!
            times.append(Date().timeIntervalSince(began)*1000)
            let sourceData=source.dataProvider!.data!
            let pixels=CFDataGetBytePtr(sourceData)!
            let maskData=result.image.dataProvider!.data!
            let mask=CFDataGetBytePtr(maskData)!
            let bg=dark ? Int(pixels[0]):255
            let strongest=(0..<(width*height)).map {p in max(abs(Int(pixels[p*4])-bg),abs(Int(pixels[p*4+1])-bg),abs(Int(pixels[p*4+2])-bg))}.max()!
            var protected=0,yellow=0,minY=height,maxY=0,minX=width,maxX=0
            for y in 0..<height {for x in 0..<width {
                let i=(y*width+x)*4
                let delta=max(abs(Int(pixels[i])-bg),abs(Int(pixels[i+1])-bg),abs(Int(pixels[i+2])-bg))
                if delta>18 {
                    if Double(delta)/Double(strongest)>=0.98 {precondition(mask[i+3]==0,"Solid glyphs must remain transparent")}
                    protected+=1;minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)
                }
                if mask[i+3]>0 {
                    yellow+=1
                    precondition(result.bounds[0].contains(CGPoint(x:x,y:y)))
                    precondition(mask[i+3] == (dark ? 76:235))
                }
            }}
            let ink=CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1),box=result.bounds[0]
            precondition(protected>50 && yellow>50)
            precondition(box.contains(ink) && box.height<target.height*CGFloat(scale)*0.8,"Trim line leading, not just outer padding")
            precondition(box.width-ink.width<=CGFloat(4*scale) && box.height-ink.height<=CGFloat(4*scale))
            // Composite with the production mask: transparent cut-outs must stay aligned at 1x and 2x.
            let composite=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:space,bitmapInfo:info)!
            composite.draw(source,in:CGRect(x:0,y:0,width:width,height:height))
            composite.draw(result.image,in:CGRect(x:0,y:0,width:width,height:height))
            let composited=composite.makeImage()!,compositeData=composited.dataProvider!.data!
            let actual=CFDataGetBytePtr(compositeData)!
            for p in 0..<(width*height) {
                let i=p*4
                let delta=max(abs(Int(pixels[i])-bg),abs(Int(pixels[i+1])-bg),abs(Int(pixels[i+2])-bg))
                if Double(delta)/Double(strongest)>=0.98 {
                    for c in 0..<3 {precondition(abs(Int(pixels[i+c])-Int(actual[i+c]))<=1,"Composite must preserve solid glyph color")}
                }
                if !dark {precondition(abs(Int(pixels[i])-Int(actual[i]))<=1,"Light-background glyph luminance edge must not wash out")}
            }
            if scale==2 && size==30 {previews.append(composited)}
            let blank=CGRect(x:region.minX+260,y:region.minY,width:50,height:100)
            precondition(GlyphHighlight.render(image:source,region:region,targets:[blank])==nil)
        }
    }
    if let path=ProcessInfo.processInfo.environment["PRESSTRANS_HIGHLIGHT_PREVIEW"] {
        let sheet=CGContext(data:nil,width:640,height:previews.count*200,bitsPerComponent:8,bytesPerRow:640*4,space:space,bitmapInfo:info)!
        for (index,image) in previews.enumerated() {sheet.draw(image,in:CGRect(x:0,y:(previews.count-1-index)*200,width:640,height:200))}
        let data=NSBitmapImageRep(cgImage:sheet.makeImage()!).representation(using:.png,properties:[:])!
        try data.write(to:URL(fileURLWithPath:path))
    }
    print("Glyph highlight raster checks passed: Chinese, Latin, dark/light, colored glyphs, 14/30pt, 1x/2x, tight bounds, negative origin, blank rejection; max \(Int(times.max() ?? 0)) ms")
}
