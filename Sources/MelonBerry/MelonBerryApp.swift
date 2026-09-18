import AppKit
import SwiftUI
import UserNotifications

@main
struct MelonBerryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var controller = ScanController.shared
    @AppStorage(Prefs.Key.autoScan) private var autoScan = true

    var body: some Scene {
        MenuBarExtra {
            Text(controller.statusText)
            Divider()
            Button("Scan Now") { controller.requestScan() }
                .disabled(!controller.canScan)
            Toggle("Scan When Paper Is Loaded", isOn: $autoScan)
            Divider()
            Button("Open Scans Folder") {
                try? FileManager.default.createDirectory(at: Prefs.destination, withIntermediateDirectories: true)
                NSWorkspace.shared.open(Prefs.destination)
            }
            if let last = controller.lastOutput {
                Button("Show Last Scan in Finder") { NSWorkspace.shared.activateFileViewerSelecting([last]) }
            }
            Divider()
            Button("Settings…") { SettingsWindowManager.shared.show() }
                .keyboardShortcut(",")
            Button("Quit MelonBerry") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: controller.menuBarIcon)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        // developer mode: render the README screenshots and exit
        if let flag = CommandLine.arguments.firstIndex(of: "--screenshots"), CommandLine.arguments.count > flag + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
            MainActor.assumeIsolated { Screenshots.renderAll(to: directory) }
            exit(0)
        }
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        Task { @MainActor in ScanController.shared.start() }
    }
}
