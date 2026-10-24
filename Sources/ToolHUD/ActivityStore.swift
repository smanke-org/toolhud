import Foundation
import Observation
import ToolHUDKit

/// How many actions ToolHUD has run per day, for the Activity graph in Settings.
///
/// Counted: every HUD or button-pad button that runs, by click or key, and every item picked
/// from another app's menu in ToolHUD's menu. Not counted: Test This Button in Settings. Only
/// numbers are stored, in Application Support/ToolHUD/activity.json.
@Observable
@MainActor
final class ActivityStore {
    static let shared = ActivityStore()

    private(set) var log = ActivityLog()

    /// `TOOLHUD_ACTIVITY_FILE` points a test build elsewhere, so it never changes the
    /// installed app's counts.
    private let url: URL = {
        if let override = ProcessInfo.processInfo.environment["TOOLHUD_ACTIVITY_FILE"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "ToolHUD").appending(path: "activity.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(ActivityLog.self, from: data) {
            log = saved
        }
    }

    func record() {
        log.record()
        log.trim()
        save()
        ActivitySync.shared.localDidChange()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(log).write(to: url, options: .atomic)
        } catch {
            NSLog("ToolHUD: couldn't save activity: \(error.localizedDescription)")
        }
    }
}
