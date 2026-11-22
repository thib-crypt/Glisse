import AppKit
import ServiceManagement
import SwiftUI

struct MenuView: View {
    @ObservedObject var store: TimerStore
    @AppStorage("showCountdown") private var showCountdown = true
    @AppStorage("haptics") private var haptics = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.timers.isEmpty {
                EmptyState()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.timers) { t in
                            TimerRow(timer: t, now: store.now, store: store)
                                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                        removal: .scale(scale: 0.9).combined(with: .opacity)))
                        }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 10)
                }
                .frame(height: min(CGFloat(store.timers.count) * 64 + 10, 340))
            }
            if !store.recent.isEmpty { recentSection }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 330)
    }

    private var header: some View {
        HStack {
            Text("Glisse").font(.system(size: 15, weight: .bold, design: .rounded))
            Spacer()
            if !store.timers.isEmpty {
                Text("\(store.timers.count) en cours")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Terminés").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Effacer") { store.clearRecent() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(store.recent) { t in
                RecentRow(timer: t, now: store.now) { store.relaunch(t) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Menu {
                Toggle("Décompte dans la barre des menus", isOn: $showCountdown)
                Toggle("Retour haptique", isOn: $haptics)
                Toggle("Ouvrir à la connexion", isOn: $launchAtLogin)
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .onChange(of: launchAtLogin) { _, on in
                do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
            }

            Spacer()
            Text("Glissez l'icône ↓ pour lancer")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
            Spacer()
            Button("Quitter") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

struct EmptyState: View {
    @State private var bounce = false
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .offset(y: bounce ? 6 : -2)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: bounce)
            Text("Aucun minuteur").font(.system(size: 13, weight: .semibold))
            Text("Cliquez sur l'icône et glissez vers le bas :\nplus vous descendez, plus c'est long.")
                .multilineTextAlignment(.center)
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .onAppear { bounce = true }
    }
}

struct TimerRow: View {
    let timer: GTimer
    let now: Date
    @ObservedObject var store: TimerStore

    @State private var hovering = false
    @State private var text: String = ""
    @FocusState private var editing: Bool

    var body: some View {
        let tint = Palette.tint(timer.duration)
        HStack(spacing: 12) {
            ProgressRing(progress: timer.remainingFraction(at: now), tint: tint)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Minuteur \(Fmt.duration(Int(timer.duration.rounded())))", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($editing)
                    .onSubmit { store.setLabel(timer.id, text); editing = false }
                Text("Fin à \(Fmt.clock(timer.end))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if hovering {
                HStack(spacing: 4) {
                    IconButton(symbol: "plus", help: "+5 min") { store.extend(timer.id, by: 300) }
                    IconButton(symbol: "xmark", help: "Supprimer") { store.remove(timer.id) }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Text(Fmt.countdown(timer.remaining(at: now)))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: Int(timer.remaining(at: now)))
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.07 : 0.035))
        )
        .onHover { h in withAnimation(.snappy(duration: 0.18)) { hovering = h } }
        .onAppear { text = timer.label }
        .onChange(of: timer.label) { _, l in if !editing { text = l } }
    }
}

struct RecentRow: View {
    let timer: GTimer
    let now: Date
    var relaunch: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.tint(timer.duration).opacity(0.8))
                .font(.system(size: 12))
            Text(timer.displayName).font(.system(size: 12)).lineLimit(1)
            Spacer()
            Text(Fmt.ago(timer.end, now: now)).font(.system(size: 11)).foregroundStyle(.tertiary)
            IconButton(symbol: "arrow.clockwise", help: "Relancer") { relaunch() }
                .opacity(hovering ? 1 : 0.4)
        }
        .onHover { hovering = $0 }
    }
}

struct ProgressRing: View {
    let progress: Double
    let tint: Color
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
        .padding(2)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.14 : 0.07)))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}
