import AppKit

/// Wraps NSTableView. Backed by a per-table TableModel that holds the
/// rows and serves as NSTableViewDataSource + NSTableViewDelegate.
///
/// Properties:
///   columns                   [{"title", "identifier", "width"?}]
///   rows                      [[String]]  -- parallel to columns
///   selectedRow               Number (-1 to deselect)
///   usesAlternatingRowBackgroundColors  Bool
///   frame                     Rect
///
/// Events:
///   selectionChanged          -> { row: Number, -1 when nothing selected }
///
/// We store the TableModel on the heap via objc_setAssociatedObject so
/// it stays alive as long as the table view does. NSTableView's
/// dataSource and delegate are held weakly so we can't rely on them
/// retaining the model.
final class TableViewFactory: NSObject, WidgetFactory {
    let typeName = "NSTableView"

    func create() -> AnyObject {
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        table.headerView = NSTableHeaderView()
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask = []
        table.style = .inset
        table.rowSizeStyle = .small
        table.intercellSpacing = NSSize(width: 0, height: 2)

        let model = TableModel()
        table.dataSource = model
        table.delegate = model
        objc_setAssociatedObject(table, &TableViewFactory.modelKey, model, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        return table
    }

    func setProperty(_ name: String, value: JSONValue, on object: AnyObject) throws {
        guard let table = object as? NSTableView else {
            throw WidgetError.internalError("expected NSTableView")
        }
        let model = TableViewFactory.model(for: table)
        switch name {
        case "columns":
            guard let array = value.asArray else {
                throw WidgetError.badRequest("columns expects an array of objects")
            }
            // Drop existing columns.
            for col in table.tableColumns { table.removeTableColumn(col) }
            model.columnIdentifiers = []
            for item in array {
                guard let dict = item.asObject else {
                    throw WidgetError.badRequest("columns entry must be an object")
                }
                let title = dict["title"]?.asString ?? ""
                let identifier = dict["identifier"]?.asString ?? title
                let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
                col.title = title
                col.resizingMask = [.autoresizingMask, .userResizingMask]
                if let w = dict["width"]?.asDouble {
                    col.width = CGFloat(w)
                }
                table.addTableColumn(col)
                model.columnIdentifiers.append(identifier)
            }
            // Hide the header when there is a single column with empty title
            // -- matches the System Browser's column-as-label look.
            let allEmpty = model.columnIdentifiers.count == 1
                && (table.tableColumns.first?.title.isEmpty ?? false)
            table.headerView = allEmpty ? nil : NSTableHeaderView()
            table.reloadData()
        case "rows":
            guard let array = value.asArray else {
                throw WidgetError.badRequest("rows expects an array of row arrays")
            }
            var rows: [[String]] = []
            rows.reserveCapacity(array.count)
            for rowVal in array {
                if let cellArr = rowVal.asArray {
                    rows.append(cellArr.map { $0.asString ?? "" })
                } else if let s = rowVal.asString {
                    rows.append([s])
                } else {
                    rows.append([])
                }
            }
            model.rows = rows
            table.reloadData()
        case "selectedRow":
            let idx = value.asInt ?? -1
            if idx < 0 {
                table.deselectAll(nil)
            } else if idx < table.numberOfRows {
                table.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
                table.scrollRowToVisible(idx)
            }
        case "usesAlternatingRowBackgroundColors":
            table.usesAlternatingRowBackgroundColors = value.asBool ?? false
        case "frame":
            table.frame = try WidgetProps.parseFrame(value)
        case "autoresizingMask":
            table.autoresizingMask = WidgetProps.parseAutoresizingMask(value)
        default:
            throw WidgetError.unknownProperty(name)
        }
    }

    func subscribe(_ event: String,
                   on object: AnyObject,
                   widgetId: String,
                   emit: @escaping (String, JSONValue) -> Void) throws {
        guard let table = object as? NSTableView else {
            throw WidgetError.internalError("expected NSTableView")
        }
        let model = TableViewFactory.model(for: table)
        switch event {
        case "selectionChanged":
            model.onSelectionChanged = { [weak table] in
                guard let table else { return }
                emit("selectionChanged", .object(["row": .int(table.selectedRow)]))
            }
        default:
            throw WidgetError.unknownEvent(event)
        }
    }

    func tearDown(_ object: AnyObject) {
        guard let table = object as? NSTableView else { return }
        table.removeFromSuperview()
        objc_setAssociatedObject(table, &TableViewFactory.modelKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    // MARK: associated object plumbing

    private static var modelKey: UInt8 = 0

    static func model(for table: NSTableView) -> TableModel {
        if let existing = objc_getAssociatedObject(table, &modelKey) as? TableModel {
            return existing
        }
        let m = TableModel()
        objc_setAssociatedObject(table, &modelKey, m, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        table.dataSource = m
        table.delegate = m
        return m
    }
}

/// Per-table data source / delegate that owns the row model.
final class TableModel: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    /// One row per outer element; inner element per column, parallel to
    /// columnIdentifiers.
    var rows: [[String]] = []

    /// Identifier per column, used to look up the right cell value.
    var columnIdentifiers: [String] = []

    /// Closure invoked from tableViewSelectionDidChange. May be nil when
    /// nothing is subscribed yet.
    var onSelectionChanged: (() -> Void)?

    // MARK: NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count
    }

    // MARK: NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("PharoNativeShellCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
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
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        let value = cellValue(at: row, columnIdentifier: tableColumn?.identifier.rawValue)
        cell.textField?.stringValue = value
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        onSelectionChanged?()
    }

    // MARK: lookup

    private func cellValue(at row: Int, columnIdentifier: String?) -> String {
        guard row >= 0, row < rows.count else { return "" }
        let columns = rows[row]
        guard let identifier = columnIdentifier,
              let columnIndex = columnIdentifiers.firstIndex(of: identifier) else {
            return columns.first ?? ""
        }
        guard columnIndex < columns.count else { return "" }
        return columns[columnIndex]
    }
}
