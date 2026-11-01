import AppIntents
import AppKit
import ToolHUDKit

/// Actions for the Shortcuts app: open the HUD (or an app's ring or a folder, by name), and
/// run the last action again.
struct ShowHUDIntent: AppIntent {
    static let title: LocalizedStringResource = "Show ToolHUD"
    static let description = IntentDescription("Opens the HUD in the middle of the screen. Name an app's ring or a folder to open that instead.")
    static let openAppWhenRun = false

    @Parameter(title: "Ring or folder", description: "An app's ring or a folder button, by name. Leave empty for the usual ring.")
    var ring: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Show ToolHUD \(\.$ring)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        var url = URLComponents()
        url.scheme = "toolhud"
        url.host = "show"
        if let ring, !ring.isEmpty { url.queryItems = [URLQueryItem(name: "ring", value: ring)] }
        if let link = url.url { (NSApp.delegate as? AppDelegate)?.application(NSApp, open: [link]) }
        return .result()
    }
}

struct RepeatLastActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run ToolHUD's Last Action Again"
    static let description = IntentDescription("Runs whatever ToolHUD ran last, as clicking the middle of the HUD does.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        HUDController.shared.repeatLast()
        return .result()
    }
}

struct ToolHUDShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ShowHUDIntent(), phrases: ["Show \(.applicationName)", "Open \(.applicationName)"],
                    shortTitle: "Show HUD", systemImageName: "circle.circle")
        AppShortcut(intent: RepeatLastActionIntent(), phrases: ["Repeat the last \(.applicationName) action"],
                    shortTitle: "Run Again", systemImageName: "arrow.clockwise")
    }
}
