import SwiftUI
import AppKit

/// Only this view moves the window; the rest of the UI does not (`isMovableByWindowBackground` is off).
struct WindowDragStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragStripView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragStripView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
