import AppKit

/// The minimap (the diagram and a box for what is on screen) and the zoom pill, floating at the bottom right of the canvas.
final class ZoomOverlay: NSView {
    let map = NavigatorMapView()
    private let mapSurface = FloatingSurface(radius: Tok.Radius.card)
    private let pill = FloatingSurface(radius: 999)
    private let zoomOut = IconButton(symbol: "minus", label: "Zoom out", tip: "Zoom out (⌘−)", size: 30, pointSize: 12)
    private let zoomIn = IconButton(symbol: "plus", label: "Zoom in", tip: "Zoom in (⌘+)", size: 30, pointSize: 12)
    private let percent = NSButton()
    private weak var canvas: CanvasView?
    private var observers: [NSObjectProtocol] = []

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        map.translatesAutoresizingMaskIntoConstraints = false
        map.wantsLayer = true
        map.layer?.cornerRadius = Tok.Radius.card
        map.layer?.masksToBounds = true
        map.setAccessibilityLabel("Navigator: the red box is what is on screen")
        mapSurface.addSubview(map)

        percent.isBordered = false
        percent.setButtonType(.momentaryChange)
        percent.target = self; percent.action = #selector(fit(_:))
        percent.toolTip = "Zoom to fit"
        percent.setAccessibilityLabel("Zoom level; press to zoom to fit")
        percent.translatesAutoresizingMaskIntoConstraints = false
        zoomOut.target = self; zoomOut.action = #selector(out(_:))
        zoomIn.target = self; zoomIn.action = #selector(inn(_:))
        zoomOut.cornerRadius = 15; zoomIn.cornerRadius = 15
        let row = NSStackView(views: [zoomOut, percent, zoomIn])
        row.spacing = 0
        row.edgeInsets = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        row.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(row)

        let stack = NSStackView(views: [mapSurface, pill])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            mapSurface.widthAnchor.constraint(equalToConstant: 168), mapSurface.heightAnchor.constraint(equalToConstant: 104),
            map.leadingAnchor.constraint(equalTo: mapSurface.leadingAnchor), map.trailingAnchor.constraint(equalTo: mapSurface.trailingAnchor),
            map.topAnchor.constraint(equalTo: mapSurface.topAnchor), map.bottomAnchor.constraint(equalTo: mapSurface.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: pill.leadingAnchor), row.trailingAnchor.constraint(equalTo: pill.trailingAnchor),
            row.topAnchor.constraint(equalTo: pill.topAnchor), row.bottomAnchor.constraint(equalTo: pill.bottomAnchor),
            percent.widthAnchor.constraint(greaterThanOrEqualToConstant: 52), percent.heightAnchor.constraint(equalToConstant: 30),
        ])
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func attach(_ canvas: CanvasView) {
        self.canvas = canvas
        map.canvas = canvas
        refresh()
    }

    /// Follow scrolling and zooming of the document view (called once the canvas is inside its scroll view).
    func observe() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let scroll = canvas?.enclosingScrollView else { return }
        let clip = scroll.contentView
        clip.postsBoundsChangedNotifications = true
        clip.postsFrameChangedNotifications = true
        for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: clip, queue: .main) { [weak self] _ in self?.refresh() })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: scroll, queue: .main) { [weak self] _ in self?.refresh() })
        refresh()
    }

    func refresh() {
        map.needsDisplay = true
        let m = canvas?.magnification ?? 1
        percent.attributedTitle = NSAttributedString(string: "\(Int((m * 100).rounded()))%", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: Tok.textPrimary,
        ])
    }

    var percentText: String { percent.attributedTitle.string }
    @objc private func out(_ s: Any?) { canvas?.zoomStep(out: true); refresh() }
    @objc private func inn(_ s: Any?) { canvas?.zoomStep(out: false); refresh() }
    @objc private func fit(_ s: Any?) { canvas?.zoomToFitDiagram(); refresh() }
    func pressZoomOut() { out(nil) }
    func pressZoomIn() { inn(nil) }
    func pressPercent() { fit(nil) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }
}
