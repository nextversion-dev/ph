import AppKit

/// Wraps NSOutlineView. Pharo ships a tree of items via the `items`
/// property. Each item is `{ id: String, label: String, children?: [items] }`.
/// Identity is the string `id`; selection events report the selected
/// item's id. Programmatic selection / expansion is also by id.
///
/// Properties:
///   columns        [{title, identifier, width?}]
///   items          tree of nodes
///   selectedItem   String (an item id), or null
///   expandedItems  [String] -- ids to expand on the next reload
///   indentation    Number -- indentation per level
///   frame          Rect
///   autoresizingMask
///
/// Events:
///   selectionChanged -> { id: String, label: String } | { id: null }
final class OutlineViewFactory: NSObject, WidgetFactory {
    let typeName = "NSOutlineView"

    func create() -> AnyObject {
        let outline = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        outline.headerView = nil
        outline.style = .inset
        outline.usesAlternatingRowBackgroundColors = false
        outline.allowsMultipleSelection = false
        outline.allowsEmptySelection = true
        outline.gridStyleMask = []
        outline.intercellSpacing = NSSize(width: 0, height: 2)
        outline.rowSizeStyle = .small
        outline.indentationPerLevel = 14

        let model = OutlineModel()
        outline.dataSource = model
        outline.delegate = model
        objc_setAssociatedObject(outline, &OutlineViewFactory.modelKey, model, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        return outline
    }

    func setProperty(_ name: String, value: JSONValue, on object: AnyObject) throws {
        guard let outline = object as? NSOutlineView else {
            throw WidgetError.internalError("expected NSOutlineView")
        }
        let model = OutlineViewFactory.model(for: outline)
        switch name {
        case "columns":
            guard let array = value.asArray else {
                throw WidgetError.badRequest("columns expects array of objects")
            }
            for col in outline.tableColumns { outline.removeTableColumn(col) }
            model.columnIdentifiers = []
            for item in array {
                guard let dict = item.asObject else { continue }
                let title = dict["title"]?.asString ?? ""
                let identifier = dict["identifier"]?.asString ?? title
                let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
                col.title = title
                if let w = dict["width"]?.asDouble {
                    col.width = CGFloat(w)
                }
                outline.addTableColumn(col)
                if outline.outlineTableColumn == nil {
                    outline.outlineTableColumn = col
                }
                model.columnIdentifiers.append(identifier)
            }
            let allEmpty = model.columnIdentifiers.count == 1
                && (outline.tableColumns.first?.title.isEmpty ?? false)
            outline.headerView = allEmpty ? nil : NSTableHeaderView()
            outline.reloadData()
        case "items":
            let oldExpansion = model.collectExpandedIds(in: outline)
            model.rootNodes = OutlineNode.parseForest(value)
            model.rebuildIndex()
            outline.reloadData()
            // Re-apply previous expansion where ids survived a re-set, so a
            // filter refresh doesn't collapse everything.
            for id in oldExpansion {
                if let node = model.node(forId: id) {
                    outline.expandItem(node)
                }
            }
        case "selectedItem":
            if case .null = value {
                outline.deselectAll(nil)
            } else if let id = value.asString,
                      let node = model.node(forId: id) {
                let row = outline.row(forItem: node)
                if row >= 0 {
                    outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    outline.scrollRowToVisible(row)
                } else {
                    outline.deselectAll(nil)
                }
            } else {
                outline.deselectAll(nil)
            }
        case "expandedItems":
            guard let array = value.asArray else { return }
            for v in array {
                if let id = v.asString, let node = model.node(forId: id) {
                    outline.expandItem(node)
                }
            }
        case "indentation":
            if let d = value.asDouble { outline.indentationPerLevel = CGFloat(d) }
        case "frame":
            outline.frame = try WidgetProps.parseFrame(value)
        case "autoresizingMask":
            outline.autoresizingMask = WidgetProps.parseAutoresizingMask(value)
        default:
            throw WidgetError.unknownProperty(name)
        }
    }

    func subscribe(_ event: String,
                   on object: AnyObject,
                   widgetId: String,
                   emit: @escaping (String, JSONValue) -> Void) throws {
        guard let outline = object as? NSOutlineView else {
            throw WidgetError.internalError("expected NSOutlineView")
        }
        let model = OutlineViewFactory.model(for: outline)
        switch event {
        case "selectionChanged":
            model.onSelectionChanged = { [weak outline] in
                guard let outline else { return }
                let row = outline.selectedRow
                if row < 0 || row >= outline.numberOfRows {
                    emit("selectionChanged", .object(["id": .null, "label": .null]))
                    return
                }
                if let node = outline.item(atRow: row) as? OutlineNode {
                    emit("selectionChanged", .object([
                        "id": .string(node.id),
                        "label": .string(node.label)
                    ]))
                } else {
                    emit("selectionChanged", .object(["id": .null, "label": .null]))
                }
            }
        default:
            throw WidgetError.unknownEvent(event)
        }
    }

    func tearDown(_ object: AnyObject) {
        guard let outline = object as? NSOutlineView else { return }
        outline.removeFromSuperview()
        objc_setAssociatedObject(outline, &OutlineViewFactory.modelKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static var modelKey: UInt8 = 0

    static func model(for outline: NSOutlineView) -> OutlineModel {
        if let existing = objc_getAssociatedObject(outline, &modelKey) as? OutlineModel {
            return existing
        }
        let m = OutlineModel()
        objc_setAssociatedObject(outline, &modelKey, m, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        outline.dataSource = m
        outline.delegate = m
        return m
    }
}

/// A single outline node holds its id, display label, and child nodes.
/// Identity comparison uses the id string so re-sent trees keep their
/// row associations consistent across a reload.
final class OutlineNode: NSObject {
    let id: String
    let label: String
    var children: [OutlineNode]

    init(id: String, label: String, children: [OutlineNode]) {
        self.id = id
        self.label = label
        self.children = children
        super.init()
    }

    /// Parse a JSON array (or single object) representing a forest.
    static func parseForest(_ value: JSONValue) -> [OutlineNode] {
        if let arr = value.asArray {
            return arr.compactMap { parseNode($0) }
        }
        if let n = parseNode(value) { return [n] }
        return []
    }

    private static func parseNode(_ value: JSONValue) -> OutlineNode? {
        guard let dict = value.asObject,
              let id = dict["id"]?.asString else {
            return nil
        }
        let label = dict["label"]?.asString ?? id
        let kids: [OutlineNode]
        if let childrenVal = dict["children"], let arr = childrenVal.asArray {
            kids = arr.compactMap { parseNode($0) }
        } else {
            kids = []
        }
        return OutlineNode(id: id, label: label, children: kids)
    }
}

final class OutlineModel: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {

    var columnIdentifiers: [String] = []
    var rootNodes: [OutlineNode] = []
    var onSelectionChanged: (() -> Void)?
    private var idIndex: [String: OutlineNode] = [:]

    func rebuildIndex() {
        idIndex.removeAll()
        func walk(_ nodes: [OutlineNode]) {
            for n in nodes {
                idIndex[n.id] = n
                walk(n.children)
            }
        }
        walk(rootNodes)
    }

    func node(forId id: String) -> OutlineNode? {
        return idIndex[id]
    }

    func collectExpandedIds(in outline: NSOutlineView) -> [String] {
        var out: [String] = []
        for (id, node) in idIndex {
            if outline.isItemExpanded(node) {
                out.append(id)
            }
        }
        return out
    }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let node = item as? OutlineNode { return node.children.count }
        return rootNodes.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? OutlineNode { return node.children[index] }
        return rootNodes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let node = item as? OutlineNode { return !node.children.isEmpty }
        return false
    }

    // MARK: NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("PharoNativeShellOutlineCell")
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let text = NSTextField(labelWithString: "")
            text.font = NSFont.systemFont(ofSize: 12)
            text.lineBreakMode = .byTruncatingTail
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.textField = text
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        if let node = item as? OutlineNode {
            cell.textField?.stringValue = node.label
        } else {
            cell.textField?.stringValue = ""
        }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        onSelectionChanged?()
    }
}
