---
name: widget vocab and browser port
overview: "Expand the Pharo-driven widget protocol with four new types -- NSScrollView, NSSplitView, NSTableView, NSTextView -- then re-implement the System Browser entirely in Pharo on top of them. The native shell stays small and generic; the System Browser becomes a Pharo class composing widget wrappers, with each selection event handled in-image. End checkpoint: the new \"Native System Browser (Pharo-driven)\" menu item opens a window visually equivalent to v1's, but every pane is a real NSTableView and every line of orchestration logic lives in Pharo and is hot-reloadable."
todos:
  - id: scrollview
    content: Add ScrollViewFactory to the shell + PNNSScrollView wrapper (documentView role, scrollbar props)
    status: completed
  - id: splitview
    content: Add SplitViewFactory + PNNSSplitView wrapper (vertical, arrangedSubview role, dividerPositions)
    status: completed
  - id: tableview
    content: Add TableViewFactory with TableModel data source/delegate + PNNSTableView wrapper (columns, rows bulk-replace, selectionChanged event, selectedRow getter/setter)
    status: completed
  - id: textview
    content: Add TextViewFactory configured for code display + PNNSTextView wrapper (string, attributedRuns, editable -- stays false in v2)
    status: completed
  - id: host-register
    content: Update WidgetHost.registerDefaults to include the four new factories
    status: completed
  - id: tools-package
    content: Create PharoNative-AppKit-Tools package with PNSystemBrowser class that composes the wrappers and orchestrates selection cascades against PackageOrganizer / SystemNavigation
    status: completed
  - id: tools-menu
    content: Add PNToolsMenu in PharoNative-AppKit-Tools with worldMenu pragma adding 'Native System Browser (Pharo-driven)' under Browse
    status: completed
  - id: baseline-wire
    content: Wire PharoNative-AppKit-Tools into BaselineOfPharoNativeBridge so install.sh picks it up
    status: completed
  - id: smoke-test-browser
    content: "End-to-end smoke test: rebuild shell, reinstall bridge, launch image, click new menu item, verify all four panes populate and source pane shows method bodies"
    status: completed
isProject: false
---

## Architecture

The widget protocol stays exactly as designed; we just register four more factories on the shell and four more wrappers in Pharo. The System Browser is a new Pharo class that wires them together.

```mermaid
flowchart TB
  subgraph PharoImg["Pharo image"]
    Browser["PNSystemBrowser<br/>(all browser logic)"]
    Wrappers["PNNSWindow + PNNSSplitView<br/>+ PNNSScrollView + PNNSTableView<br/>+ PNNSTextView"]
    Adaptor["PNAppKitAdaptor"]
    Browser --> Wrappers --> Adaptor
  end
  subgraph Shell["PharoNativeShell.app (unchanged surface)"]
    Host["WidgetHost"]
    OldFac["Window/View/Button/TextField"]
    NewFac["ScrollView/SplitView/TableView/TextView"]
    Host --> OldFac
    Host --> NewFac
  end
  Adaptor <-->|"newline-delimited JSON"| Host
```

User flow once shipped:
1. World menu -> "Native System Browser (Pharo-driven)".
2. `PNToolsMenu` evaluates `PNSystemBrowser open`.
3. `PNSystemBrowser` creates the wrapper tree, populates packages from `PackageOrganizer default`, and shows the window.
4. Each table selection invokes a Pharo block which queries the image and calls `rows:` on the next table or `string:` on the text view.

## Wire protocol additions

New types: `NSScrollView`, `NSSplitView`, `NSTableView`, `NSTextView`.

New child roles:
- `documentView` -- `NSScrollView` accepts exactly one. The shell binds the child as `scrollView.documentView`.
- `arrangedSubview` -- `NSSplitView` accepts many; preserves insertion order.

New properties (per type):
- `NSScrollView`: `hasVerticalScroller` (bool), `hasHorizontalScroller` (bool), `borderType` (`"none" | "line" | "bezel" | "groove"`), `frame`.
- `NSSplitView`: `vertical` (bool; default false = vertical divider with horizontally-arranged children, matching AppKit), `dividerStyle` (`"thin" | "thick" | "paneSplitter"`), `dividerPositions` (`[Number]`), `frame`.
- `NSTableView`: `columns` (`[{"title": String, "identifier": String, "width": Number?}]` -- replace), `rows` (`[[String]]` parallel to columns -- bulk replace + reloadData), `selectedRow` (Number -- programmatic selection, `-1` clears), `usesAlternatingRowBackgroundColors` (bool), `frame`.
- `NSTextView`: `string` (String -- replace contents), `attributedRuns` (`[{"location": Int, "length": Int, "foreground": "green"|"red"|"blue"|...}]` -- optional styling, applied after `string`), `editable` (bool, false in v2), `font` (`{family: String, size: Number}`), `frame`.

New events:
- `NSTableView` `selectionChanged` -> `{ "row": Number }` (-1 when nothing selected).

`widget.invoke` additions: none required for v2.

## Native shell -- new files

All under [pharo-native-shell/Sources/PharoNativeShell/Widget/Factories/](pharo-native-shell/Sources/PharoNativeShell/Widget/Factories):

- `ScrollViewFactory.swift` -- creates `NSScrollView` with sensible defaults; child role `documentView` sets `scrollView.documentView` and, when the document is an `NSTableView`, also configures `tv.frame = scrollView.contentSize` and `tv.autoresizingMask = [.width]`.
- `SplitViewFactory.swift` -- creates `NSSplitView`; `vertical` true means horizontal stack; `addArrangedSubview` on each child. `dividerPositions` applied via `setPosition(_:ofDividerAt:)` after the next layout pass (use `DispatchQueue.main.async`).
- `TableViewFactory.swift` -- the big one. Creates an `NSTableView`. Hosts a small `TableModel` `NSObject` subclass that conforms to `NSTableViewDataSource` + `NSTableViewDelegate`. `columns` replaces `tableView.tableColumns` with `NSTableColumn`s identified by the provided identifier. `rows` swaps a `[[String]]` model and calls `reloadData()`. `selectedRow` calls `selectRowIndexes:byExtendingSelection:`. `selectionChanged` subscribes via `tableViewSelectionDidChange:` and emits `{row}`. Cells use simple `NSTextField`-style view via `makeView(withIdentifier:)`.
- `TextViewFactory.swift` -- creates an `NSTextView` configured for code display (monospaced font, no rich text, no automatic substitutions, disabled by default). `string` writes through `textStorage.mutableString`. `attributedRuns` walks the array, applying `NSColor`s for the listed runs over the current text storage. `editable=false` in v2.

Update [WidgetHost.swift](pharo-native-shell/Sources/PharoNativeShell/Widget/WidgetHost.swift) `registerDefaults` to include the four new factories.

## Pharo wrappers -- additions to `PharoNative-AppKit-Widgets`

All under [pharo-bridge/src/PharoNative-AppKit-Widgets/](pharo-bridge/src/PharoNative-AppKit-Widgets):

- `PNNSScrollView` (`widgetTypeName: 'NSScrollView'`) -- `documentView: aWidget` sends `addChild:role: 'documentView'`. Plus `hasVerticalScroller:`, `hasHorizontalScroller:`, `borderType:`.
- `PNNSSplitView` (`'NSSplitView'`) -- `vertical:`, `addArrangedSubview:`, `dividerPositions:` (takes a Smalltalk array of Numbers and ships it as an Array).
- `PNNSTableView` (`'NSTableView'`) -- `columns: anArrayOfDictionaries`, `rows: anArrayOfArrays`, `selectedRow:`, `onSelectionChanged: aBlock` (block receives the row index as an integer; -1 means deselect).
- `PNNSTextView` (`'NSTextView'`) -- `string:`, `attributedRuns:`, `editable:`. Stays read-only in v2.

## New package `PharoNative-AppKit-Tools`

- `pharo-bridge/src/PharoNative-AppKit-Tools/package.st`
- `PNSystemBrowser.class.st` -- holds wrapper instance vars (`window`, `outerSplit`, `topSplit`, `packagesTable`, `classesTable`, `protocolsTable`, `methodsTable`, `sourceTextView`, `packages`, `classes`, `protocols`, `methods`). Class-side `open` constructs and returns an instance. The build method:
  1. Builds an outer vertical `PNNSSplitView`; top half = horizontal `PNNSSplitView`, bottom half = scrolled `PNNSTextView`.
  2. Inside the horizontal split, four scrolled `PNNSTableView`s with single columns titled Packages / Classes / Protocols / Methods.
  3. Wires `onSelectionChanged:` blocks for each table that re-query the image and re-populate the next column down the chain.
  4. Initial `populatePackages` reads `PackageOrganizer default packages` (already used in [PNBridgeHandlers.class.st](pharo-bridge/src/PharoNative-Bridge-Core/PNBridgeHandlers.class.st)).
  5. `onWillClose:` on the window calls `destroyAll` which destroys every wrapper.
- `PNToolsMenu.class.st` -- world menu pragma adds "Native System Browser (Pharo-driven)" under `#Browsing` with order: 2 (sits below the v1 entry at order 1 so both are visible during the migration).

Add the new package to [BaselineOfPharoNativeBridge.class.st](pharo-bridge/src/BaselineOfPharoNativeBridge/BaselineOfPharoNativeBridge.class.st) so [install.sh](pharo-bridge/scripts/install.sh) picks it up.

## v2 smoke test

After `pharo-native-shell/scripts/build.sh` + `pharo-bridge/scripts/install.sh`:

1. Launch the bootstrapped image with GUI.
2. World menu -> Browse -> "Native System Browser (Pharo-driven)".
3. A native window opens with the same four-pane layout as the v1 fat-client browser.
4. Clicking a package populates classes; clicking a class populates protocols (and seeds methods with no-protocol-filter); clicking a protocol filters methods; clicking a method shows source in the bottom pane.
5. Resizing the window and dragging dividers behaves natively.
6. Closing the window destroys all wrappers (verified by `PNSystemBrowser allInstances` returning empty after a GC, or by checking that the shell registry is empty -- could add `shell.ping` style introspection later).

If step 4 works end to end, the architecture proves itself a second time on a non-trivial UI.

## Out of scope for this plan

- Syntax highlighting in the new browser. v2 ships plain text in the source pane; we can reintroduce the Swift highlighter or write a Pharo equivalent emitting `attributedRuns` as a follow-up.
- Editing methods. Source view stays read-only; the v1 fat-client browser was also read-only.
- Lazy / streaming row delivery on NSTableView (bulk-replace `rows` is good for System Browser sizes; revisit if we see jank).
- Replacing or removing the v1 fat-client browser. It stays in the image; the menu has both entries.
- Native Debugger / Inspector / Playground -- each becomes its own plan after the System Browser proves the pattern.