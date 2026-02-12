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

struct WindowStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.styleMask.remove(.resizable)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func windowStyle() -> some View {
        self.background(WindowStyler())
    }
}

// MARK: - Hide Native Scroll Indicators

struct ScrollBarHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            hideScrollers(in: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            hideScrollers(in: nsView)
        }
    }

    private func hideScrollers(in view: NSView) {
        if let scrollView = findScrollView(in: view) {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScroller = nil
            scrollView.horizontalScroller = nil
        }
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.superview?.subviews ?? [] {
            if let found = findEnclosingScrollView(view: subview) {
                return found
            }
        }
        return findEnclosingScrollView(view: view)
    }

    private func findEnclosingScrollView(view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let v = current {
            if let sv = v as? NSScrollView {
                return sv
            }
            current = v.superview
        }
        return nil
    }
}
