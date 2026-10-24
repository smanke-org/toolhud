import AppKit
import CryptoKit
import Foundation
import IOKit
import Observation
import SystemConfiguration
import ToolHUDKit

/// Combines the Activity graph's counts from every Mac that shares ToolHUD settings
/// through iCloud Drive.
///
/// Each Mac writes only its own file, `iCloud Drive/ToolHUD/Activity/<device>.sealed`
/// (sealed with the sync key, like the settings), and reads the others'. With one writer per
/// file there are no conflicts to resolve, and the counts are whole-day totals, so reading a
/// file twice never counts anything twice. Only numbers are shared, never which buttons ran.
/// Takes part only while settings sync is on and unlocked; turning sync off removes this
/// Mac's file, so the other Macs stop counting it.
@Observable
@MainActor
final class ActivitySync {
    static let shared = ActivitySync()

    /// The other Macs' latest files, by device ID.
    private(set) var remotes: [String: DeviceActivity] = [:]

    @ObservationIgnored private var started = false
    @ObservationIgnored private var observingWake = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var publishTask: Task<Void, Never>?
    @ObservationIgnored private let queue = DispatchQueue(label: "com.smanke.ToolHUD.activitysync", qos: .utility)

    private enum Keys {
        static let remoteCache = "activitySync.remotes"
        static let macCount = "diagnostics.activityMacCount"
        static let allMacsActions = "diagnostics.activityAllMacsActions"
    }

    private init() {
        // Last-known counts from the other Macs, so the graph is complete at once rather
        // than showing only this Mac until the first read lands.
        if let data = UserDefaults.standard.data(forKey: Keys.remoteCache),
           let cached = try? DeviceActivity.decoder.decode([String: DeviceActivity].self, from: data) {
            remotes = cached
        }
    }

    // MARK: - What the graph shows

    /// Whether other Macs' counts are combined: settings sync is on and unlocked.
    var isActive: Bool { SettingsSync.shared.isEnabled && SettingsSync.shared.keyState == .ready }

    /// The other Macs whose counts are combined; none while sync is off.
    var activeRemotes: [DeviceActivity] {
        #if DEBUG
        if let staged = DebugHooks.activityRemotes { return staged }
        #endif
        return isActive ? remotes.values.sorted { $0.deviceName.localizedStandardCompare($1.deviceName) == .orderedAscending } : []
    }

    /// This Mac's counts plus the other Macs'.
    var combinedLog: ActivityLog {
        ActivityLog.combined([ActivityStore.shared.log] + activeRemotes.map(\.log))
    }

    // MARK: - Lifecycle

    /// At launch, and whenever settings sync is turned on or off.
    func start() {
        guard SettingsSync.shared.isEnabled else {
            stop()
            return
        }
        // Waits for the passphrase; nothing goes up unencrypted.
        guard SettingsSync.shared.syncKey != nil, !started else { return }
        started = true
        publish()
        refresh()
        // Other Macs' counts arrive in the background; look for them now and then.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            MainActor.assumeIsolated { ActivitySync.shared.refresh() }
        }
        guard !observingWake else { return }
        observingWake = true
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ActivitySync.shared.refresh() }
        }
    }

    /// Settings sync was turned off: stop sharing, and take this Mac's file away so the
    /// other Macs no longer count it.
    private func stop() {
        guard started else { return }
        started = false
        timer?.invalidate()
        timer = nil
        publishTask?.cancel()
        publishTask = nil
        guard let folder = Self.folder else { return }
        let url = folder.appending(path: "\(DeviceIdentity.deviceID).sealed")
        queue.async { Self.coordinatedDelete(url) }
    }

    /// This Mac got a sync key (set up, joined, or started over): write this Mac's file
    /// sealed with it, and read the others' again.
    func keyDidChange() {
        guard started else { return start() }
        publish()
        refresh()
    }

    /// An action was counted on this Mac. Written a few seconds later, so a burst of
    /// actions writes once.
    func localDidChange() {
        guard started else { return }
        publishTask?.cancel()
        publishTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            publishTask = nil
            publish()
        }
    }

    /// At quit, writes a count still waiting for its debounced write.
    func flush() {
        guard started, publishTask != nil else { return }
        publishTask?.cancel()
        publishTask = nil
        publish(waiting: true)
    }

    // MARK: - Files

    /// `iCloud Drive/ToolHUD/Activity`, or nil while iCloud Drive is off. Follows
    /// `TOOLHUD_SYNC_FOLDER`, so a test build never overwrites the installed app's file
    /// (both share this Mac's device ID).
    nonisolated static var folder: URL? {
        let app = SettingsSync.folder
        guard FileManager.default.fileExists(atPath: app.deletingLastPathComponent().path) else { return nil }
        return app.appending(path: "Activity")
    }

    /// `waiting` blocks briefly for the write, for quit, where there's no later chance.
    private func publish(waiting: Bool = false) {
        guard started, let folder = Self.folder, let key = SettingsSync.shared.syncKey else { return }
        let done = DispatchSemaphore(value: 0)
        let record = DeviceActivity(deviceID: DeviceIdentity.deviceID, deviceName: DeviceIdentity.deviceName,
                                    updatedAt: Date(), appVersion: AppInfo.version, log: ActivityStore.shared.log)
        queue.async {
            defer { done.signal() }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let data = try SyncCrypto.seal(DeviceActivity.encoder.encode(record), using: key)
                let url = folder.appending(path: "\(record.deviceID).sealed")
                var coordinationError: NSError?
                var writeError: Error?
                NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
                    do { try data.write(to: target, options: .atomic) } catch { writeError = error }
                }
                if let error = coordinationError ?? writeError { throw error }
            } catch {
                NSLog("ToolHUD: couldn't share activity through iCloud Drive: \(error.localizedDescription)")
            }
        }
        // Bounded, so a busy iCloud daemon can't hold up quitting.
        if waiting { _ = done.wait(timeout: .now() + 2) }
    }

    /// Reads the other Macs' files. Off the main thread, since a coordinated read can wait
    /// on iCloud.
    func refresh() {
        guard started, let folder = Self.folder, let key = SettingsSync.shared.syncKey else { return }
        let ownID = DeviceIdentity.deviceID
        queue.async {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            var fresh: [String: DeviceActivity] = [:]
            var downloading = Set<String>()
            for name in names {
                // iCloud Drive can evict a file to save space, leaving ".<name>.icloud".
                // Ask for it back and keep the last-known counts meanwhile.
                if name.hasPrefix("."), name.hasSuffix(".icloud") {
                    let real = String(name.dropFirst().dropLast(".icloud".count))
                    guard let id = Self.deviceID(fromFileName: real), id != ownID else { continue }
                    try? FileManager.default.startDownloadingUbiquitousItem(at: folder.appending(path: real))
                    downloading.insert(id)
                    continue
                }
                guard let id = Self.deviceID(fromFileName: name), id != ownID else { continue }
                var data: Data?
                var coordinationError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: folder.appending(path: name), options: [], error: &coordinationError) { target in
                    data = try? Data(contentsOf: target)
                }
                // A file sealed with another key (from before someone started over) is skipped.
                guard let data, let plain = try? SyncCrypto.open(data, using: key),
                      let record = try? DeviceActivity.decoder.decode(DeviceActivity.self, from: plain) else { continue }
                fresh[record.deviceID] = record
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { ActivitySync.shared.apply(fresh, downloading: downloading) }
            }
        }
    }

    nonisolated private static func deviceID(fromFileName name: String) -> String? {
        guard name.hasSuffix(".sealed"), !name.hasPrefix(".") else { return nil }
        return String(name.dropLast(".sealed".count))
    }

    nonisolated private static func coordinatedDelete(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
            try? FileManager.default.removeItem(at: target)
        }
    }

    private func apply(_ fresh: [String: DeviceActivity], downloading: Set<String>) {
        var merged = fresh
        for id in downloading where merged[id] == nil { merged[id] = remotes[id] }
        // A Mac whose file is gone (sync turned off there, or the file deleted) drops out.
        if merged != remotes { remotes = merged }
        if let data = try? DeviceActivity.encoder.encode(remotes) {
            UserDefaults.standard.set(data, forKey: Keys.remoteCache)
        }
        // So the combined numbers can be checked with `defaults read com.smanke.ToolHUD`.
        UserDefaults.standard.set(activeRemotes.count + 1, forKey: Keys.macCount)
        UserDefaults.standard.set(combinedLog.lifetime, forKey: Keys.allMacsActions)
    }
}

/// A stable identity for this Mac that is safe to write into iCloud Drive.
enum DeviceIdentity {
    /// From the hardware UUID, so it survives reinstalls and is not carried to a new Mac
    /// by Migration Assistant (an ID kept in UserDefaults would be, and two Macs would then
    /// share one file). Hashed, so the hardware identifier never leaves the Mac.
    static let deviceID: String = {
        let source = hardwareUUID() ?? fallbackUUID()
        let digest = SHA256.hash(data: Data("\(source):com.smanke.ToolHUD".utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }()

    /// The name in System Settings › General › About. Not `Host.current().localizedName`,
    /// which can block for seconds on DNS.
    static var deviceName: String {
        #if DEBUG
        // A made-up name for screenshots.
        if let staged = ProcessInfo.processInfo.environment["TOOLHUD_DEBUG_DEVICE_NAME"] { return staged }
        #endif
        return (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
    }

    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    /// Only reached if IOKit won't give up the hardware UUID.
    private static func fallbackUUID() -> String {
        let key = "activitySync.fallbackDeviceUUID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}
