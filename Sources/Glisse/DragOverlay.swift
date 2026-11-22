import AppKit
import SwiftUI

// MARK: - État partagé de l'overlay

@MainActor
final class OverlayModel: ObservableObject {
    enum Phase { case dragging, committing, cancelling }
    @Published var anchor: CGPoint = .zero
    @Published var cursor: CGPoint = .zero
    @Published var seconds = 0
    @Published var phase: Phase = .dragging
    @Published var appeared = false
}

/// Panneau transparent plein écran, au-dessus de la barre des menus, qui dessine
/// le « fil » tiré depuis l'icône et la bulle du minuteur.
@MainActor
final class DragOverlayController {
    let model = OverlayModel()
    private var panel: NSPanel?
    private var screenFrame: NSRect = .zero
    private var generation = 0

    func begin(anchor: NSPoint, screen: NSScreen) {
        generation += 1
        screenFrame = screen.frame
        let panel = self.panel ?? makePanel()
        panel.setFrame(screen.frame, display: false)

        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            model.phase = .dragging
            model.appeared = false
            model.seconds = 0
            model.anchor = local(anchor)
            model.cursor = local(anchor)
        }
        panel.orderFrontRegardless()
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) { self.model.appeared = true }
            }
        }
    }

    func update(cursor: NSPoint, seconds: Int) {
        model.cursor = local(cursor)
        if model.seconds != seconds {
            withAnimation(.snappy(duration: 0.2)) { model.seconds = seconds }
        }
    }

    func commit(completion: @escaping () -> Void) {
        let gen = generation
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            model.phase = .committing
            model.cursor = model.anchor
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.panel?.orderOut(nil)
            completion()
        }
    }

    func cancel() {
        let gen = generation
        withAnimation(.easeOut(duration: 0.2)) { model.phase = .cancelling }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func local(_ p: NSPoint) -> CGPoint {
        CGPoint(x: p.x - screenFrame.minX, y: screenFrame.maxY - p.y)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: OverlayView(model: model))
        host.sizingOptions = []
        p.contentView = host
        panel = p
        return p
    }
}

// MARK: - Vues

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    private var armed: Bool { model.seconds >= 60 }
    private var tint: Color { armed ? Palette.tint(Double(model.seconds)) : .secondary }

    var body: some View {
        GeometryReader { geo in
            let center = bubbleCenter(in: geo.size)
            ZStack {
                RopeShape(from: model.anchor, to: model.cursor)
                    .stroke(
                        LinearGradient(colors: [tint.opacity(0.25), tint], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: armed ? [] : [2, 6])
                    )
                    .shadow(color: tint.opacity(0.55), radius: 5)

                Circle()
                    .fill(tint)
                    .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .shadow(color: tint.opacity(0.7), radius: 6)
                    .scaleEffect(model.phase == .dragging ? 1 : 0.2)
                    .position(model.cursor)

                TimerBubble(seconds: model.seconds, armed: armed, tint: tint)
                    .scaleEffect(scale, anchor: .center)
                    .opacity(opacity)
                    .blur(radius: model.phase == .dragging ? 0 : 6)
                    .position(center)
            }
            .opacity(model.phase == .cancelling ? 0 : 1)
        }
        .ignoresSafeArea()
    }

    private var scale: CGFloat {
        switch model.phase {
        case .dragging: model.appeared ? 1 : 0.35
        case .committing: 0.12
        case .cancelling: 0.85
        }
    }

    private var opacity: Double {
        switch model.phase {
        case .dragging: model.appeared ? 1 : 0
        case .committing, .cancelling: 0
        }
    }

    /// La bulle se place à côté du curseur, et bascule de côté près des bords de l'écran.
    private func bubbleCenter(in size: CGSize) -> CGPoint {
        let half: CGFloat = 92
        let side: CGFloat = model.cursor.x + 26 + half * 2 > size.width ? -1 : 1
        let x = model.cursor.x + side * (26 + half)
        let y = min(max(model.cursor.y + 30, half + 30), size.height - half - 20)
        return CGPoint(x: x, y: y)
    }
}

/// Un fil qui quitte l'icône verticalement puis s'incurve vers le curseur.
struct RopeShape: Shape {
    var from: CGPoint
    var to: CGPoint

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(from.x, from.y), .init(to.x, to.y)) }
        set {
            from = CGPoint(x: newValue.first.first, y: newValue.first.second)
            to = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: from)
        p.addQuadCurve(to: to, control: CGPoint(x: from.x, y: (from.y + to.y) / 2))
        return p
    }
}

struct TimerBubble: View {
    let seconds: Int
    let armed: Bool
    let tint: Color

    private var minutes: Int { seconds / 60 }
    private var hours: Int { minutes / 60 }
    private var fraction: Double {
        guard minutes > 0 else { return 0 }
        let m = minutes % 60
        return m == 0 ? 1 : Double(m) / 60
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                    .padding(5)

                // 60 graduations dessinées en 2 formes au lieu de 60 vues (même rendu, 2 calques).
                DialTicks(major: false).fill(Color.primary.opacity(0.12))
                DialTicks(major: true).fill(Color.primary.opacity(0.32))

                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(5)
                    .shadow(color: tint.opacity(0.6), radius: 6)

                VStack(spacing: 5) {
                    Text(armed ? Fmt.duration(seconds) : "↓")
                        .font(.system(size: hours > 0 ? 24 : 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(seconds)))
                    if hours > 0 { HourDots(hours: hours, tint: tint) }
                }
            }
            .frame(width: 128, height: 128)

            Text(armed ? "Fin à \(Fmt.clock(Date().addingTimeInterval(TimeInterval(seconds))))" : "Tirez vers le bas")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 26, y: 12)
    }
}

/// Graduations du cadran : capsules à 45 pt du centre, tous les 6°.
struct DialTicks: Shape {
    let major: Bool

    func path(in rect: CGRect) -> Path {
        let w: CGFloat = major ? 2 : 1, h: CGFloat = major ? 7 : 4
        let tick = Path(roundedRect: CGRect(x: -w / 2, y: -45 - h / 2, width: w, height: h),
                        cornerRadius: w / 2, style: .continuous)
        var p = Path()
        for i in 0..<60 where (i % 5 == 0) == major {
            let t = CGAffineTransform(translationX: rect.midX, y: rect.midY).rotated(by: CGFloat(i) * .pi / 30)
            p.addPath(tick, transform: t)
        }
        return p
    }
}

struct HourDots: View {
    let hours: Int
    let tint: Color
    var body: some View {
        if hours <= 8 {
            HStack(spacing: 3) {
                ForEach(0..<hours, id: \.self) { _ in
                    Capsule().fill(tint).frame(width: 6, height: 3)
                }
            }
            .transition(.scale.combined(with: .opacity))
        } else {
            Text("\(hours) h").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(tint)
        }
    }
}
