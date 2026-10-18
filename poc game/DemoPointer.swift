#if os(macOS)
import SwiftUI
import AppKit
import Combine

// Read the cursor relative to the real window and play surface. Polling alongside
// the game tick also handles exits across controls, title bars, and during drags.
@MainActor final class DemoPointer: ObservableObject {
    weak var surface: NSView?
    func sample() -> (insideWindow: Bool, position: CGPoint?) {
        guard let surface, let window = surface.window,
              window.isVisible, !window.isMiniaturized,
              surface.bounds.width > 0, surface.bounds.height > 0 else { return (false,nil) }
        let screenPoint = NSEvent.mouseLocation
        guard window.frame.contains(screenPoint) else { return (false,nil) }
        let local = surface.convert(window.convertPoint(fromScreen:screenPoint),from:nil)
        return (true,CGPoint(x:(local.x-surface.bounds.minX)/surface.bounds.width,
                             y:(local.y-surface.bounds.minY)/surface.bounds.height))
    }
}

struct DemoPointerSurface: NSViewRepresentable {
    let pointer: DemoPointer
    func makeNSView(context: Context) -> Surface {
        let view = Surface(); pointer.surface = view; return view
    }
    func updateNSView(_ nsView: Surface, context: Context) { pointer.surface = nsView }
    final class Surface: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif
