import SwiftUI
import AppKit

// MARK: - Window Drag Gesture

struct WindowDragGesture: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Window Drag Blocker

struct WindowDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DragBlockingView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class DragBlockingView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

// MARK: - Window Styling

class WindowStylerView: NSView {
    private var windowObservation: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyStyle()

        windowObservation = observe(\.window, options: [.new]) { [weak self] _, _ in
            self?.applyStyle()
        }
    }

    private func applyStyle() {
        guard let window = self.window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert(.resizable)
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.9)

        // Completely remove the native titlebar
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        if let titlebarContainer = window.standardWindowButton(.closeButton)?.superview?.superview {
            titlebarContainer.frame.size.height = 0
            titlebarContainer.isHidden = true
        }
    }
}

struct WindowStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowStylerView {
        WindowStylerView()
    }

    func updateNSView(_ nsView: WindowStylerView, context: Context) {}
}

extension View {
    func windowStyle() -> some View {
        self.background(WindowStyler())
    }
}

// MARK: - Always On Top

class AlwaysOnTopView: NSView {
    var isOnTop: Bool = false {
        didSet {
            applyLevel()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyLevel()
    }

    private func applyLevel() {
        guard let window = self.window else { return }
        window.level = isOnTop ? .floating : .normal
    }
}

struct AlwaysOnTopHelper: NSViewRepresentable {
    var isOnTop: Bool

    func makeNSView(context: Context) -> AlwaysOnTopView {
        let view = AlwaysOnTopView()
        view.isOnTop = isOnTop
        return view
    }

    func updateNSView(_ nsView: AlwaysOnTopView, context: Context) {
        nsView.isOnTop = isOnTop
    }
}
