import AppKit
import SwiftUI

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Petit champ flottant qui apparaît sous l'icône juste après la création d'un minuteur.
@MainActor
final class QuickLabelController: NSObject, NSWindowDelegate {
    private var panel: KeyPanel?
    private var autoClose: DispatchWorkItem?

    func show(for timer: GTimer, store: TimerStore, anchor: NSPoint) {
        close()
        let view = QuickLabelView(
            timer: timer,
            onSubmit: { [weak self] text in
                store.setLabel(timer.id, text)
                self?.close()
            },
            onCancel: { [weak self] in self?.close() },
            onEdit: { [weak self] in self?.autoClose?.cancel() }
        )
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        p.delegate = self

        var origin = NSPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height - 8)
        if let vf = NSScreen.screens.first(where: { $0.frame.contains(anchor) })?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
        }
        p.setFrameOrigin(origin)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            p.animator().alphaValue = 1
        }
        panel = p

        let work = DispatchWorkItem { [weak self] in self?.close() }
        autoClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func close() {
        autoClose?.cancel()
        guard let p = panel else { return }
        panel = nil
        p.delegate = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated { close() }
    }
}

struct QuickLabelView: View {
    let timer: GTimer
    var onSubmit: (String) -> Void
    var onCancel: () -> Void
    var onEdit: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let tint = Palette.tint(timer.duration)
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            TextField("Ajouter une description…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused)
                .onSubmit { onSubmit(text) }
                .onChange(of: text) { onEdit() }
            Text(Fmt.duration(Int(timer.duration.rounded())))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(tint.opacity(0.15), in: Capsule())
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .onAppear { focused = true }
        .onExitCommand(perform: onCancel)
    }
}
