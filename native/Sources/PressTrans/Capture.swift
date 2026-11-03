import AppKit
import ApplicationServices
import PressTransCore

struct CaptureResult { let context: CapturedContext; let anchor: CGRect?; let processID: pid_t }
enum CaptureFailure: LocalizedError {
    case permission, noSelection, secure, unsupported
    var errorDescription: String? {
        switch self {
        case .permission: return "先为 PressTrans 开启辅助功能权限，然后回到原应用选中文字。"
        case .noSelection: return "没有读到选中文字。请先选中一个词或句子，再按 ⌥⇧T。"
        case .secure: return "此处是受保护的输入区域，无法查询。"
        case .unsupported: return "此应用没有提供可读取的选区。可在菜单中打开手动查询。"
        }
    }
}
final class TextCapture {
    static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    static func capture(processID:pid_t, appName:String) throws -> CaptureResult {
        guard AXIsProcessTrusted() else { throw CaptureFailure.permission }
        let root = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(root, 0.3)
        guard let focusedValue = value(root, kAXFocusedUIElementAttribute), CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { throw CaptureFailure.unsupported }
        let focused = focusedValue as! AXUIElement
        if (value(focused, kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole { throw CaptureFailure.secure }
        var range = CFRange()
        let rangeValue = value(focused, kAXSelectedTextRangeAttribute)
        let hasRange = rangeValue.map { CFGetTypeID($0) == AXValueGetTypeID() && AXValueGetValue($0 as! AXValue, .cfRange, &range) } ?? false
        guard !hasRange || (range.location >= 0 && range.length <= 2000) else {throw CaptureFailure.unsupported}
        var selected = value(focused, kAXSelectedTextAttribute) as? String
        if (selected?.isEmpty ?? true), hasRange, range.length > 0 {
            var output: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(focused, kAXStringForRangeParameterizedAttribute as CFString, rangeValue!, &output) == .success { selected = output as? String }
        }
        guard let selected, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CaptureFailure.noSelection }
        var surrounding: String?
        // Ask for a bounded range first instead of fetching an entire document.
        if hasRange, range.location >= 0, range.length > 0 {
            let count = (value(focused, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue
            let start = max(0, range.location - 600)
            let end = min(count ?? range.location + range.length, range.location + range.length + 1200)
            var contextRange = CFRange(location: start, length: max(0, end - start))
            if let argument = AXValueCreate(.cfRange, &contextRange) {
                var output: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(focused, kAXStringForRangeParameterizedAttribute as CFString, argument, &output) == .success { surrounding = output as? String }
            }
        }
        // Only read full values of reasonably-sized text controls.
        if surrounding == nil, let count = value(focused, kAXNumberOfCharactersAttribute) as? NSNumber, count.intValue <= 12000 {
            surrounding = value(focused, kAXValueAttribute) as? String
        }
        guard let context = ContextBuilder.make(selection: selected, surrounding: surrounding, sourceApp: appName) else { throw CaptureFailure.noSelection }
        var anchor: CGRect?
        if hasRange, let rangeValue {
            var result: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(focused, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &result) == .success, let result, CFGetTypeID(result) == AXValueGetTypeID() {
                var rect = CGRect.zero
                if AXValueGetValue(result as! AXValue, .cgRect, &rect), rect.width > 0 { anchor = rect }
            }
        }
        return CaptureResult(context: context, anchor: anchor, processID: processID)
    }
}
