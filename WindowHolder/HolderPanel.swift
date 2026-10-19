import Cocoa

protocol HolderPanelDelegate: AnyObject {
    func holderPanelDidSelect(_ panel: HolderPanel)
    func holderPanelDidRequestExitEdit(_ panel: HolderPanel)
    func holderPanelDidEndFrameChange(_ panel: HolderPanel)
    func holderPanelDidRequestMinimizeAll(_ panel: HolderPanel)
    func holderPanelDidRequestDeleteAll(_ panel: HolderPanel)
}

enum HolderMetrics {
    static let buttonSize: CGFloat = 13
    static let barPadding: CGFloat = 2
    static let buttonGap: CGFloat = 3
    static let barInset: CGFloat = 6
    static let barHeight: CGFloat = buttonSize + barPadding * 2
    static let barWidth: CGFloat = barPadding * 2 + buttonSize * 2 + buttonGap
}

/// Borderless holder. A small control cluster at the top left can minimize or delete every window locked inside.
/// The rest of the panel ignores the mouse so those windows stay usable.
final class HolderPanel: NSPanel {
    let holderID: UUID
    weak var holderDelegate: HolderPanelDelegate?
    var suppressNextSnap = false
    private(set) var isMinimized = false

    private let canvas: HolderCanvasView
    private let barPanel: NSPanel
    private let barView: HolderBarView

    var isEditing = false {
        didSet { applyChrome() }
    }

    var isSelected = false {
        didSet {
            canvas.isSelected = isSelected
            canvas.needsDisplay = true
        }
    }

    /// Full holder rect, in screen coordinates. Dropped windows can use the top edge.
    var contentScreenFrame: NSRect { frame }

    init(holderID: UUID, frame: NSRect) {
        self.holderID = holderID
        canvas = HolderCanvasView(frame: NSRect(origin: .zero, size: frame.size))
        barView = HolderBarView(frame: NSRect(x: 0, y: 0, width: HolderMetrics.barWidth, height: HolderMetrics.barHeight))
        barPanel = NSPanel(
            contentRect: NSRect(x: frame.minX, y: frame.maxY - HolderMetrics.barHeight, width: HolderMetrics.barWidth, height: HolderMetrics.barHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        isMovableByWindowBackground = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        acceptsMouseMovedEvents = true

        canvas.autoresizingMask = [.width, .height]
        canvas.onFrameChanged = { [weak self] in
            guard let self else { return }
            self.holderDelegate?.holderPanelDidEndFrameChange(self)
        }
        canvas.onSelect = { [weak self] in
            guard let self else { return }
            self.holderDelegate?.holderPanelDidSelect(self)
        }
        canvas.onExitEdit = { [weak self] in
            guard let self else { return }
            self.holderDelegate?.holderPanelDidRequestExitEdit(self)
        }
        contentView = canvas

        barPanel.isFloatingPanel = true
        barPanel.isReleasedWhenClosed = false
        barPanel.isOpaque = false
        barPanel.backgroundColor = .clear
        barPanel.hasShadow = false
        barPanel.hidesOnDeactivate = false
        barPanel.level = .popUpMenu
        barPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        barPanel.animationBehavior = .none
        barPanel.ignoresMouseEvents = false
        barView.autoresizingMask = [.width, .height]
        barView.onMinimize = { [weak self] in
            guard let self else { return }
            self.suppressNextSnap = true
            self.holderDelegate?.holderPanelDidRequestMinimizeAll(self)
        }
        barView.onDelete = { [weak self] in
            guard let self else { return }
            self.suppressNextSnap = true
            self.holderDelegate?.holderPanelDidRequestDeleteAll(self)
        }
        barPanel.contentView = barView
        applyChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { isEditing }
    override var canBecomeMain: Bool { false }

    func claimsMouse(at screenPoint: NSPoint) -> Bool {
        guard !isMinimized else { return false }
        if barPanel.frame.contains(screenPoint) { return true }
        guard frame.contains(screenPoint) else { return false }
        let local = NSPoint(x: screenPoint.x - frame.minX, y: screenPoint.y - frame.minY)
        return canvas.claims(local)
    }

    func trackMouse(at screenPoint: NSPoint) {
        guard !isMinimized else {
            ignoresMouseEvents = true
            return
        }
        if isEditing {
            ignoresMouseEvents = false
            return
        }
        ignoresMouseEvents = !claimsMouse(at: screenPoint)
    }

    func minimizeAway() {
        isMinimized = true
        ignoresMouseEvents = true
        orderOut(nil)
        barPanel.orderOut(nil)
    }

    func restore() {
        isMinimized = false
        applyChrome()
    }

    override func close() {
        barPanel.close()
        super.close()
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        super.setFrame(frameRect, display: displayFlag)
        syncBar()
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate: Bool) {
        super.setFrame(frameRect, display: displayFlag, animate: animate)
        syncBar()
    }

    private func syncBar() {
        let barFrame = NSRect(
            x: frame.minX + HolderMetrics.barInset,
            y: frame.maxY - HolderMetrics.barHeight - HolderMetrics.barInset,
            width: HolderMetrics.barWidth,
            height: HolderMetrics.barHeight
        )
        barPanel.setFrame(barFrame, display: true)
        guard !isMinimized else { return }
        barPanel.orderFrontRegardless()
    }

    private func applyChrome() {
        canvas.isEditing = isEditing
        canvas.needsDisplay = true
        invalidateCursorRects(for: canvas)
        guard !isMinimized else { return }
        level = .floating
        if isEditing {
            ignoresMouseEvents = false
        } else {
            trackMouse(at: NSEvent.mouseLocation)
            resignKey()
        }
        orderFrontRegardless()
        syncBar()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            holderDelegate?.holderPanelDidRequestExitEdit(self)
            return
        }
        super.keyDown(with: event)
    }
}

private enum ResizeEdge {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight
}

private final class HolderBarButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Sits above every snapped window so the minimize and delete buttons stay reachable.
private final class HolderBarView: NSView {
    var onMinimize: (() -> Void)?
    var onDelete: (() -> Void)?

    private let minimizeButton = HolderBarButton()
    private let deleteButton = HolderBarButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.cornerRadius = HolderMetrics.barHeight / 2
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.9).cgColor
        configure(minimizeButton, symbol: "minus", tint: .black, bezel: .systemYellow, tip: "Minimize all windows in this holder")
        minimizeButton.action = #selector(minimizeAll)
        configure(deleteButton, symbol: "xmark", tint: .white, bezel: .systemRed, tip: "Delete all windows in this holder")
        deleteButton.action = #selector(deleteAll)
        addSubview(minimizeButton)
        addSubview(deleteButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let buttonSize = HolderMetrics.buttonSize
        let y = (bounds.height - buttonSize) / 2
        deleteButton.frame = NSRect(x: HolderMetrics.barPadding, y: y, width: buttonSize, height: buttonSize)
        minimizeButton.frame = NSRect(
            x: HolderMetrics.barPadding + buttonSize + HolderMetrics.buttonGap,
            y: y,
            width: buttonSize,
            height: buttonSize
        )
    }

    @objc private func minimizeAll() {
        onMinimize?()
    }

    @objc private func deleteAll() {
        onDelete?()
    }

    private func configure(_ button: HolderBarButton, symbol: String, tint: NSColor, bezel: NSColor, tip: String) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(configuration)
        button.bezelStyle = .circular
        button.bezelColor = bezel
        button.contentTintColor = tint
        button.toolTip = tip
        button.target = self
        button.imageScaling = .scaleProportionallyDown
    }
}

private final class HolderCanvasView: NSView {
    var isEditing = false {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    var isSelected = false {
        didSet { needsDisplay = true }
    }

    var onFrameChanged: (() -> Void)?
    var onSelect: (() -> Void)?
    var onExitEdit: (() -> Void)?

    private var resizeEdge: ResizeEdge?
    private var dragStartMouse: NSPoint = .zero
    private var dragStartFrame: NSRect = .zero
    private var draggingFrame = false
    private let grabMargin: CGFloat = 10
    private let minimumSize = NSSize(width: 280, height: 180)

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { isEditing }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func claims(_ local: NSPoint) -> Bool {
        guard bounds.contains(local) else { return false }
        return isEditing
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEditing, bounds.contains(point) else { return nil }
        return self
    }

    override func draw(_ dirtyRect: NSRect) {
        let outer = bounds.insetBy(dx: 2, dy: 2)
        guard outer.width > 2, outer.height > 2 else { return }
        let border = NSBezierPath(roundedRect: outer, xRadius: 8, yRadius: 8)
        border.lineWidth = isEditing && isSelected ? 4 : 3
        let color = (isEditing && isSelected) ? NSColor.controlAccentColor : NSColor.systemOrange
        color.setStroke()
        border.stroke()

        if isEditing {
            let content = bounds.insetBy(dx: 4, dy: 4)
            drawHandles(around: content)
        }
    }

    override func resetCursorRects() {
        discardCursorRects()
        guard isEditing else { return }
        let margin = grabMargin
        let width = bounds.width
        let height = bounds.height
        guard width > margin * 2, height > margin * 2 else {
            addCursorRect(bounds, cursor: .openHand)
            return
        }
        addCursorRect(NSRect(x: 0, y: height - margin, width: margin, height: margin), cursor: .crosshair)
        addCursorRect(NSRect(x: width - margin, y: height - margin, width: margin, height: margin), cursor: .crosshair)
        addCursorRect(NSRect(x: 0, y: 0, width: margin, height: margin), cursor: .crosshair)
        addCursorRect(NSRect(x: width - margin, y: 0, width: margin, height: margin), cursor: .crosshair)
        addCursorRect(NSRect(x: margin, y: height - margin, width: width - margin * 2, height: margin), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: margin, y: 0, width: width - margin * 2, height: margin), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: margin, width: margin, height: height - margin * 2), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: width - margin, y: margin, width: margin, height: height - margin * 2), cursor: .resizeLeftRight)
        addCursorRect(bounds.insetBy(dx: margin, dy: margin), cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEditing, let window else { return }
        let local = convert(event.locationInWindow, from: nil)
        onSelect?()
        window.makeKey()
        draggingFrame = true
        resizeEdge = edge(at: local)
        dragStartMouse = NSEvent.mouseLocation
        dragStartFrame = window.frame
        if resizeEdge == nil {
            NSCursor.closedHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard draggingFrame, isEditing, let window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - dragStartMouse.x
        let dy = mouse.y - dragStartMouse.y
        let next: NSRect
        if let resizeEdge {
            next = resizedFrame(from: dragStartFrame, edge: resizeEdge, dx: dx, dy: dy)
        } else {
            next = dragStartFrame.offsetBy(dx: dx, dy: dy)
        }
        window.setFrame(next, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        let movedFrame = draggingFrame && window?.frame != dragStartFrame
        draggingFrame = false
        resizeEdge = nil
        if isEditing {
            NSCursor.openHand.set()
            if movedFrame {
                onFrameChanged?()
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onExitEdit?()
            return
        }
        super.keyDown(with: event)
    }

    private func edge(at point: NSPoint) -> ResizeEdge? {
        let onLeft = point.x <= grabMargin
        let onRight = point.x >= bounds.width - grabMargin
        let onBottom = point.y <= grabMargin
        let onTop = point.y >= bounds.height - grabMargin
        switch (onLeft, onRight, onTop, onBottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return nil
        }
    }

    private func resizedFrame(from start: NSRect, edge: ResizeEdge, dx: CGFloat, dy: CGFloat) -> NSRect {
        var originX = start.origin.x
        var originY = start.origin.y
        var width = start.width
        var height = start.height

        switch edge {
        case .left, .topLeft, .bottomLeft:
            width = max(minimumSize.width, start.width - dx)
            originX = start.maxX - width
        case .right, .topRight, .bottomRight:
            width = max(minimumSize.width, start.width + dx)
        case .top, .bottom:
            break
        }

        switch edge {
        case .bottom, .bottomLeft, .bottomRight:
            height = max(minimumSize.height, start.height - dy)
            originY = start.maxY - height
        case .top, .topLeft, .topRight:
            height = max(minimumSize.height, start.height + dy)
        case .left, .right:
            break
        }

        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    private func drawHandles(around rect: NSRect) {
        guard rect.width > 8, rect.height > 8 else { return }
        let size: CGFloat = 8
        let xs = [rect.minX, rect.midX - size / 2, rect.maxX - size]
        let ys = [rect.minY, rect.midY - size / 2, rect.maxY - size]
        for y in ys {
            for x in xs {
                if x == xs[1], y == ys[1] { continue }
                let handle = NSRect(x: x, y: y, width: size, height: size)
                NSColor.white.setFill()
                handle.fill()
                NSColor.black.withAlphaComponent(0.7).setStroke()
                NSBezierPath(rect: handle).stroke()
            }
        }
    }
}
