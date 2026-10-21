import Cocoa
import os

private let holderLog = Logger(subsystem: "com.windowsnap.WindowSnap", category: "HolderManager")

/// A window snapped into a holder. Closed-window and drag-out removal comes later.
final class GroupedWindow {
    let windowID: CGWindowID
    let pid: pid_t
    let ownerName: String
    let element: AXUIElement
    var frame: NSRect

    init(windowID: CGWindowID, pid: pid_t, ownerName: String, element: AXUIElement, frame: NSRect) {
        self.windowID = windowID
        self.pid = pid
        self.ownerName = ownerName
        self.element = element
        self.frame = frame
    }
}

final class Holder {
    let id: UUID
    let panel: HolderPanel
    private(set) var windows: [GroupedWindow] = []

    init(id: UUID, panel: HolderPanel) {
        self.id = id
        self.panel = panel
    }

    func place(_ window: GroupedWindow) {
        windows.removeAll { $0.windowID == window.windowID }
        windows.append(window)
    }

    func remove(windowID: CGWindowID) {
        windows.removeAll { $0.windowID == windowID }
    }

    func removeAllWindows() {
        windows.removeAll()
    }
}

final class HolderManager: HolderPanelDelegate {
    private(set) var holders: [Holder] = []
    private(set) var isEditing = false
    private(set) var selectedID: UUID?

    var onTrustChanged: ((Bool) -> Void)?
    var onVisibilityChanged: (() -> Void)?

    var hasHiddenHolder: Bool {
        holders.contains { $0.panel.isMinimized }
    }

    private var eventTap: CFMachPort?
    private var eventRunLoopSource: CFRunLoopSource?
    private var keyMonitor: Any?
    private var trustTimer: Timer?
    private var lastReportedTrust: Bool?
    private var trackingScheduled = false
    private var dragCandidate: (id: CGWindowID, frame: NSRect)?
    private var dragElement: AXUIElement?

    var canDeleteSelected: Bool {
        guard isEditing, let selectedID else { return false }
        return holders.contains { $0.id == selectedID }
    }

    var summaries: [String] {
        holders.enumerated().map { index, holder in
            let count = holder.windows.count
            let noun = count == 1 ? "window" : "windows"
            let selected = isEditing && holder.id == selectedID ? " · selected" : ""
            return "Holder \(index + 1) — \(count) \(noun)\(selected)"
        }
    }

    func start() {
        ensureMonitoring()
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.ensureMonitoring()
        }
    }

    /// A session event tap sees the mouse-up that ends a window drag. NSEvent's global monitor often does not.
    /// The tap only exists while Accessibility is granted, so this retries after the user turns it on.
    func ensureMonitoring() {
        let trusted = WindowTracker.isTrusted
        if lastReportedTrust != trusted {
            lastReportedTrust = trusted
            onTrustChanged?(trusted)
        }
        if trusted, eventTap != nil {
            return
        }
        removeTap()
        guard trusted else { return }

        let mask = CGEventMask(
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue)
        )
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HolderManager>.fromOpaque(userInfo).takeUnretainedValue()
                switch type {
                case .tapDisabledByTimeout, .tapDisabledByUserInput:
                    DispatchQueue.main.async { manager.reenableTap() }
                case .leftMouseUp:
                    DispatchQueue.main.async { manager.handleMouseUp() }
                case .mouseMoved:
                    manager.scheduleTracking()
                case .leftMouseDragged:
                    DispatchQueue.main.async { manager.constrainDraggedWindow() }
                case .leftMouseDown:
                    if Thread.isMainThread {
                        manager.trackHolders()
                        manager.captureDragStart()
                    } else {
                        DispatchQueue.main.async {
                            manager.trackHolders()
                            manager.captureDragStart()
                        }
                    }
                default:
                    break
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else {
            holderLog.error("Accessibility is on but the mouse-up tap was not created")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventRunLoopSource = source
        trackHolders()

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.isEditing == true else { return }
            self?.setEditing(false)
        }
    }

    fileprivate func reenableTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    fileprivate func scheduleTracking() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.scheduleTracking() }
            return
        }
        guard !trackingScheduled else { return }
        trackingScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.trackingScheduled = false
            self.trackHolders()
        }
    }

    private func trackHolders() {
        let mouse = NSEvent.mouseLocation
        for holder in holders {
            holder.panel.trackMouse(at: mouse)
        }
    }

    fileprivate func captureDragStart() {
        let mouse = NSEvent.mouseLocation
        if isEditing || holders.contains(where: { $0.panel.claimsMouse(at: mouse) }) {
            dragCandidate = nil
            dragElement = nil
            return
        }
        guard let target = WindowTracker.windowUnderCursor(excludingPID: getpid()) else {
            dragCandidate = nil
            dragElement = nil
            return
        }
        dragCandidate = (target.windowID, target.appKitFrame)
        dragElement = holders.lazy.compactMap { holder in
            holder.windows.first { $0.windowID == target.windowID }?.element
        }.first
    }

    /// Pull a dragged window back inside as soon as its top crosses the holder edge.
    fileprivate func constrainDraggedWindow() {
        guard !isEditing, let started = dragCandidate else { return }
        guard let target = WindowTracker.windowUnderCursor(excludingPID: getpid()),
              target.windowID == started.id else { return }
        let frame = target.appKitFrame
        guard let holder = holder(containing: frame) else { return }
        let content = holder.panel.contentScreenFrame
        guard frame.maxY > content.maxY + 0.5 else { return }
        let element = dragElement ?? WindowTracker.element(matching: target)
        dragElement = element
        guard let element else { return }
        let placed = fittedFrame(element, windowID: target.windowID, proposed: frame, content: content)
        if let grouped = holder.windows.first(where: { $0.windowID == target.windowID }) {
            grouped.frame = placed
        }
    }

    private func removeTap() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        if let eventRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventRunLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
        eventRunLoopSource = nil
    }

    func createHolder() {
        let id = UUID()
        let panel = HolderPanel(holderID: id, frame: frameForNewHolder())
        panel.holderDelegate = self
        let holder = Holder(id: id, panel: panel)
        holders.append(holder)
        selectedID = id
        panel.isEditing = isEditing
        panel.isSelected = isEditing
        for other in holders where other.id != id {
            other.panel.isSelected = false
        }
        panel.orderFrontRegardless()
    }

    func setEditing(_ editing: Bool) {
        isEditing = editing
        if editing, selectedID == nil {
            selectedID = holders.last?.id
        }
        if !editing {
            selectedID = nil
        }
        for holder in holders {
            holder.panel.isEditing = editing
            holder.panel.isSelected = editing && holder.id == selectedID
        }
    }

    func toggleEditing() {
        setEditing(!isEditing)
    }

    func deleteSelected() {
        guard let selectedID, let index = holders.firstIndex(where: { $0.id == selectedID }) else { return }
        let holder = holders.remove(at: index)
        holder.panel.close()
        self.selectedID = isEditing ? holders.last?.id : nil
        for item in holders {
            item.panel.isSelected = item.id == self.selectedID
        }
    }

    func holderPanelDidSelect(_ panel: HolderPanel) {
        selectedID = panel.holderID
        for holder in holders {
            holder.panel.isSelected = holder.id == selectedID
        }
        panel.orderFrontRegardless()
    }

    func holderPanelDidRequestExitEdit(_ panel: HolderPanel) {
        setEditing(false)
    }

    func holderPanelDidEndFrameChange(_ panel: HolderPanel) {
        guard let holder = holders.first(where: { $0.panel === panel }) else { return }
        reflow(holder)
    }

    func holderPanelDidRequestMinimizeAll(_ panel: HolderPanel) {
        guard let holder = holders.first(where: { $0.panel === panel }) else { return }
        for window in holder.windows {
            if let visible = WindowTracker.appKitFrame(of: window.windowID) {
                window.frame = visible
            }
        }
        WindowTracker.setMinimized(holder.windows.map(\.element), minimized: true)
        panel.minimizeAway()
        onVisibilityChanged?()
    }

    func holderPanelDidRequestDeleteAll(_ panel: HolderPanel) {
        guard let holder = holders.first(where: { $0.panel === panel }) else { return }
        for window in holder.windows {
            WindowTracker.closeWindow(window.element)
        }
        holder.removeAllWindows()
    }

    /// Moves each window into the matching slot of `layout`. Slots share edges and reach the holder corners.
    @discardableResult
    func placeWindows(_ windows: [ExternalWindow], layout: HolderLayout) -> Int {
        guard !windows.isEmpty, layout.slots.count == windows.count else { return 0 }
        let holder = holderForPlacement()
        let tiles = layout.frames(in: holder.panel.contentScreenFrame)
        var placedCount = 0
        for (target, tile) in zip(windows, tiles) {
            guard let element = WindowTracker.element(matching: target) else { continue }
            WindowTracker.setMinimized([element], minimized: false)
            let placed = fittedFrame(element, windowID: target.windowID, proposed: tile, content: holder.panel.contentScreenFrame)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            for other in holders where other !== holder {
                other.remove(windowID: target.windowID)
            }
            holder.place(GroupedWindow(
                windowID: target.windowID,
                pid: target.pid,
                ownerName: target.ownerName,
                element: element,
                frame: placed
            ))
            placedCount += 1
        }
        holder.panel.orderFrontRegardless()
        return placedCount
    }

    private func holderForPlacement() -> Holder {
        if let visible = holders.last(where: { !$0.panel.isMinimized }) {
            return visible
        }
        if let hidden = holders.last {
            hidden.panel.restore()
            return hidden
        }
        createHolder()
        return holders[holders.count - 1]
    }

    /// Dock click. Restores a minimized holder, or brings the current one forward.
    func presentHolders() {
        if hasHiddenHolder {
            restoreHiddenHolders()
            return
        }
        if holders.isEmpty {
            createHolder()
            return
        }
        for holder in holders {
            holder.panel.restore()
        }
    }

    func restoreHiddenHolders() {
        let windows = holders.filter(\.panel.isMinimized).flatMap(\.windows)
        for holder in holders where holder.panel.isMinimized {
            holder.panel.restore()
        }
        WindowTracker.setMinimized(windows.map(\.element), minimized: false)
        onVisibilityChanged?()
        // Deminiaturize applies the app's own size after the windows appear. Put the saved size back once that finishes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.restoreFrames(windows)
        }
    }

    private func handleMouseUp() {
        if holders.contains(where: \.panel.suppressNextSnap) {
            for holder in holders {
                holder.panel.suppressNextSnap = false
            }
            dragCandidate = nil
            dragElement = nil
            return
        }
        guard !isEditing, !holders.isEmpty else { return }
        guard WindowTracker.isTrusted else { return }
        let started = dragCandidate
        dragCandidate = nil
        dragElement = nil
        guard let started else { return }
        let mouse = NSEvent.mouseLocation
        if holders.contains(where: { $0.panel.claimsMouse(at: mouse) }) {
            return
        }
        guard let target = WindowTracker.windowUnderCursor(excludingPID: getpid()) else { return }
        guard target.windowID == started.id else { return }
        let windowFrame = target.appKitFrame
        let moved = abs(windowFrame.minX - started.frame.minX) > 6
            || abs(windowFrame.minY - started.frame.minY) > 6
            || abs(windowFrame.width - started.frame.width) > 6
            || abs(windowFrame.height - started.frame.height) > 6
        guard moved else { return }
        let matches: [(Holder, CGFloat)] = holders.compactMap { holder in
            let coverage = WindowTracker.snapCoverage(of: windowFrame, with: holder.panel.frame)
            let score = max(coverage.window, coverage.holder)
            guard !holder.panel.isMinimized else { return nil }
            guard WindowTracker.shouldSnap(window: windowFrame, holder: holder.panel.frame) else {
                if score > 0.05 {
                    holderLog.info("No snap for \(target.ownerName, privacy: .public): window \(coverage.window, privacy: .public) holder \(coverage.holder, privacy: .public)")
                }
                return nil
            }
            return (holder, score)
        }
        guard let best = matches.max(by: { $0.1 < $1.1 }) else { return }
        guard !best.0.panel.isMinimized else { return }
        guard let element = WindowTracker.element(matching: target) else { return }
        let placed = fittedFrame(element, windowID: target.windowID, proposed: windowFrame, content: best.0.panel.contentScreenFrame)

        for holder in holders where holder !== best.0 {
            holder.remove(windowID: target.windowID)
        }
        best.0.place(GroupedWindow(
            windowID: target.windowID,
            pid: target.pid,
            ownerName: target.ownerName,
            element: element,
            frame: placed
        ))
        holderLog.info("Snapped \(target.ownerName, privacy: .public) \(target.windowID) overlap \(best.1, privacy: .public)")
    }

    private func holder(containing windowFrame: NSRect) -> Holder? {
        let matches: [(Holder, CGFloat)] = holders.compactMap { holder in
            guard !holder.panel.isMinimized else { return nil }
            guard WindowTracker.shouldSnap(window: windowFrame, holder: holder.panel.frame) else { return nil }
            let coverage = WindowTracker.snapCoverage(of: windowFrame, with: holder.panel.frame)
            return (holder, max(coverage.window, coverage.holder))
        }
        return matches.max(by: { $0.1 < $1.1 })?.0
    }

    private func reflow(_ holder: Holder) {
        let content = holder.panel.contentScreenFrame
        for window in holder.windows {
            window.frame = fittedFrame(window.element, windowID: window.windowID, proposed: window.frame, content: content)
        }
    }

    /// Keeps the window inside the holder.
    /// A second pass corrects apps whose on-screen frame hangs above the frame Accessibility reports.
    private func fittedFrame(_ element: AXUIElement, windowID: CGWindowID, proposed: NSRect, content: NSRect) -> NSRect {
        var placed = clamped(proposed, to: content)
        guard WindowTracker.snap(element, toAppKitFrame: placed) else { return placed }
        guard let actual = WindowTracker.appKitFrame(of: windowID) else { return placed }
        let overflow = actual.maxY - content.maxY
        guard overflow > 1 else { return actual }
        placed.origin.y -= overflow
        if placed.minY < content.minY {
            placed.origin.y = content.minY
        }
        placed = clamped(placed, to: content)
        WindowTracker.snap(element, toAppKitFrame: placed)
        return WindowTracker.appKitFrame(of: windowID) ?? placed
    }

    /// Accessibility size is not always the on-screen size. Nudge the request so the visible frame matches `target`.
    private func restoreFrames(_ windows: [GroupedWindow]) {
        for window in windows {
            let target = window.frame
            WindowTracker.snap(window.element, toAppKitFrame: target)
            guard let actual = WindowTracker.appKitFrame(of: window.windowID) else { continue }
            let corrected = NSRect(
                x: target.minX - (actual.minX - target.minX),
                y: target.minY - (actual.minY - target.minY),
                width: target.width - (actual.width - target.width),
                height: target.height - (actual.height - target.height)
            )
            let sizeChanged = abs(corrected.width - target.width) > 1 || abs(corrected.height - target.height) > 1
            let originChanged = abs(corrected.minX - target.minX) > 1 || abs(corrected.minY - target.minY) > 1
            if sizeChanged || originChanged {
                WindowTracker.snap(window.element, toAppKitFrame: corrected)
            }
        }
    }

    private func clamped(_ frame: NSRect, to content: NSRect) -> NSRect {
        var result = frame
        result.size.width = min(max(result.width, 80), max(content.width, 80))
        result.size.height = min(max(result.height, 60), max(content.height, 60))
        result.origin.x = min(max(result.origin.x, content.minX), content.maxX - result.size.width)
        result.origin.y = min(max(result.origin.y, content.minY), content.maxY - result.size.height)
        return result
    }

    private func frameForNewHolder() -> NSRect {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(x: 80, y: 80, width: 1100, height: 720)
        }
        return screen.visibleFrame
    }

    deinit {
        trustTimer?.invalidate()
        removeTap()
    }
}
