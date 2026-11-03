import Foundation
import CoreGraphics
import Vision

public enum ScreenTextRecognizer {
    public enum RecognitionFailure:Error {case noText}
    public static func recognize(image:CGImage,region:CGRect,point:CGPoint) throws -> (word:String,line:String,rect:CGRect) {
        let request=VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection=false
        request.automaticallyDetectsLanguage=true
        request.recognitionLanguages=["en-US","zh-Hans","zh-Hant","ja-JP","ko-KR","fr-FR","de-DE","es-ES","pt-BR","it-IT"]
        try VNImageRequestHandler(cgImage:image).perform([request])
        func screenRect(_ normalized:CGRect)->CGRect {
            CGRect(x:region.minX+normalized.minX*region.width,y:region.minY+(1-normalized.maxY)*region.height,width:normalized.width*region.width,height:normalized.height*region.height)
        }
        for observation in request.results ?? [] {
            guard let candidate=observation.topCandidates(1).first,candidate.confidence>=0.35,
                  screenRect(observation.boundingBox).insetBy(dx:-2,dy:-2).contains(point) else{continue}
            let text=candidate.string
            var match:(String,CGRect)?
            text.enumerateSubstrings(in:text.startIndex..<text.endIndex,options:.byWords) {word,range,_,stop in
                guard let word,let box=try? candidate.boundingBox(for:range) else{return}
                let rect=screenRect(box.boundingBox)
                if rect.insetBy(dx:-1,dy:-1).contains(point) {match=(word,rect);stop=true}
            }
            if let match {return (match.0,text,match.1)}
        }
        throw RecognitionFailure.noText
    }
}
