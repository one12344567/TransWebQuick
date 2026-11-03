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
    static func capture(processID:pid_t, appName:String, point:CGPoint?=nil) throws -> CaptureResult {
        guard AXIsProcessTrusted() else { throw CaptureFailure.permission }
        let root = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(root, 0.3)
        if let point {
            var hit:AXUIElement?
            if AXUIElementCopyElementAtPosition(root,Float(point.x),Float(point.y),&hit) == .success {
                var candidate=hit
                for _ in 0..<5 {
                    guard let element=candidate else{break}
                    do {return try captureElement(element,processID:processID,appName:appName,point:point)}
                    catch CaptureFailure.secure {throw CaptureFailure.secure}
                    catch {}
                    guard let parent=value(element,kAXParentAttribute),CFGetTypeID(parent)==AXUIElementGetTypeID() else{break}
                    candidate=(parent as! AXUIElement)
                }
            }
        }
        guard let focusedValue=value(root,kAXFocusedUIElementAttribute),CFGetTypeID(focusedValue)==AXUIElementGetTypeID() else{throw CaptureFailure.unsupported}
        return try captureElement(focusedValue as! AXUIElement,processID:processID,appName:appName,point:point)
    }
    private static func parameter(_ element:AXUIElement,_ name:String,_ argument:CFTypeRef)->CFTypeRef? {
        var result:CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(element,name as CFString,argument,&result) == .success ? result:nil
    }
    private static func rect(_ element:AXUIElement,_ range:CFTypeRef)->CGRect? {
        guard let value=parameter(element,kAXBoundsForRangeParameterizedAttribute,range),CFGetTypeID(value)==AXValueGetTypeID() else{return nil}
        var rect=CGRect.zero
        return AXValueGetValue(value as! AXValue,.cgRect,&rect) ? rect:nil
    }
    private static func captureElement(_ focused:AXUIElement,processID:pid_t,appName:String,point:CGPoint?) throws -> CaptureResult {
        if (value(focused, kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole { throw CaptureFailure.secure }
        var range = CFRange()
        var rangeValue = value(focused, kAXSelectedTextRangeAttribute)
        var hasRange = rangeValue.map { CFGetTypeID($0) == AXValueGetTypeID() && AXValueGetValue($0 as! AXValue, .cfRange, &range) } ?? false
        guard !hasRange || (range.location >= 0 && range.length <= 2000) else {throw CaptureFailure.unsupported}
        var selected = value(focused, kAXSelectedTextAttribute) as? String
        if let point {
            let selectedHere=rangeValue.flatMap{rect(focused,$0)}?.insetBy(dx:-2,dy:-2).contains(point) ?? false
            if !selectedHere || range.length==0 {
                var location=point
                guard let position=AXValueCreate(.cgPoint,&location),
                      let raw=parameter(focused,kAXRangeForPositionParameterizedAttribute,position),CFGetTypeID(raw)==AXValueGetTypeID(),
                      AXValueGetValue(raw as! AXValue,.cfRange,&range),range.location>=0 else{throw CaptureFailure.unsupported}
                let index=range.location
                let count=(value(focused,kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue
                let start=max(0,index-80),end=min(count ?? index+80,index+80)
                var nearby=CFRange(location:start,length:max(0,end-start))
                guard let argument=AXValueCreate(.cfRange,&nearby),let text=parameter(focused,kAXStringForRangeParameterizedAttribute,argument) as? String else{throw CaptureFailure.unsupported}
                let regex=try NSRegularExpression(pattern:"[A-Za-z]+(?:['’−-][A-Za-z]+)*")
                let words=regex.matches(in:text,range:NSRange(location:0,length:(text as NSString).length))
                guard let word=words.first(where:{$0.range.location<=index-start && NSMaxRange($0.range)>index-start}) else{throw CaptureFailure.noSelection}
                selected=(text as NSString).substring(with:word.range)
                range=CFRange(location:start+word.range.location,length:word.range.length)
                rangeValue=AXValueCreate(.cfRange,&range);hasRange=true
            }
        }
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
