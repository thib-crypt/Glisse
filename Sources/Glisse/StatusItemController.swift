import AppKit
import Combine
import SwiftUI

/// Vue transparente posée sur le bouton de la barre des menus : elle capte le clic et le glisser.
final class DragCatcherView: NSView {
    var onDown: ((NSPoint) -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onUp: ((NSPoint) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Toujours capter le clic, même si le bouton de la barre des menus voudrait le prendre.
        frame.contains(point) ? self : nil
    }

    private var poller: Timer?
    private var lastLocation: NSPoint = .zero

    /// Depuis macOS 26, les icônes de la barre des menus sont affichées par le système :
    /// l'app reçoit le clic, mais plus les `mouseDragged`. On interroge donc directement
    /// l'état global de la souris (position + bouton enfoncé) à ~120 Hz jusqu'au relâchement.
    override func mouseDown(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        dragLog.notice("mouseDown at \(p.x, privacy: .public),\(p.y, privacy: .public) hwDown=\(Self.leftButtonDown, privacy: .public)")
        poller?.invalidate()
        onDown?(p)
        lastLocation = p
        guard Self.leftButtonDown else { finish(); return } // clic livré en retard
        // Cadence alignée sur l'écran (120 Hz ProMotion, 60 Hz sur un écran externe).
        let hz = Double(window?.screen?.maximumFramesPerSecond ?? NSScreen.main?.maximumFramesPerSecond ?? 120)
        let t = Timer(timeInterval: 1.0 / max(60, hz), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        poller = t
    }

    override func mouseDragged(with event: NSEvent) { poll() }
    /// macOS 26+ synthétise un mouseUp ~1 ms après le mouseDown alors que le bouton est
    /// encore enfoncé : on l'ignore et on se fie uniquement à l'état matériel du bouton.
    override func mouseUp(with event: NSEvent) {
        dragLog.notice("mouseUp event ignored, hardware down=\(Self.leftButtonDown, privacy: .public)")
    }

    /// État réel du bouton gauche lu au niveau HID (insensible aux événements synthétisés).
    static var leftButtonDown: Bool {
        CGEventSource.buttonState(.hidSystemState, button: .left)
    }

    private func poll() {
        guard Self.leftButtonDown else { finish(); return }
        let p = NSEvent.mouseLocation
        guard p != lastLocation else { return }
        lastLocation = p
        onDrag?(p)
    }

    private func finish() {
        poller?.invalidate()
        poller = nil
        let p = NSEvent.mouseLocation
        dragLog.notice("release at \(p.x, privacy: .public),\(p.y, privacy: .public)")
        onUp?(p)
    }
}

import os
let dragLog = Logger(subsystem: "com.thibault.glisse", category: "drag")

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: TimerStore
    private let overlay = DragOverlayController()
    private let quickLabel = QuickLabelController()
    private let popover = NSPopover()

    private var downPoint: NSPoint?
    private var dragging = false
    private var lastSeconds = 0
    private var ringingUntil: Date?
    /// macOS rejoue un clic ~0,5 s après la fin d'un glisser : on l'ignore.
    private var ignoreClicksUntil = Date.distantPast
    private var bag = Set<AnyCancellable>()
    /// Dernier état dessiné dans la barre des menus, pour ne rien redessiner s'il n'a pas changé.
    private var shownIconKey: Int?
    private var shownTitle: String?

    init(store: TimerStore) {
        self.store = store
        super.init()

        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)

        let catcher = DragCatcherView(frame: button.bounds)
        catcher.autoresizingMask = [.width, .height]
        catcher.onDown = { [weak self] in self?.mouseDown($0) }
        catcher.onDrag = { [weak self] in self?.mouseDragged($0) }
        catcher.onUp = { [weak self] in self?.mouseUp($0) }
        button.addSubview(catcher)

        // Le contenu SwiftUI du popover n'existe que pendant qu'il est affiché (voir togglePopover).
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshButton() }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.store.reschedule() // l'option « décompte » change la cadence nécessaire
                self?.refreshButton()
            }
            .store(in: &bag)

        store.onFinish = { [weak self] _ in self?.ring() }
        refreshButton()
    }

    // MARK: Gestes

    private var anchor: NSPoint {
        guard let f = statusItem.button?.window?.frame else { return NSEvent.mouseLocation }
        return NSPoint(x: f.midX, y: f.minY)
    }

    private func mouseDown(_ p: NSPoint) {
        guard Date() >= ignoreClicksUntil else { downPoint = nil; return }
        downPoint = p
        dragging = false
    }

    private func mouseDragged(_ p: NSPoint) {
        guard let start = downPoint else { return }
        if !dragging {
            guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
            dragging = true
            lastSeconds = 0
            popover.performClose(nil)
            quickLabel.close()
            statusItem.button?.highlight(true)
            let screen = statusItem.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
            dragLog.notice("drag begin anchor=\(self.anchor.x, privacy: .public),\(self.anchor.y, privacy: .public) window=\(String(describing: self.statusItem.button?.window?.frame), privacy: .public)")
            overlay.begin(anchor: anchor, screen: screen)
        }
        let seconds = DurationCurve.seconds(forDistance: anchor.y - p.y)
        if seconds != lastSeconds {
            feedback(from: lastSeconds, to: seconds)
            lastSeconds = seconds
        }
        overlay.update(cursor: p, seconds: seconds)
    }

    private func mouseUp(_ p: NSPoint) {
        guard downPoint != nil else { return }
        defer { downPoint = nil }
        guard dragging else { togglePopover(); return }
        dragging = false
        ignoreClicksUntil = Date().addingTimeInterval(0.8)
        statusItem.button?.highlight(false)

        guard lastSeconds >= 60 else { overlay.cancel(); return }
        let timer = store.add(seconds: lastSeconds)
        let anchor = self.anchor
        overlay.commit { [weak self] in
            guard let self else { return }
            self.pop()
            self.quickLabel.show(for: timer, store: self.store, anchor: anchor)
        }
    }

    private func feedback(from old: Int, to new: Int) {
        guard Prefs.haptics else { return }
        let performer = NSHapticFeedbackManager.defaultPerformer
        let crossedHour = old / 3600 != new / 3600
        let armedChange = (old >= 60) != (new >= 60)
        performer.perform(crossedHour || armedChange ? .levelChange : .alignment, performanceTime: .now)
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            quickLabel.close()
            let host = NSHostingController(rootView: MenuView(store: store))
            host.sizingOptions = [.preferredContentSize]
            popover.contentViewController = host
            store.setPopoverVisible(true)
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            store.setPopoverVisible(false)
            // Libère toute la hiérarchie SwiftUI : plus aucune animation ni mise à jour en arrière-plan.
            popover.contentViewController = nil
        }
    }

    // MARK: Icône

    private func refreshButton() {
        guard let button = statusItem.button else { return }
        let now = Date()
        let ringing = ringingUntil.map { $0 > now } ?? false
        let next = store.next
        let fraction = next?.remainingFraction(at: now)
        // Clé d'icône : cloche, cadran vide, ou camembert quantifié (bien plus fin que les 18 pt affichés).
        let key = ringing ? -2 : fraction.map { $0 > 0 ? Int(($0 * 600).rounded(.up)) : -1 } ?? -1
        if key != shownIconKey {
            shownIconKey = key
            button.image = StatusIcon.image(remaining: fraction, ringing: ringing)
        }
        let title = Prefs.showCountdown ? next.map { " " + Fmt.countdown($0.remaining(at: now)) } ?? "" : ""
        if title != shownTitle {
            shownTitle = title
            button.title = title
        }
    }

    /// Petit rebond de l'icône quand un minuteur est posé.
    private func pop() {
        guard let layer = statusItem.button?.layer else { return }
        let a = CAKeyframeAnimation(keyPath: "transform")
        a.values = [1, 1.25, 0.92, 1.04, 1].map { centered(layer, CATransform3DMakeScale($0, $0, 1)) }
        a.keyTimes = [0, 0.25, 0.55, 0.8, 1]
        a.duration = 0.45
        layer.add(a, forKey: "pop")
    }

    private func ring() {
        ringingUntil = Date().addingTimeInterval(8)
        refreshButton()
        if let layer = statusItem.button?.layer {
            let a = CAKeyframeAnimation(keyPath: "transform")
            a.values = [0, 0.25, -0.25, 0.18, -0.18, 0.08, 0].map { centered(layer, CATransform3DMakeRotation($0, 0, 0, 1)) }
            a.duration = 0.7
            a.repeatCount = 3
            layer.add(a, forKey: "ring")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.1) { [weak self] in self?.refreshButton() }
    }
}

/// Transformation appliquée autour du centre du calque (les calques AppKit ont leur ancre au coin).
private func centered(_ layer: CALayer, _ t: CATransform3D) -> NSValue {
    let cx = layer.bounds.midX, cy = layer.bounds.midY
    let m = CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-cx, -cy, 0), t),
                                CATransform3DMakeTranslation(cx, cy, 0))
    return NSValue(caTransform3D: m)
}

enum StatusIcon {
    static func image(remaining: Double?, ringing: Bool) -> NSImage {
        if ringing, let bell = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Minuteur terminé") {
            let img = bell.withSymbolConfiguration(.init(pointSize: 14, weight: .semibold)) ?? bell
            img.isTemplate = true
            return img
        }
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let r = rect.insetBy(dx: 2, dy: 2)
            let c = NSPoint(x: rect.midX, y: rect.midY)
            NSColor.black.set()

            let ring = NSBezierPath(ovalIn: r)
            ring.lineWidth = 1.6
            ring.stroke()

            if let f = remaining, f > 0 {
                let pie = NSBezierPath()
                pie.move(to: c)
                pie.appendArc(withCenter: c, radius: r.width / 2 - 2.4, startAngle: 90, endAngle: 90 - 360 * f, clockwise: true)
                pie.close()
                pie.fill()
            } else {
                let hand = NSBezierPath()
                hand.move(to: c)
                hand.line(to: NSPoint(x: c.x, y: r.maxY - 3.2))
                hand.lineWidth = 1.6
                hand.lineCapStyle = .round
                hand.stroke()
                NSBezierPath(ovalIn: NSRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)).fill()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Glisse"
        return img
    }
}
