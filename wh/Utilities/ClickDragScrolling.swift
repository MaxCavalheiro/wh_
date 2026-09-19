//
//  ClickDragScrolling.swift
//  wh
//

import AppKit
import SwiftUI

extension View {
    /// Lets the enclosing `ScrollView` be scrolled by clicking and dragging with the mouse,
    /// in addition to the wheel/trackpad. Apply to the ScrollView's content.
    func clickDragScrolling() -> some View {
        background(ClickDragScrollingEnabler())
    }
}

/// Invisible view that locates the AppKit scroll view hosting the SwiftUI `ScrollView`
/// and drives it from mouse-drag events.
private struct ClickDragScrollingEnabler: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ScrollViewFinder {
        let view = ScrollViewFinder()
        view.onScrollViewFound = { [weak coordinator = context.coordinator] scrollView in
            coordinator?.attach(to: scrollView)
        }
        return view
    }

    func updateNSView(_ nsView: ScrollViewFinder, context: Context) {}

    static func dismantleNSView(_ nsView: ScrollViewFinder, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private weak var scrollView: NSScrollView?
        private var monitor: Any?
        private var lastLocationInWindow: NSPoint?

        /// Movement (in points) before a click turns into a drag, so plain clicks still reach buttons.
        private let dragThreshold: CGFloat = 3
        private var isDragging = false

        func attach(to scrollView: NSScrollView) {
            guard self.scrollView !== scrollView else { return }
            detach()
            self.scrollView = scrollView
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            scrollView = nil
            lastLocationInWindow = nil
            isDragging = false
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let scrollView, event.window === scrollView.window else { return event }

            switch event.type {
            case .leftMouseDown:
                let point = scrollView.convert(event.locationInWindow, from: nil)
                lastLocationInWindow = scrollView.bounds.contains(point) ? event.locationInWindow : nil
                isDragging = false
                return event

            case .leftMouseDragged:
                guard let last = lastLocationInWindow else { return event }
                let delta = event.locationInWindow.y - last.y
                if !isDragging, abs(delta) < dragThreshold, abs(event.locationInWindow.x - last.x) < dragThreshold {
                    return event
                }
                isDragging = true
                lastLocationInWindow = event.locationInWindow
                scroll(scrollView, by: delta)
                return event

            case .leftMouseUp:
                lastLocationInWindow = nil
                isDragging = false
                return event

            default:
                return event
            }
        }

        /// Moves the content with the mouse. `delta` is in window coordinates (y grows upward).
        private func scroll(_ scrollView: NSScrollView, by delta: CGFloat) {
            let clipView = scrollView.contentView
            guard let documentView = scrollView.documentView else { return }

            let maxY = max(0, documentView.bounds.height - clipView.bounds.height)
            var origin = clipView.bounds.origin
            // A flipped document (SwiftUI's) has y = 0 at the top, so dragging the mouse down
            // (negative delta) must reduce the offset to reveal earlier content.
            origin.y += documentView.isFlipped ? delta : -delta
            origin.y = min(max(origin.y, 0), maxY)

            clipView.scroll(to: origin)
            scrollView.reflectScrolledClipView(clipView)
        }
    }
}

/// Reports the nearest ancestor `NSScrollView` once inserted into the view hierarchy.
final class ScrollViewFinder: NSView {
    var onScrollViewFound: ((NSScrollView) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        var view: NSView? = superview
        while let current = view {
            if let scrollView = current as? NSScrollView {
                onScrollViewFound?(scrollView)
                return
            }
            view = current.superview
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
