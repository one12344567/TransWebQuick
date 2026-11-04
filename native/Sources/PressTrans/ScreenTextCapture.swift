import AppKit
import ScreenCaptureKit
import Vision
import PressTransCore

enum ScreenTextFailure:LocalizedError {
    case permission, unavailable, noText
    var errorDescription:String? {switch self {
    case .permission:L("此处需要屏幕识字。请在隐私与服务中允许屏幕录制；图片仅在本机识别。")
    case .unavailable:L("屏幕识字需要 macOS 15.2 或更新版本。")
    case .noText:L("指针下没有识别到清晰文字。请将指针放在字词上，或选中文字后查询。")
    }}
}
/// One-shot OCR only. No recording stream, screenshot files, image upload, or background polling.
actor ScreenTextCapture {
    static let shared=ScreenTextCapture()
    static var enabled:Bool {
        get{UserDefaults.standard.bool(forKey:"screenTextFallback")}
        set{UserDefaults.standard.set(newValue,forKey:"screenTextFallback")}
    }
    func capture(processID:pid_t,appName:String,point:CGPoint,screen:CGRect) async throws -> CaptureResult {
        try Task.checkCancellation()
        guard CGPreflightScreenCaptureAccess() else{throw ScreenTextFailure.permission}
        guard #available(macOS 15.2,*) else{throw ScreenTextFailure.unavailable}
        let region=CGRect(x:point.x-320,y:point.y-130,width:640,height:260).intersection(screen)
        guard !region.isEmpty else{throw ScreenTextFailure.noText}
        let image=try await SCScreenshotManager.captureImage(in:region)
        try Task.checkCancellation()
        let result:(word:String,line:String,rect:CGRect)
        do {result=try autoreleasepool {try ScreenTextRecognizer.recognize(image:image,region:region,point:point)}}
        catch {throw ScreenTextFailure.noText}
        try Task.checkCancellation()
        guard let context=ContextBuilder.make(selection:result.word,surrounding:result.line,sourceApp:appName+L(" · 屏幕识字")) else{throw ScreenTextFailure.noText}
        return CaptureResult(context:context,anchor:result.rect,processID:processID)
    }
}
