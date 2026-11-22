import AppKit
import Sparkle

/// Mises à jour via Sparkle : le flux `SUFeedURL` (Info.plist) est vérifié une fois par jour et à la demande.
/// Chaque mise à jour est un DMG notarisé publié sur GitHub Releases et signé EdDSA (`scripts/release.sh`).
@MainActor
final class Updater {
    static let shared = Updater()

    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                          userDriverDelegate: nil)
    private init() {}

    /// Démarre les vérifications planifiées (il suffit de toucher `shared`).
    func start() {}

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
