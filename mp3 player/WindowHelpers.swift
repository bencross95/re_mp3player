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

    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}

// MARK: - Window Styling

class WindowStylerView: NSView {
    private var windowObservation: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyStyle()

        // Also observe in case the window changes
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
