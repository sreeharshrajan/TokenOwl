import AppKit
import SwiftUI

/// Debug affordance for verification and screenshots.
///
/// Set `TOKENOWL_PREVIEW_PATH=/tmp/preview.png` before launching: after the
/// first snapshot arrives the live menu UI is rendered offscreen inside the
/// app process and written to that path. `TOKENOWL_PREVIEW_LOADING_PATH`
/// captures the first-launch loading state instead, and
/// `TOKENOWL_STATUS_PATH` captures the menu-bar item itself. No
/// screen-recording permission is needed, and nothing is written anywhere
/// else.
///
/// Rendering goes through `NSHostingView` + `cacheDisplay(in:to:)`, which is
/// the same drawing path the live UI uses. `ImageRenderer` is deliberately
/// avoided: offscreen it draws AppKit-backed controls (`Menu`,
/// `ProgressView`) as a system placeholder and ignores the effective
/// appearance, so its output does not match what the user sees.
@MainActor
enum MenuPreviewRenderer {

    static func renderIfRequested(store: QuotaStore) {
        render(store: store, pathKey: "TOKENOWL_PREVIEW_PATH")
        renderStatusItemIfRequested()
    }

    /// Captures the first-launch loading state, which would otherwise be
    /// overwritten by the settled-state render a moment later.
    static func renderLoadingIfRequested(store: QuotaStore) {
        render(store: store, pathKey: "TOKENOWL_PREVIEW_LOADING_PATH")
    }

    // MARK: Panel

    private static func render(store: QuotaStore, pathKey: String) {
        guard let path = path(named: pathKey) else { return }

        // The panel background comes from its window in the live UI, so it is
        // supplied here rather than by the view itself.
        let content = MenuBarView()
            .environment(store)
            .background(Color(nsColor: .windowBackgroundColor))

        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        guard size.width > 1, size.height > 1 else {
            log("preview sizing failed")
            return
        }

        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        write(view: hosting, to: path, label: "preview")
    }

    // MARK: Status item

    private static func renderStatusItemIfRequested() {
        guard let path = path(named: "TOKENOWL_STATUS_PATH") else { return }

        for window in NSApp.windows where window.isVisible {
            guard window.className.contains("NSStatus"),
                  let contentView = window.contentView,
                  contentView.bounds.width > 1,
                  contentView.bounds.height > 1
            else { continue }

            log("status window \(window.className) bounds=\(window.frame) contentView=\(type(of: contentView))")
            log(describe(contentView, depth: 0))

            write(view: contentView, to: path, label: "status item")
            return
        }

        log("status item window not found")
    }

    private static func describe(_ view: NSView, depth: Int) -> String {
        guard depth < 5 else { return "" }
        var line = String(
            repeating: "  ", count: depth + 1
        ) + "\(type(of: view)) frame=\(view.frame)"
        if let button = view as? NSButton {
            if !button.title.isEmpty { line += " title=\(button.title)" }
            if button.image != nil { line += " hasImage" }
        } else if let control = view as? NSControl,
                  !control.stringValue.isEmpty {
            line += " stringValue=\(control.stringValue)"
        }
        line += "\n"
        for subview in view.subviews {
            line += describe(subview, depth: depth + 1)
        }
        return line
    }

    // MARK: Shared

    /// Debug-build affordance: in release builds this always returns `nil`,
    /// so preview/status env vars written into an installed app do nothing.
    private static func path(named key: String) -> String? {
        #if DEBUG
        guard let path = ProcessInfo.processInfo.environment[key],
              !path.isEmpty
        else { return nil }
        return path
        #else
        return nil
        #endif
    }

    private static func write(view: NSView, to path: String, label: String) {
        let size = view.bounds.size
        let scale: CGFloat = 2
        let pixelsWide = Int(size.width * scale)
        let pixelsHigh = Int(size.height * scale)

        guard pixelsWide > 0, pixelsHigh > 0,
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: pixelsWide,
                  pixelsHigh: pixelsHigh,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              )
        else {
            log("\(label) bitmap failed")
            return
        }

        bitmap.size = size
        view.cacheDisplay(in: view.bounds, to: bitmap)

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            log("\(label) png encode failed")
            return
        }

        do {
            try png.write(to: URL(fileURLWithPath: path))
            log("\(label) written to \(path)")
        } catch {
            log("\(label) write failed: \(error.localizedDescription)")
        }
    }

    private static func log(_ message: String) {
        let data = Data("[TokenOwl] \(message)\n".utf8)
        try? FileHandle.standardError.write(contentsOf: data)
    }
}
