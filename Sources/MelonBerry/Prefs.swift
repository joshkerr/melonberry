import Foundation

/// UserDefaults keys, shared between `@AppStorage` in views and direct reads in the controller.
enum Prefs {
    enum Key {
        static let destination = "destination"
        static let autoScan = "autoScan"
        static let showWindow = "showWindow"
        static let autoClose = "autoClose"
        static let closeDelay = "closeDelay"
        static let duplex = "duplex"
        static let colorMode = "colorMode"
        static let skipBlank = "skipBlank"
    }

    static let defaultDestination = ("~/Documents/Scans" as NSString).expandingTildeInPath

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.destination: defaultDestination,
            Key.autoScan: true,
            Key.showWindow: true,
            Key.autoClose: true,
            Key.closeDelay: 6.0,
            Key.duplex: true,
            Key.colorMode: "Color",
            Key.skipBlank: true,
        ])
    }

    private static var defaults: UserDefaults { .standard }

    static var destination: URL {
        URL(fileURLWithPath: defaults.string(forKey: Key.destination) ?? defaultDestination, isDirectory: true)
    }
    static var autoScan: Bool { defaults.bool(forKey: Key.autoScan) }
    static var showWindow: Bool { defaults.bool(forKey: Key.showWindow) }
    static var autoClose: Bool { defaults.bool(forKey: Key.autoClose) }
    static var closeDelay: Double { max(defaults.double(forKey: Key.closeDelay), 1) }
    static var duplex: Bool { defaults.bool(forKey: Key.duplex) }
    static var skipBlank: Bool { defaults.bool(forKey: Key.skipBlank) }
    static var colorMode: String { defaults.string(forKey: Key.colorMode) ?? "Color" }
}
