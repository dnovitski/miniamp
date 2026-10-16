// `miniamp` command line: the same executable as the app, started with a command.

import AppKit
import Foundation

enum CLI {
    static let commands: Set = ["status", "start", "stop", "restart", "install", "update", "uninstall", "autostart",
                                "open", "help", "version", "-h", "--help", "--version"]

    static func handles(_ arg: String) -> Bool { commands.contains(arg) }

    static func run(_ args: [String]) -> Int32 {
        let command = args[0]
        let rest = Array(args.dropFirst())
        switch command {
        case "status":
            status()
            return 0
        case "start", "stop", "restart":
            guard let services = services(rest) else { return usage() }
            for svc in services {
                switch command {
                case "start": Launchd.start(svc)
                case "stop": Launchd.stop(svc)
                default: Launchd.restart(svc)
                }
            }
            if command != "stop" { services.forEach { Launchd.waitUntilUp($0) } }
            status()
            return 0
        case "install":
            return Setup.install(log: { print($0) }) ? 0 : 1
        case "update":
            return Setup.update(log: { print($0) }) ? 0 : 1
        case "uninstall":
            guard rest.isEmpty || rest == ["--packages"] else { return usage() }
            return Setup.uninstall(removePackages: rest == ["--packages"], log: { print($0) }) ? 0 : 1
        case "autostart":
            guard rest.count == 1, ["on", "off"].contains(rest[0]) else { return usage() }
            Launchd.setAutostart(rest[0] == "on")
            print("Start at login: \(rest[0])")
            return 0
        case "open":
            NSWorkspace.shared.open(AppInfo.bundleURL)
            return 0
        case "version", "--version":
            print("miniamp \(AppInfo.version)")
            return 0
        default:
            return usage(0)
        }
    }

    private static func services(_ args: [String]) -> [Service]? {
        switch args {
        case [], ["all"]: Service.all
        case ["web"]: [.web]
        case ["db"], ["mariadb"]: [.mariadb]
        default: nil
        }
    }

    private static func status() {
        for svc in Service.all {
            let st = Launchd.status(svc)
            print("\(st == .running ? "●" : "○") \(svc.name.padding(toLength: 11, withPad: " ", startingAt: 0)) \(st.label.lowercased()) (\(svc.detail))")
        }
        print("Start at login: \(Launchd.autostart ? "on" : "off")")
        let missing = Setup.steps.filter { !$0.check() }
        if !missing.isEmpty {
            print("Setup incomplete: \(missing.map(\.title).joined(separator: ", ")). Run `miniamp install`.")
        }
    }

    @discardableResult
    private static func usage(_ code: Int32 = 1) -> Int32 {
        print("""
            miniamp \(AppInfo.version): PHP, MariaDB and phpMyAdmin without root

            Usage:
              miniamp status                       Show the servers and the setup state
              miniamp start|stop|restart [web|db]  Control both servers, or one
              miniamp autostart on|off             Start the servers at login
              miniamp install                      Install or repair the setup
              miniamp update                       Upgrade PHP, MariaDB and phpMyAdmin
              miniamp uninstall [--packages]       Remove the setup (sites and databases are kept)
              miniamp open                         Open the control panel

            Sites: http://localhost:8888 · phpMyAdmin: http://localhost:8888/phpMyAdmin/ · MariaDB: 127.0.0.1:3306 (root/root)
            """)
        return code
    }
}
