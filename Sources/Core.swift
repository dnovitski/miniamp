// Shared core for the app and the CLI: paths, the two launchd services, and running processes.
//
// Each service is a launchd job in the user's GUI domain (no root needed):
//   - running:   launchctl print shows "state = running"
//   - start:     bootstrap the plist (LaunchAgents copy if present, else the template), then kickstart
//   - stop:      bootout, then wait until the job is gone
//   - autostart: a copy of the plist exists in ~/Library/LaunchAgents (that is what launchd loads at login)
// For MariaDB this matches `brew services` exactly, so both stay in sync.

import Darwin
import Foundation

enum Paths {
    static let home = NSHomeDirectory()
    static let brew = "/opt/homebrew"
    static let brewBin = brew + "/bin/brew"
    static let php = brew + "/bin/php"
    static let mariadb = brew + "/bin/mariadb"
    static let mariadbAdmin = brew + "/bin/mariadb-admin"
    static let mariadbData = brew + "/var/mysql"
    static let mariadbConf = brew + "/etc/my.cnf.d/miniamp.cnf"
    static let phpMyAdmin = brew + "/share/phpmyadmin"
    static let phpMyAdminConfig = brew + "/etc/phpmyadmin.config.inc.php"
    static let cliLink = brew + "/bin/miniamp"
    static let brewCellar = brew + "/Cellar/miniamp/"
    static let brewApp = brew + "/opt/miniamp/Miniamp.app"  // stable across `brew upgrade`
    static let userApp = home + "/Applications/Miniamp.app"
    static let support = home + "/Library/Application Support/miniamp"
    static let router = support + "/router.php"
    static let agents = home + "/Library/LaunchAgents"
    static let docroot = home + "/Sites/localhost"
    static let logs = home + "/Library/Logs/miniamp"
    static let webLog = logs + "/web.log"
    static let setupLog = logs + "/setup.log"
    static let console = "/System/Applications/Utilities/Console.app"
}

enum AppInfo {
    /// The real executable, also when started through the `miniamp` symlink.
    static let executable = Bundle.main.executableURL!.resolvingSymlinksInPath()
    /// "Miniamp.app" (Contents/MacOS/<exe> -> three levels up).
    static let bundleURL = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let info = plist(ofApp: bundleURL.path) ?? [:]
    static let version = info["CFBundleShortVersionString"] as? String ?? "dev"
    /// Installed with `brew install dnovitski/tap/miniamp` (running from the Cellar).
    static let isHomebrew = executable.path.hasPrefix(Paths.brewCellar)

    /// "1.2.0 (42)" of a Miniamp app bundle, to tell whether a copy is current; nil if it is not Miniamp.
    static func versionString(ofApp path: String) -> String? {
        guard let other = plist(ofApp: path),
              other["CFBundleIdentifier"] as? String == info["CFBundleIdentifier"] as? String else { return nil }
        return "\(other["CFBundleShortVersionString"] ?? "?") (\(other["CFBundleVersion"] ?? "?"))"
    }

    /// Read directly instead of via Bundle, which caches and would miss a freshly copied version.
    private static func plist(ofApp path: String) -> [String: Any]? {
        NSDictionary(contentsOfFile: path + "/Contents/Info.plist") as? [String: Any]
    }
}

enum Status {
    case running, starting, stopped, conflict

    var isOn: Bool { self == .running || self == .starting }

    var label: String {
        switch self {
        case .running: "Running"
        case .starting: "Starting…"
        case .conflict: "Port in use by another app"
        case .stopped: "Stopped"
        }
    }
}

struct Service: Identifiable {
    let id: String  // launchd label
    let short: String  // CLI name
    let name: String
    let detail: String
    let port: UInt16
    let template: String
    var agent: String { Paths.agents + "/\(id).plist" }

    static let web = Service(id: "local.miniamp.web", short: "web", name: "Web Server", detail: "PHP · localhost:8888",
                             port: 8888, template: Paths.support + "/local.miniamp.web.plist")
    static let mariadb = Service(id: "sh.brew.mariadb", short: "db", name: "MariaDB", detail: "MySQL · 127.0.0.1:3306",
                                 port: 3306, template: Paths.brew + "/opt/mariadb/sh.brew.mariadb.plist")
    static let all = [web, mariadb]
}

enum Launchd {
    static let domain = "gui/\(getuid())"

    static func status(_ svc: Service) -> Status {
        let job = jobRunning(svc.id)
        let open = portOpen(svc.port)
        return job ? (open ? .running : .starting) : (open ? .conflict : .stopped)
    }

    static func start(_ svc: Service) {
        // Both jobs are KeepAlive, so "loaded but not running" means a previous stop is still shutting down.
        waitWhile { jobLoaded(svc.id) && !jobRunning(svc.id) }
        let plist = FileManager.default.fileExists(atPath: svc.agent) ? svc.agent : svc.template
        Shell.run("/bin/launchctl", ["bootstrap", domain, plist])  // fails harmlessly if already loaded
        Shell.run("/bin/launchctl", ["kickstart", "\(domain)/\(svc.id)"])
    }

    static func stop(_ svc: Service) {
        Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(svc.id)"])
        // bootout returns before the job has exited; MariaDB needs a few seconds to shut down cleanly.
        waitWhile { jobLoaded(svc.id) }
    }

    static func restart(_ svc: Service) {
        stop(svc)
        start(svc)
        waitUntilUp(svc)
    }

    /// Waits (max 30 s) until the service accepts connections.
    @discardableResult
    static func waitUntilUp(_ svc: Service) -> Bool {
        waitWhile { !portOpen(svc.port) }
        return portOpen(svc.port)
    }

    static var autostart: Bool { Service.all.allSatisfy { FileManager.default.fileExists(atPath: $0.agent) } }

    static func setAutostart(_ on: Bool) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Paths.agents, withIntermediateDirectories: true)
        for svc in Service.all {
            if on {
                if !fm.fileExists(atPath: svc.agent) { try? fm.copyItem(atPath: svc.template, toPath: svc.agent) }
            } else {
                try? fm.removeItem(atPath: svc.agent)
            }
        }
    }

    static func jobLoaded(_ label: String) -> Bool {
        Shell.run("/bin/launchctl", ["print", "\(domain)/\(label)"]).code == 0
    }

    static func jobRunning(_ label: String) -> Bool {
        let result = Shell.run("/bin/launchctl", ["print", "\(domain)/\(label)"])
        return result.code == 0 && result.output.contains("state = running")
    }

    static func portOpen(_ port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private static func waitWhile(_ condition: () -> Bool) {
        for _ in 0..<120 {  // max 30 s
            guard condition() else { return }
            usleep(250_000)
        }
    }
}

enum Shell {
    /// Apps started from Finder get a minimal PATH; Homebrew needs its own bin dir first.
    static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(Paths.brew)/bin:\(Paths.brew)/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["NONINTERACTIVE"] = "1"
        return env
    }()

    /// Runs a tool and returns its exit code and combined stdout/stderr.
    /// `onLine` receives the output line by line while the tool runs (for live logs).
    @discardableResult
    static func run(_ tool: String, _ args: [String], input: String? = nil,
                    onLine: ((String) -> Void)? = nil) -> (code: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.environment = environment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let stdin = Pipe()
        p.standardInput = input == nil ? FileHandle.nullDevice : stdin

        let lock = NSLock()
        let eof = DispatchSemaphore(value: 0)
        var output = Data()
        var pending = Data()
        func emit(_ line: Data) {
            onLine?(String(decoding: line, as: UTF8.self).replacingOccurrences(of: "\r", with: ""))
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                eof.signal()
                return
            }
            lock.lock()
            defer { lock.unlock() }
            output.append(chunk)
            guard onLine != nil else { return }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                emit(pending[pending.startIndex..<newline])
                pending.removeSubrange(pending.startIndex...newline)
            }
        }

        do {
            try p.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            onLine?("\(error.localizedDescription)")
            return (-1, error.localizedDescription)
        }
        if let input {
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try? stdin.fileHandleForWriting.close()
        }
        p.waitUntilExit()
        eof.wait()
        if !pending.isEmpty { emit(pending) }
        return (p.terminationStatus, String(decoding: output, as: UTF8.self))
    }
}
