import Darwin
import Foundation

/// Resolves the PyInstaller-frozen listener binary bundled in Cloak.app.
enum ListenerCore {
    static func hostArchitecture() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buf, &size, nil, 0)
        let machine = String(cString: buf)
        if machine.hasPrefix("arm") { return "arm64" }
        if machine.hasPrefix("x86") { return "x86_64" }
        return machine
    }

    /// Bundled `cloak-core-<arch>` for this Mac, or nil if the app was not built with cores.
    static func bundledExecutableURL() -> URL? {
        let name = "cloak-core-\(hostArchitecture())"
        guard let url = Bundle.main.url(forResource: name, withExtension: nil),
              FileManager.default.isExecutableFile(atPath: url.path) else {
            return nil
        }
        return url
    }

    static func bundledExecutablePath() -> String? {
        bundledExecutableURL()?.path
    }
}
