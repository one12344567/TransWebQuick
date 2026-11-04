import Foundation
import CoreGraphics

/// Builds a transient yellow overlay with transparent solid glyphs and color-matted edges.
public enum GlyphHighlight {
    public struct Result {
        public let image:CGImage
        /// Tight visible highlight bounds, in image pixels (top-left origin).
        public let bounds:[CGRect]
    }
    public static func render(image:CGImage,region:CGRect,targets:[CGRect])->Result? {
        let width=image.width,height=image.height
        guard width>0,height>0,width*height<=1_000_000,region.width>0,region.height>0 else{return nil}
        let space=CGColorSpace(name:CGColorSpace.sRGB)!
        let info=CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        var source=[UInt8](repeating:0,count:width*height*4)
        let read=source.withUnsafeMutableBytes {bytes->Bool in
            guard let context=CGContext(data:bytes.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:space,bitmapInfo:info) else{return false}
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height));return true
        }
        guard read else{return nil}
        let sx=CGFloat(width)/region.width,sy=CGFloat(height)/region.height
        var output=[UInt8](repeating:0,count:source.count),bounds:[CGRect]=[]
        for target in targets.prefix(24) {
            let rect=CGRect(x:(target.minX-region.minX)*sx,y:(target.minY-region.minY)*sy,width:target.width*sx,height:target.height*sy).intersection(CGRect(x:0,y:0,width:width,height:height)).integral
            guard !rect.isNull,rect.width>2,rect.height>4 else{continue}
            let x0=max(0,Int(rect.minX)),x1=min(width,Int(rect.maxX)),y0=max(0,Int(rect.minY)),y1=min(height,Int(rect.maxY))
            var histogram=[Int:Int]()
            for y in y0..<y1 {for x in x0..<x1 {
                let i=(y*width+x)*4
                let key=(Int(source[i])>>4)<<8 | (Int(source[i+1])>>4)<<4 | Int(source[i+2])>>4
                histogram[key,default:0]+=1
            }}
            guard let dominant=histogram.max(by:{$0.value<$1.value}),Double(dominant.value)/Double((x1-x0)*(y1-y0))>0.30 else{continue}
            // Recover the actual background color, rather than the center of a quantization bin.
            var sums=[Int](repeating:0,count:3),samples=0
            for y in y0..<y1 {for x in x0..<x1 {
                let i=(y*width+x)*4
                let key=(Int(source[i])>>4)<<8 | (Int(source[i+1])>>4)<<4 | Int(source[i+2])>>4
                if key==dominant.key {for c in 0..<3{sums[c]+=Int(source[i+c])};samples+=1}
            }}
            let background=sums.map{$0/max(1,samples)}
            func difference(_ x:Int,_ y:Int)->Int {
                let i=(y*width+x)*4
                return max(abs(Int(source[i])-background[0]),abs(Int(source[i+1])-background[1]),abs(Int(source[i+2])-background[2]))
            }
            var left=x1,right=x0,top=y1,bottom=y0,ink=0,flat=0,inkContrast=0
            for y in y0..<y1 {for x in x0..<x1 {
                let delta=difference(x,y)
                inkContrast=max(inkContrast,delta)
                if delta<18 {flat+=1}
                if delta>36 {left=min(left,x);right=max(right,x);top=min(top,y);bottom=max(bottom,y);ink+=1}
            }}
            let area=(x1-x0)*(y1-y0)
            // Texture, an image background or a blank region cannot safely define a text mask.
            guard ink>=4,Double(ink)/Double(area)<0.55,Double(flat)/Double(area)>0.50,right>left,bottom>top else{continue}
            let padX=max(1,Int(ceil(sx*0.65))),padY=max(1,Int(ceil(sy*0.65)))
            let bx=max(x0,left-padX),by=max(y0,top-padY),ex=min(x1,right+1+padX),ey=min(y1,bottom+1+padY)
            let radius=min(2.5*sx,CGFloat(ey-by)*0.14)
            let dark=background.reduce(0,+)<3*128
            let alpha=dark ? 76:235
            let color=[255,225,46]
            for y in by..<ey {for x in bx..<ex {
                let cx=max(CGFloat(bx)+radius,min(CGFloat(x)+0.5,CGFloat(ex)-radius))
                let cy=max(CGFloat(by)+radius,min(CGFloat(y)+0.5,CGFloat(ey)-radius))
                guard hypot(CGFloat(x)+0.5-cx,CGFloat(y)+0.5-cy)<=radius else{continue}
                // Solid strokes stay transparent. Edge pixels contain both ink and background;
                // change only their estimated background contribution, avoiding a white halo.
                let coverage=min(1,Double(difference(x,y))/Double(inkContrast))
                guard coverage<0.98 else{continue}
                let i=(y*width+x)*4
                for c in 0..<3 {
                    let matted=Double(source[i+c])+Double(color[c]-background[c])*(1-coverage)
                    output[i+c]=UInt8(max(0,min(255,matted))*Double(alpha)/255)
                }
                output[i+3]=UInt8(alpha)
            }}
            bounds.append(CGRect(x:bx,y:by,width:ex-bx,height:ey-by))
        }
        guard !bounds.isEmpty,let provider=CGDataProvider(data:Data(output) as CFData),
              let image=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:space,bitmapInfo:CGBitmapInfo(rawValue:info),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else{return nil}
        return Result(image:image,bounds:bounds)
    }
}
