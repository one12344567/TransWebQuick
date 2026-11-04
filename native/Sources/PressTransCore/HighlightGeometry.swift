import CoreGraphics

public enum HighlightGeometry {
    public static func appKitRect(_ rect:CGRect,primaryTop:CGFloat)->CGRect {
        CGRect(x:rect.minX,y:primaryTop-rect.maxY,width:rect.width,height:rect.height)
    }
    /// Expand only to the nearest physical pixel; a fixed 3 pt inset shifts short-word highlights.
    public static func aligned(_ rect:CGRect,scale:CGFloat)->CGRect? {
        guard rect.minX.isFinite,rect.minY.isFinite,rect.width.isFinite,rect.height.isFinite,
              rect.width>0,rect.height>0,scale.isFinite,scale>0 else{return nil}
        let x=floor(rect.minX*scale)/scale,y=floor(rect.minY*scale)/scale
        return CGRect(x:x,y:y,width:ceil(rect.maxX*scale)/scale-x,height:ceil(rect.maxY*scale)/scale-y)
    }
    /// Merge adjacent glyphs on one visual line, keeping wrapped lines separate.
    public static func lines(_ rects:[CGRect])->[CGRect] {
        var result:[CGRect]=[]
        for rect in rects where rect.width>0 && rect.height>0 && rect.width.isFinite && rect.height.isFinite && rect.minX.isFinite && rect.minY.isFinite {
            if let index=result.firstIndex(where:{abs($0.midY-rect.midY)<min($0.height,rect.height)*0.3 && rect.minX <= $0.maxX+3 && rect.maxX >= $0.minX-3}) {result[index]=result[index].union(rect)}
            else {result.append(rect)}
        }
        return result
    }
}
