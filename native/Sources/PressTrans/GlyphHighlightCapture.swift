import AppKit
import ScreenCaptureKit
import PressTransCore

/// One small, transient crop per requested highlight. No OCR, files, model calls or recording stream.
actor GlyphHighlightCapture {
    static let shared=GlyphHighlightCapture()
    func mask(region:CGRect,targets:[CGRect]) async ->CGImage? {
        guard #available(macOS 15.2,*),CGPreflightScreenCaptureAccess(),
              region.width>0,region.height>0,region.width<=1600,region.height<=240,
              region.width*region.height<=180_000,!Task.isCancelled else{return nil}
        do {
            let image=try await SCScreenshotManager.captureImage(in:region)
            try Task.checkCancellation()
            return autoreleasepool {GlyphHighlight.render(image:image,region:region,targets:targets)?.image}
        } catch {return nil}
    }
}
