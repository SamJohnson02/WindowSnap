import Cocoa

/// One way to tile a fixed number of windows so they share edges and reach the holder corners.
struct HolderLayout: Equatable {
    let name: String
    /// Unit rectangles. Origin is the bottom-left, and each edge is a fraction of the holder.
    let slots: [CGRect]

    func frames(in content: NSRect) -> [NSRect] {
        slots.map { slot in
            let x = content.minX + slot.minX * content.width
            let y = content.minY + slot.minY * content.height
            let endX = content.minX + slot.maxX * content.width
            let endY = content.minY + slot.maxY * content.height
            return NSRect(x: x, y: y, width: endX - x, height: endY - y)
        }
    }

    /// Layouts that fit `count` windows. The first one is the default.
    static func options(for count: Int) -> [HolderLayout] {
        guard count > 0 else { return [] }
        if count == 1 {
            return [HolderLayout(name: "Fill", slots: [CGRect(x: 0, y: 0, width: 1, height: 1)])]
        }

        var layouts = [grid(count: count), columns(count: count), rows(count: count)]
        if count >= 3 {
            layouts.append(largeLeft(count: count))
            layouts.append(largeRight(count: count))
        }
        switch count {
        case 3:
            layouts.append(bands(top: 1, bottom: 2, name: "One over two"))
        case 4:
            layouts.append(bands(top: 1, bottom: 3, name: "One over three"))
            layouts.append(bands(top: 3, bottom: 1, name: "Three over one"))
        case 5:
            layouts.append(bands(top: 2, bottom: 3, name: "Two over three"))
        default:
            break
        }
        if count >= 4 {
            for columnCount in 2..<count where count.isMultiple(of: columnCount) {
                let rowCount = count / columnCount
                guard rowCount > 1 else { continue }
                layouts.append(evenGrid(columns: columnCount, rows: rowCount, name: "\(columnCount) × \(rowCount)"))
            }
        }

        var unique: [HolderLayout] = []
        for layout in layouts {
            if let index = unique.firstIndex(where: { sameSlots($0.slots, layout.slots) }) {
                if unique[index].name == "Grid", layout.name != "Grid" {
                    unique[index] = layout
                }
                continue
            }
            unique.append(layout)
        }
        return unique
    }

    private static func grid(count: Int) -> HolderLayout {
        let columns = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        var slots: [CGRect] = []
        var index = 0
        for rowFromTop in 0..<rows {
            let rowCount = min(columns, count - index)
            let vertical = split(rows - 1 - rowFromTop, of: rows)
            for column in 0..<rowCount {
                let horizontal = split(column, of: rowCount)
                slots.append(CGRect(x: horizontal.origin, y: vertical.origin, width: horizontal.size, height: vertical.size))
                index += 1
            }
        }
        let name = count == 2 ? "Side by side" : (count == 3 ? "Two over one" : "Grid")
        return HolderLayout(name: name, slots: slots)
    }

    private static func columns(count: Int) -> HolderLayout {
        let slots = (0..<count).map { column in
            let horizontal = split(column, of: count)
            return CGRect(x: horizontal.origin, y: 0, width: horizontal.size, height: 1)
        }
        let name = count == 2 ? "Side by side" : "Columns"
        return HolderLayout(name: name, slots: slots)
    }

    private static func rows(count: Int) -> HolderLayout {
        let slots = (0..<count).map { rowFromTop in
            let vertical = split(count - 1 - rowFromTop, of: count)
            return CGRect(x: 0, y: vertical.origin, width: 1, height: vertical.size)
        }
        let name = count == 2 ? "Stacked" : "Rows"
        return HolderLayout(name: name, slots: slots)
    }

    private static func largeLeft(count: Int) -> HolderLayout {
        let side = count - 1
        var slots = [CGRect(x: 0, y: 0, width: 0.5, height: 1)]
        for rowFromTop in 0..<side {
            let vertical = split(side - 1 - rowFromTop, of: side)
            slots.append(CGRect(x: 0.5, y: vertical.origin, width: 0.5, height: vertical.size))
        }
        return HolderLayout(name: "Large on the left", slots: slots)
    }

    private static func largeRight(count: Int) -> HolderLayout {
        let side = count - 1
        var slots: [CGRect] = []
        for rowFromTop in 0..<side {
            let vertical = split(side - 1 - rowFromTop, of: side)
            slots.append(CGRect(x: 0, y: vertical.origin, width: 0.5, height: vertical.size))
        }
        slots.append(CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        return HolderLayout(name: "Large on the right", slots: slots)
    }

    private static func bands(top: Int, bottom: Int, name: String) -> HolderLayout {
        var slots: [CGRect] = []
        for column in 0..<top {
            let horizontal = split(column, of: top)
            slots.append(CGRect(x: horizontal.origin, y: 0.5, width: horizontal.size, height: 0.5))
        }
        for column in 0..<bottom {
            let horizontal = split(column, of: bottom)
            slots.append(CGRect(x: horizontal.origin, y: 0, width: horizontal.size, height: 0.5))
        }
        return HolderLayout(name: name, slots: slots)
    }

    private static func evenGrid(columns: Int, rows: Int, name: String) -> HolderLayout {
        var slots: [CGRect] = []
        for rowFromTop in 0..<rows {
            let vertical = split(rows - 1 - rowFromTop, of: rows)
            for column in 0..<columns {
                let horizontal = split(column, of: columns)
                slots.append(CGRect(x: horizontal.origin, y: vertical.origin, width: horizontal.size, height: vertical.size))
            }
        }
        return HolderLayout(name: name, slots: slots)
    }

    private static func split(_ index: Int, of count: Int) -> (origin: CGFloat, size: CGFloat) {
        let origin = CGFloat(index) / CGFloat(count)
        let end = CGFloat(index + 1) / CGFloat(count)
        return (origin, end - origin)
    }

    private static func sameSlots(_ lhs: [CGRect], _ rhs: [CGRect]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            abs(left.minX - right.minX) < 0.001
                && abs(left.minY - right.minY) < 0.001
                && abs(left.width - right.width) < 0.001
                && abs(left.height - right.height) < 0.001
        }
    }
}
