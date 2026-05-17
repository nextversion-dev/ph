import AppKit

/// The 4-pane System Browser layout: Packages | Classes | Protocols | Methods
/// across the top, source viewer below.
final class BrowserViewController: NSViewController {

    private let client: BridgeClient

    private let packagesList = ListColumnView(title: "Packages")
    private let classesList = ListColumnView(title: "Classes")
    private let protocolsList = ListColumnView(title: "Protocols")
    private let methodsList = ListColumnView(title: "Methods")

    private let sourceTextView: NSTextView = {
        let tv = NSTextView()
        tv.isEditable = false
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.autoresizingMask = [.width]
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.allowsUndo = false
        return tv
    }()

    private var packages: [PackageInfo] = []
    private var classes: [ClassInfo] = []
    private var protocols: [ProtocolInfo] = []
    private var methods: [String] = []

    private var selectedPackage: PackageInfo? { packages[safe: packagesList.selectedRow] }
    private var selectedClass: ClassInfo? { classes[safe: classesList.selectedRow] }
    private var selectedProtocol: ProtocolInfo? { protocols[safe: protocolsList.selectedRow] }
    private var selectedMethod: String? { methods[safe: methodsList.selectedRow] }

    init(client: BridgeClient) {
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func loadView() {
        let horizontal = NSSplitView()
        horizontal.isVertical = true
        horizontal.dividerStyle = .thin
        horizontal.translatesAutoresizingMaskIntoConstraints = false

        for column in [packagesList, classesList, protocolsList, methodsList] {
            horizontal.addArrangedSubview(column)
        }

        packagesList.delegate = self
        classesList.delegate = self
        protocolsList.delegate = self
        methodsList.delegate = self

        let sourceScroll = NSScrollView()
        sourceScroll.translatesAutoresizingMaskIntoConstraints = false
        sourceScroll.hasVerticalScroller = true
        sourceScroll.hasHorizontalScroller = false
        sourceScroll.autohidesScrollers = true
        sourceScroll.borderType = .noBorder
        sourceScroll.documentView = sourceTextView
        sourceScroll.drawsBackground = false

        let vertical = NSSplitView()
        vertical.isVertical = false
        vertical.dividerStyle = .thin
        vertical.translatesAutoresizingMaskIntoConstraints = false
        vertical.addArrangedSubview(horizontal)
        vertical.addArrangedSubview(sourceScroll)

        let root = NSView()
        root.addSubview(vertical)
        NSLayoutConstraint.activate([
            vertical.topAnchor.constraint(equalTo: root.topAnchor),
            vertical.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            vertical.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            vertical.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        ])
        self.view = root

        DispatchQueue.main.async {
            vertical.setPosition(420, ofDividerAt: 0)
            let third = horizontal.frame.width / 4
            for i in 0..<3 {
                horizontal.setPosition(third * CGFloat(i + 1), ofDividerAt: i)
            }
        }
    }

    func loadPackages() {
        Task { @MainActor in
            do {
                let result = try await client.listPackages()
                self.packages = result
                self.packagesList.set(items: result.map { "\($0.name)  (\($0.classCount))" })
            } catch {
                self.packagesList.showError(error)
            }
        }
    }

    private func loadClasses() {
        guard let pkg = selectedPackage else {
            classes = []; classesList.set(items: [])
            protocols = []; protocolsList.set(items: [])
            methods = []; methodsList.set(items: [])
            sourceTextView.string = ""
            return
        }
        Task { @MainActor in
            do {
                let result = try await client.listClasses(package: pkg.name)
                self.classes = result
                self.classesList.set(items: result.map(\.displayName))
                self.protocols = []; self.protocolsList.set(items: [])
                self.methods = []; self.methodsList.set(items: [])
                self.sourceTextView.string = ""
            } catch {
                self.classesList.showError(error)
            }
        }
    }

    private func loadProtocols() {
        guard let cls = selectedClass else {
            protocols = []; protocolsList.set(items: [])
            methods = []; methodsList.set(items: [])
            sourceTextView.string = ""
            return
        }
        Task { @MainActor in
            do {
                let result = try await client.listProtocols(class: cls.name, side: cls.side)
                self.protocols = result
                self.protocolsList.set(items: result.map { "\($0.name)  (\($0.methodCount))" })
                self.methods = []; self.methodsList.set(items: [])
                self.sourceTextView.string = ""
            } catch {
                self.protocolsList.showError(error)
            }
        }
    }

    private func loadMethods() {
        guard let cls = selectedClass else { return }
        let proto = selectedProtocol?.name
        Task { @MainActor in
            do {
                let result = try await client.listMethods(class: cls.name, side: cls.side, protocolName: proto)
                self.methods = result
                self.methodsList.set(items: result)
                self.sourceTextView.string = ""
            } catch {
                self.methodsList.showError(error)
            }
        }
    }

    private func loadSource() {
        guard let cls = selectedClass, let sel = selectedMethod else {
            sourceTextView.string = ""
            return
        }
        Task { @MainActor in
            do {
                let src = try await client.getSource(class: cls.name, side: cls.side, selector: sel)
                let attr = SmalltalkSyntaxHighlighter.highlight(src.source)
                self.sourceTextView.textStorage?.setAttributedString(attr)
            } catch {
                self.sourceTextView.string = "\"error: \(error)\""
            }
        }
    }
}

extension BrowserViewController: ListColumnViewDelegate {
    func listColumnView(_ column: ListColumnView, didSelectRow row: Int) {
        if column === packagesList { loadClasses() }
        else if column === classesList { loadProtocols(); loadMethods() }
        else if column === protocolsList { loadMethods() }
        else if column === methodsList { loadSource() }
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
