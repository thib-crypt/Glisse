import AppKit
import SwiftUI

// MARK: - Modèle

struct GTimer: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var start: Date
    var end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
    func remaining(at now: Date) -> TimeInterval { max(0, end.timeIntervalSince(now)) }
    func remainingFraction(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, remaining(at: now) / duration))
    }
    var displayName: String { label.isEmpty ? "Minuteur \(Fmt.duration(Int(duration.rounded())))" : label }
}

@MainActor
final class TimerStore: ObservableObject {
    static let shared = TimerStore()

    @Published private(set) var timers: [GTimer] = []
    @Published private(set) var recent: [GTimer] = []
    @Published private(set) var now = Date()

    /// Appelé quand un ou plusieurs minuteurs arrivent à échéance.
    var onFinish: (([GTimer]) -> Void)?

    /// Un seul réveil ponctuel, programmé pour l'instant exact où quelque chose de visible change
    /// (seconde suivante du décompte, échéance d'un minuteur…). Aucun minuteur → aucun réveil.
    private var wake: Timer?
    private var popoverVisible = false
    private let defaults = UserDefaults.standard

    private init() {
        load()
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        reschedule()
    }

    /// Le popover affiche les décomptes de chaque ligne : on rafraîchit `now` avant qu'il s'ouvre
    /// et on cadence à la seconde tant qu'il est visible.
    func setPopoverVisible(_ visible: Bool) {
        guard visible != popoverVisible else { return }
        popoverVisible = visible
        if visible { now = Date() }
        reschedule()
    }

    var next: GTimer? { timers.first }

    @discardableResult
    func add(seconds: Int, label: String = "") -> GTimer {
        let start = Date()
        let t = GTimer(label: label, start: start, end: start.addingTimeInterval(TimeInterval(seconds)))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            timers.append(t)
            timers.sort { $0.end < $1.end }
        }
        save()
        Notifier.shared.schedule(t)
        reschedule()
        return t
    }

    func setLabel(_ id: UUID, _ label: String) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[i].label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
        Notifier.shared.schedule(timers[i])
    }

    func extend(_ id: UUID, by seconds: TimeInterval) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[i].end += seconds
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { timers.sort { $0.end < $1.end } }
        save()
        if let t = timers.first(where: { $0.id == id }) { Notifier.shared.schedule(t) }
        reschedule()
    }

    func remove(_ id: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { timers.removeAll { $0.id == id } }
        Notifier.shared.cancel(id)
        save()
        reschedule()
    }

    func relaunch(_ t: GTimer) {
        add(seconds: Int(t.duration.rounded()), label: t.label)
        withAnimation { recent.removeAll { $0.id == t.id } }
        save()
    }

    func clearRecent() {
        withAnimation { recent.removeAll() }
        save()
    }

    private func tick() {
        let date = Date()
        now = date
        let expired = timers.filter { $0.end <= date }
        if !expired.isEmpty {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                timers.removeAll { $0.end <= date }
                recent.insert(contentsOf: expired, at: 0)
                recent = Array(recent.prefix(5))
            }
            save()
            if !Notifier.shared.authorized { NSSound(named: "Glass")?.play() }
            onFinish?(expired)
        }
        reschedule()
    }

    /// Programme le prochain réveil au plus tard possible sans que l'affichage ne prenne de retard.
    func reschedule() {
        wake?.invalidate()
        wake = nil
        let date = Date()
        var candidates: [Date] = []
        if let next = timers.first { candidates.append(next.end) }  // échéance la plus proche (liste triée)

        let secondByThe = popoverVisible || (Prefs.showCountdown && !timers.isEmpty)
        if secondByThe {
            if let next = timers.first {
                // Instant où le décompte affiché (arrondi à la seconde supérieure) change de valeur.
                let r = next.remaining(at: date)
                candidates.append(date.addingTimeInterval(r - r.rounded(.up) + 1))
            } else {
                candidates.append(date.addingTimeInterval(1)) // « il y a 2 min » dans le popover
            }
        } else if let next = timers.first {
            // Seule l'icône (camembert de 18 pt) bouge : ~150 crans suffisent pour un tour fluide.
            candidates.append(date.addingTimeInterval(min(60, max(1, next.duration / 150))))
        }

        guard let fire = candidates.min() else { return }
        let t = Timer(fire: fire.addingTimeInterval(0.005), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // La tolérance laisse macOS regrouper ce réveil avec d'autres (économie d'énergie).
        t.tolerance = secondByThe ? 0.02 : 0.25
        RunLoop.main.add(t, forMode: .common) // continue pendant le suivi des menus / glisser
        wake = t
    }

    // MARK: Persistance

    private func save() {
        defaults.set(try? JSONEncoder().encode(timers), forKey: "timers")
        defaults.set(try? JSONEncoder().encode(recent), forKey: "recent")
    }

    private func load() {
        let dec = JSONDecoder()
        if let d = defaults.data(forKey: "timers"), let t = try? dec.decode([GTimer].self, from: d) { timers = t }
        if let d = defaults.data(forKey: "recent"), let r = try? dec.decode([GTimer].self, from: d) { recent = r }
        let date = Date()
        let expired = timers.filter { $0.end <= date }
        timers.removeAll { $0.end <= date }
        recent = Array((expired + recent).prefix(5))
        timers.sort { $0.end < $1.end }
    }
}

// MARK: - Courbe distance → durée

enum DurationCurve {
    /// Zone morte sous la barre des menus avant que le minuteur ne s'arme.
    static let deadZone: CGFloat = 16

    /// Courbe non linéaire : précise pour les durées courtes, rapide pour les longues.
    /// ~10 pt → 1 min · 100 pt → 26 min · 200 pt → 1 h 10 · 400 pt → 3 h · 700 pt → 7 h
    static func seconds(forDistance d: CGFloat) -> Int {
        let t = Double(d - deadZone)
        guard t > 0 else { return 0 }
        let m = pow(t / 10, 1.42)
        let snapped: Double
        switch m {
        case ..<60:  snapped = max(1, m.rounded())          // pas de 1 min
        case ..<180: snapped = (m / 5).rounded() * 5         // pas de 5 min
        default:     snapped = (m / 15).rounded() * 15       // pas de 15 min
        }
        return Int(min(snapped, 24 * 60)) * 60
    }
}

// MARK: - Formatage & couleurs

enum Fmt {
    static func duration(_ s: Int) -> String {
        if s < 60 { return "\(s) s" }
        let m = s / 60
        if m < 60 { return "\(m) min" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h) h" : String(format: "%d h %02d", h, r)
    }

    static func countdown(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    static func clock(_ d: Date) -> String { clockFormatter.string(from: d) }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func ago(_ d: Date, now: Date) -> String { relative.localizedString(for: d, relativeTo: now) }
}

enum Palette {
    /// Teinte qui glisse du turquoise (court) au magenta (long).
    static func tint(_ seconds: Double) -> Color {
        let m = max(1, seconds / 60)
        let t = min(1, log(m) / log(480))
        return Color(hue: 0.47 + 0.42 * t, saturation: 0.72, brightness: 0.95)
    }
}

enum Prefs {
    static var showCountdown: Bool { UserDefaults.standard.object(forKey: "showCountdown") as? Bool ?? true }
    static var haptics: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }
}
