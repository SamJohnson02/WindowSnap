import Cocoa
import os

private let snapLog = Logger(subsystem: "com.windowsnap.WindowHolder", category: "WindowTracker")

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

struct ExternalWindow {
    let windowID: CGWindowID
    let pid: pid_t
    let ownerName: String
    /// CoreGraphics bounds: origin at the top-left of the primary display, y grows downward.
    let quartzFrame: CGRect

    var appKitFrame: NSRect {
        ScreenCoordinates.appKitFrame(fromQuartzFrame: quartzFrame)
    }
}

enum ScreenCoordinates {
    /// The display whose AppKit frame origin is (0, 0). That is the menu-bar display, and the flip axis for AX.
    static var primaryScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero }
    }

    static func appKitFrame(fromQuartzFrame quartz: CGRect) -> NSRect {
        guard let primary = primaryScreen else {
            return NSRect(origin: .zero, size: quartz.size)
        }
        return NSRect(
            x: quartz.origin.x,
            y: primary.frame.height - quartz.origin.y - quartz.height,
            width: quartz.width,
            height: quartz.height
        )
    }

    static func quartzFrame(fromAppKitFrame appKit: NSRect) -> CGRect {
        guard let primary = primaryScreen else { return appKit }
        return CGRect(
            x: appKit.origin.x,
            y: primary.frame.height - appKit.origin.y - appKit.height,
            width: appKit.width,
            height: appKit.height
        )
    }

    static var mouseLocationQuartz: CGPoint {
        let mouse = NSEvent.mouseLocation
        guard let primary = primaryScreen else { return mouse }
        return CGPoint(x: mouse.x, y: primary.frame.height - mouse.y)
    }
}

enum WindowTracker {
    /// Fraction of the dragged window's area that must lie inside a holder.
    static let overlapThreshold: CGFloat = 0.5

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    private static var didRequestTrust = false
    static var hasRequestedTrust: Bool { didRequestTrust }

    /// One system prompt per launch. macOS applies the switch only to this exact copy of the app.
    static func promptForTrustIfNeeded() {
        guard !isTrusted, !didRequestTrust else { return }
        didRequestTrust = true
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func relaunchToApplyTrust() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        let url = Bundle.main.bundleURL
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if error == nil {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    static func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// Snap when most of the window is inside the holder, or the window covers most of the holder.
    /// A large window can never put half its area inside a smaller holder, but it can cover the holder.
    static func snapCoverage(of window: CGRect, with holder: CGRect) -> (window: CGFloat, holder: CGFloat) {
        let intersection = window.intersection(holder)
        guard !intersection.isNull, !intersection.isEmpty else { return (0, 0) }
        let overlap = intersection.width * intersection.height
        let windowArea = window.width * window.height
        let holderArea = holder.width * holder.height
        guard windowArea > 1, holderArea > 1 else { return (0, 0) }
        return (overlap / windowArea, overlap / holderArea)
    }

    static func shouldSnap(window: CGRect, holder: CGRect) -> Bool {
        let coverage = snapCoverage(of: window, with: holder)
        return coverage.window > overlapThreshold || coverage.holder > overlapThreshold
    }

    /// Topmost layer-0 window under the cursor, skipping this process.
    static func windowUnderCursor(excludingPID: pid_t) -> ExternalWindow? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let mouse = ScreenCoordinates.mouseLocationQuartz
        var best: ExternalWindow?
        for info in list {
            guard int(from: info, key: kCGWindowLayer) == 0 else { continue }
            guard let pid = int(from: info, key: kCGWindowOwnerPID), pid_t(pid) != excludingPID else { continue }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.01 else { continue }
            guard let windowNumber = int(from: info, key: kCGWindowNumber) else { continue }
            guard let quartzFrame = quartzBounds(from: info), quartzFrame.width > 40, quartzFrame.height > 40 else { continue }
            guard quartzFrame.contains(mouse) else { continue }
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let candidate = ExternalWindow(
                windowID: CGWindowID(windowNumber),
                pid: pid_t(pid),
                ownerName: owner,
                quartzFrame: quartzFrame
            )
            // Electron apps stack a small web view over the real window. Prefer the largest frame under the pointer.
            if let best, best.quartzFrame.width * best.quartzFrame.height >= quartzFrame.width * quartzFrame.height {
                continue
            }
            best = candidate
        }
        return best
    }

    static func element(matching window: ExternalWindow) -> AXUIElement? {
        let application = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(application, 0.4)
        let windows = axWindows(of: application)
        for element in windows {
            AXUIElementSetMessagingTimeout(element, 0.25)
            if cgWindowID(of: element) == window.windowID {
                return element
            }
        }
        for element in windows {
            guard let frame = quartzFrame(of: element) else { continue }
            if framesMatch(frame, window.quartzFrame, tolerance: 4) {
                return element
            }
        }
        snapLog.error("No AX element for pid \(window.pid) window \(window.windowID)")
        return nil
    }

    static func appKitFrame(of windowID: CGWindowID) -> NSRect? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
              let info = list.first,
              let quartz = quartzBounds(from: info) else {
            return nil
        }
        return ScreenCoordinates.appKitFrame(fromQuartzFrame: quartz)
    }

    @discardableResult
    static func snap(_ element: AXUIElement, toAppKitFrame frame: NSRect) -> Bool {
        let quartz = ScreenCoordinates.quartzFrame(fromAppKitFrame: frame)
        var position = CGPoint(x: quartz.origin.x, y: quartz.origin.y)
        var size = CGSize(width: quartz.width, height: quartz.height)
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }

        let sizeError = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        let positionError = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        // Set both again. Some AppKit apps shift the origin when the size changes.
        var positionAgain = position
        var sizeAgain = size
        if let positionValue = AXValueCreate(.cgPoint, &positionAgain),
           let sizeValue = AXValueCreate(.cgSize, &sizeAgain) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        }

        let ok = sizeError == .success && positionError == .success
        if !ok {
            snapLog.error("Snap failed size=\(sizeError.rawValue) position=\(positionError.rawValue)")
        }
        return ok
    }

    /// Posts minimize or unminimize to every window before any of them animate.
    /// A normal Accessibility call waits for that window's animation, which staggers the group.
    static func setMinimized(_ elements: [AXUIElement], minimized: Bool) {
        let value: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
        for element in elements {
            AXUIElementSetMessagingTimeout(element, 0)
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, value)
        }
    }

    @discardableResult
    static func closeWindow(_ element: AXUIElement) -> Bool {
        var buttonRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &buttonRef) == .success,
              let buttonRef,
              CFGetTypeID(buttonRef) == AXUIElementGetTypeID() else {
            return false
        }
        let button = buttonRef as! AXUIElement
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    private static func axWindows(of application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        guard error == .success, let value else {
            if error != .success {
                snapLog.error("AX window list failed: \(error.rawValue)")
            }
            return []
        }
        if let windows = value as? [AXUIElement] {
            return windows
        }
        guard CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        let array = value as! CFArray
        var windows: [AXUIElement] = []
        for index in 0..<CFArrayGetCount(array) {
            guard let pointer = CFArrayGetValueAtIndex(array, index) else { continue }
            windows.append(Unmanaged<AXUIElement>.fromOpaque(pointer).takeUnretainedValue())
        }
        return windows
    }

    private static func cgWindowID(of element: AXUIElement) -> CGWindowID? {
        var identifier: CGWindowID = 0
        let error = _AXUIElementGetWindow(element, &identifier)
        guard error == .success, identifier != 0 else { return nil }
        return identifier
    }

    private static func quartzFrame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        let positionAX = positionValue as! AXValue
        let sizeAX = sizeValue as! AXValue
        guard AXValueGetValue(positionAX, .cgPoint, &position),
              AXValueGetValue(sizeAX, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private static func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private static func quartzBounds(from info: [String: Any]) -> CGRect? {
        guard let bounds = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
        func number(_ key: String) -> CGFloat? {
            if let value = bounds[key] as? NSNumber { return CGFloat(value.doubleValue) }
            if let value = bounds[key] as? Double { return CGFloat(value) }
            return nil
        }
        guard let x = number("X"), let y = number("Y"), let width = number("Width"), let height = number("Height") else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func int(from info: [String: Any], key: CFString) -> Int? {
        switch info[key as String] {
        case let value as Int:
            return value
        case let value as UInt32:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        default:
            return nil
        }
    }
}
