import AppKit

/// Wraps NSTabView. Tabs are added via `addChild` with role
/// `tab:<title>` -- the title-after-the-colon becomes the tab label.
/// Each child becomes the tab's content view.
///
/// Properties:
///   selectedIndex   Int
///   frame, autoresizingMask
///
/// Events:
///   tabSelected -> { index: Int, title: String }
final class TabViewFactory: NSObject, WidgetFactory, NSTabViewDelegate {
    let typeName = "NSTabView"

    private var emitters: [ObjectIdentifier: (Int, String) -> Void] = [:]

    func create() -> AnyObject {
        let tab = NSTabView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        tab.tabViewType = .topTabsBezelBorder
        tab.delegate = self
        return tab
    }

    func setProperty(_ name: String, value: JSONValue, on object: AnyObject) throws {
        guard let tab = object as? NSTabView else {
            throw WidgetError.internalError("expected NSTabView")
        }
        switch name {
        case "selectedIndex":
            let idx = value.asInt ?? -1
            if idx >= 0, idx < tab.tabViewItems.count {
                tab.selectTabViewItem(at: idx)
            }
        case "frame":
            tab.frame = try WidgetProps.parseFrame(value)
        case "autoresizingMask":
            tab.autoresizingMask = WidgetProps.parseAutoresizingMask(value)
        default:
            throw WidgetError.unknownProperty(name)
        }
    }

    func addChild(_ child: AnyObject, role: String, to parent: AnyObject) throws {
        guard let tab = parent as? NSTabView else {
            throw WidgetError.internalError("expected NSTabView parent")
        }
        guard let view = child as? NSView else {
            throw WidgetError.badRequest("NSTabView children must be NSView, got \(type(of: child))")
        }
        // role is `tab:<title>` -- the substring after the first colon
        // becomes the tab title. We allow bare `tab` too for safety.
        let title: String
        if role.hasPrefix("tab:") {
            title = String(role.dropFirst(4))
        } else if role == "tab" {
            title = "Tab \(tab.tabViewItems.count + 1)"
        } else {
            throw WidgetError.badRequest("NSTabView does not accept child role '\(role)'")
        }
        let item = NSTabViewItem(identifier: "\(ObjectIdentifier(view).hashValue)")
        item.label = title
        item.view = view
        tab.addTabViewItem(item)
    }

    func subscribe(_ event: String,
                   on object: AnyObject,
                   widgetId: String,
                   emit: @escaping (String, JSONValue) -> Void) throws {
        guard let tab = object as? NSTabView else {
            throw WidgetError.internalError("expected NSTabView")
        }
        switch event {
        case "tabSelected":
            emitters[ObjectIdentifier(tab)] = { idx, title in
                emit("tabSelected", .object([
                    "index": .int(idx),
                    "title": .string(title)
                ]))
            }
        default:
            throw WidgetError.unknownEvent(event)
        }
    }

    func tearDown(_ object: AnyObject) {
        guard let tab = object as? NSTabView else { return }
        emitters.removeValue(forKey: ObjectIdentifier(tab))
        tab.removeFromSuperview()
    }

    // MARK: NSTabViewDelegate

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard let emit = emitters[ObjectIdentifier(tabView)] else { return }
        let idx = tabViewItem.flatMap { tabView.tabViewItems.firstIndex(of: $0) } ?? -1
        let title = tabViewItem?.label ?? ""
        emit(idx, title)
    }
}
