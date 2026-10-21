import Cocoa

/// The window shown when WindowSnap opens. The user checks open apps, picks a layout, and assigns each app to a spot.
final class PickerWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let holderManager: HolderManager
    private let window: NSWindow
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "No other applications are open.")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let selectAllButton = NSButton(title: "Select All", target: nil, action: nil)
    private let layoutPopup = NSPopUpButton()
    private let layoutRow = NSStackView()
    private let preview = SlotPreviewView()
    private let placeButton = NSButton(title: "Place in Holder", target: nil, action: nil)
    private var apps: [OpenApplication] = []
    private var selectedPIDs = Set<pid_t>()
    private var layouts: [HolderLayout] = []
    private var layoutIndex = 0
    private var slotAssignments: [pid_t] = []
    private var updatingControls = false

    init(holderManager: HolderManager) {
        self.holderManager = holderManager
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "WindowSnap"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 440, height: 640)
        window.contentView = makeContentView()
        window.center()
    }

    func show() {
        reloadApps()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeContentView() -> NSView {
        let content = NSView()

        let title = NSTextField(labelWithString: "Choose apps")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let explanation = NSTextField(wrappingLabelWithString: "Select the open apps to put in the holder. Pick a layout for that number, then choose which app goes in each spot.")
        explanation.textColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("apps"))
        column.resizingMask = .autoresizingMask
        column.width = 440
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.rowHeight = 44
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        if #available(macOS 11.0, *) {
            tableView.style = .fullWidth
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = tableView
        scroll.borderType = .bezelBorder

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isHidden = true

        selectAllButton.target = self
        selectAllButton.action = #selector(toggleSelectAll)
        selectAllButton.bezelStyle = .rounded

        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refresh))
        refresh.bezelStyle = .rounded

        placeButton.target = self
        placeButton.action = #selector(placeSelected)
        placeButton.bezelStyle = .rounded
        placeButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [selectAllButton, refresh, spacer, placeButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY

        let layoutLabel = NSTextField(labelWithString: "Layout")
        layoutPopup.target = self
        layoutPopup.action = #selector(layoutChanged)
        layoutPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        layoutRow.orientation = .horizontal
        layoutRow.alignment = .centerY
        layoutRow.spacing = 8
        layoutRow.addArrangedSubview(layoutLabel)
        layoutRow.addArrangedSubview(layoutPopup)

        preview.onAssign = { [weak self] index, pid in
            self?.assign(pid, to: index)
        }

        let stack = NSStackView(views: [title, explanation, scroll, emptyLabel, buttons, layoutRow, preview, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.detachesHiddenViews = true
        stack.setCustomSpacing(6, after: title)
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        preview.setContentHuggingPriority(.defaultHigh, for: .vertical)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            emptyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            layoutRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preview.heightAnchor.constraint(equalToConstant: 200),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return content
    }

    private func reloadApps() {
        apps = WindowTracker.openApplications(excludingPID: getpid())
        selectedPIDs = selectedPIDs.filter { pid in apps.contains { $0.pid == pid } }
        emptyLabel.isHidden = !apps.isEmpty
        tableView.isHidden = apps.isEmpty
        tableView.reloadData()
        refreshArrangement(keepingLayoutName: true)
    }

    private func refreshArrangement(keepingLayoutName: Bool) {
        let previousName = layouts.indices.contains(layoutIndex) ? layouts[layoutIndex].name : nil
        layouts = HolderLayout.options(for: selectedPIDs.count)
        if keepingLayoutName, let previousName, let match = layouts.firstIndex(where: { $0.name == previousName }) {
            layoutIndex = match
        } else if layoutIndex >= layouts.count {
            layoutIndex = 0
        }
        syncAssignments()
        rebuildLayoutPopup()
        updatePreview()
        updateSelectAllButton()
        updatePlaceButton()
    }

    private func syncAssignments() {
        var assigned = slotAssignments.filter { selectedPIDs.contains($0) }
        for app in apps where selectedPIDs.contains(app.pid) && !assigned.contains(app.pid) {
            assigned.append(app.pid)
        }
        slotAssignments = assigned
    }

    private func rebuildLayoutPopup() {
        updatingControls = true
        layoutPopup.removeAllItems()
        for layout in layouts {
            layoutPopup.addItem(withTitle: layout.name)
        }
        if layouts.indices.contains(layoutIndex) {
            layoutPopup.selectItem(at: layoutIndex)
        }
        layoutPopup.isEnabled = layouts.count > 1
        let showLayout = !layouts.isEmpty
        layoutRow.isHidden = !showLayout
        preview.isHidden = !showLayout
        updatingControls = false
    }

    private func updatePreview() {
        guard layouts.indices.contains(layoutIndex) else {
            preview.update(layout: nil, apps: [], assignments: [])
            return
        }
        let chosen = apps.filter { selectedPIDs.contains($0.pid) }
        preview.update(layout: layouts[layoutIndex], apps: chosen, assignments: slotAssignments)
    }

    private func updateSelectAllButton() {
        let allSelected = !apps.isEmpty && selectedPIDs.count == apps.count
        selectAllButton.title = allSelected ? "Deselect All" : "Select All"
        selectAllButton.isEnabled = !apps.isEmpty
    }

    private func updatePlaceButton() {
        let count = selectedPIDs.count
        placeButton.isEnabled = count > 0
        placeButton.title = count == 0 ? "Place in Holder" : "Place \(count) in Holder"
    }

    private func setStatus(_ message: String?) {
        statusLabel.stringValue = message ?? ""
        statusLabel.isHidden = message == nil
    }

    private func assign(_ pid: pid_t, to index: Int) {
        guard slotAssignments.indices.contains(index) else { return }
        if let other = slotAssignments.firstIndex(of: pid), other != index {
            slotAssignments.swapAt(index, other)
        } else {
            slotAssignments[index] = pid
        }
        setStatus(nil)
        updatePreview()
    }

    @objc private func toggleSelectAll() {
        if !apps.isEmpty, selectedPIDs.count == apps.count {
            selectedPIDs.removeAll()
        } else {
            selectedPIDs = Set(apps.map(\.pid))
        }
        setStatus(nil)
        tableView.reloadData()
        refreshArrangement(keepingLayoutName: true)
    }

    @objc private func refresh() {
        setStatus(nil)
        reloadApps()
    }

    @objc private func layoutChanged() {
        guard !updatingControls else { return }
        layoutIndex = max(layoutPopup.indexOfSelectedItem, 0)
        setStatus(nil)
        updatePreview()
    }

    @objc private func placeSelected() {
        guard WindowTracker.isTrusted else {
            WindowTracker.promptForTrustIfNeeded()
            setStatus("Turn on Accessibility for WindowSnap in System Settings, then click Place again.")
            return
        }
        guard layouts.indices.contains(layoutIndex) else { return }
        let byPID = Dictionary(uniqueKeysWithValues: apps.map { ($0.pid, $0) })
        let chosen = slotAssignments.compactMap { byPID[$0] }
        let placed = holderManager.placeWindows(chosen.map(\.window), layout: layouts[layoutIndex])
        guard placed > 0 else {
            setStatus("WindowSnap could not move those apps. Click Refresh and try again.")
            return
        }
        setStatus(nil)
        window.orderOut(nil)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        apps.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("app-row")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? AppPickCell ?? AppPickCell()
        cell.identifier = identifier
        let app = apps[row]
        cell.configure(app: app, checked: selectedPIDs.contains(app.pid)) { [weak self] checked in
            guard let self else { return }
            if checked {
                self.selectedPIDs.insert(app.pid)
            } else {
                self.selectedPIDs.remove(app.pid)
            }
            self.setStatus(nil)
            self.refreshArrangement(keepingLayoutName: true)
        }
        return cell
    }
}

/// Diagram of the chosen layout. Each spot is a menu of the selected apps.
private final class SlotPreviewView: NSView {
    var onAssign: ((Int, pid_t) -> Void)?
    private var arrangement: HolderLayout?
    private var buttons: [NSPopUpButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.systemOrange.cgColor
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(layout: HolderLayout?, apps: [OpenApplication], assignments: [pid_t]) {
        arrangement = layout
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        guard let layout, layout.slots.count == assignments.count else { return }
        for (index, pid) in assignments.enumerated() {
            let button = NSPopUpButton()
            button.isBordered = true
            button.bezelStyle = .recessed
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11)
            button.target = self
            button.action = #selector(picked(_:))
            button.tag = index
            if let cell = button.cell as? NSPopUpButtonCell {
                cell.lineBreakMode = .byTruncatingTail
            }
            for app in apps {
                button.addItem(withTitle: app.name)
                let item = button.lastItem
                item?.image = app.icon
                item?.representedObject = NSNumber(value: app.pid)
            }
            if let match = apps.firstIndex(where: { $0.pid == pid }) {
                button.selectItem(at: match)
            }
            addSubview(button)
            buttons.append(button)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let arrangement else { return }
        let area = bounds.insetBy(dx: 6, dy: 6)
        for (slot, button) in zip(arrangement.slots, buttons) {
            let x = area.minX + slot.minX * area.width
            let y = area.minY + slot.minY * area.height
            let endX = area.minX + slot.maxX * area.width
            let endY = area.minY + slot.maxY * area.height
            button.frame = NSRect(x: x, y: y, width: endX - x, height: endY - y).insetBy(dx: 3, dy: 3)
        }
    }

    @objc private func picked(_ sender: NSPopUpButton) {
        guard let number = sender.selectedItem?.representedObject as? NSNumber else { return }
        onAssign?(sender.tag, pid_t(number.int32Value))
    }
}

private final class AppPickCell: NSTableCellView {
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private var onToggle: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        checkbox.target = self
        checkbox.action = #selector(toggled)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameField.lineBreakMode = .byTruncatingTail
        nameField.font = .systemFont(ofSize: 13)
        for item in [checkbox, iconView, nameField] {
            item.translatesAutoresizingMaskIntoConstraints = false
            addSubview(item)
        }
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(app: OpenApplication, checked: Bool, onToggle: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
        checkbox.state = checked ? .on : .off
        checkbox.toolTip = app.name
        iconView.image = app.icon
        nameField.stringValue = app.name
    }

    @objc private func toggled() {
        onToggle?(checkbox.state == .on)
    }
}
