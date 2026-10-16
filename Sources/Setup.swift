// Install, update and uninstall, shared by the Setup tab and the CLI.
//
// Install walks through the steps in order. Each step has a `check` (is it already done?) and a `run`
// (do it). Steps that pass their check are skipped, so Install doubles as "Repair" and is safe to repeat.

import Foundation

struct SetupError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum StepState { case todo, running, done, failed }

struct SetupStep: Identifiable {
    let id: String
    let title: String
    let detail: String
    let check: () -> Bool
    let run: (_ log: @escaping (String) -> Void) throws -> Void
}

enum Setup {
    typealias Log = (String) -> Void
    typealias Progress = (_ step: String, _ state: StepState) -> Void

    static let steps: [SetupStep] = [
        SetupStep(id: "homebrew", title: "Homebrew", detail: "/opt/homebrew, writable without admin rights",
                  check: {
                      let fm = FileManager.default
                      return fm.isExecutableFile(atPath: Paths.brewBin) && fm.isWritableFile(atPath: Paths.brew)
                  },
                  run: { _ in
                      if !FileManager.default.isExecutableFile(atPath: Paths.brewBin) {
                          throw SetupError("Homebrew is not installed. Install it from https://brew.sh (this needs an admin once), then click Install again.")
                      }
                      throw SetupError("\(Paths.brew) is not writable by your user, so packages cannot be installed without admin rights.")
                  }),

        SetupStep(id: "packages", title: "PHP, MariaDB and phpMyAdmin", detail: "brew install php mariadb phpmyadmin",
                  check: {
                      let fm = FileManager.default
                      return fm.isExecutableFile(atPath: Paths.php) && fm.isExecutableFile(atPath: Paths.mariadb)
                          && fm.fileExists(atPath: Paths.phpMyAdmin + "/index.php")
                  },
                  run: { log in
                      try brew(["install", "php", "mariadb", "phpmyadmin"], log)
                  }),

        SetupStep(id: "mariadb-network", title: "MariaDB on 127.0.0.1 only", detail: "Not reachable from the network",
                  check: { (try? String(contentsOfFile: Paths.mariadbConf, encoding: .utf8)) == mariadbConf },
                  run: { log in
                      try FileManager.default.createDirectory(atPath: (Paths.mariadbConf as NSString).deletingLastPathComponent,
                                                              withIntermediateDirectories: true)
                      try mariadbConf.write(toFile: Paths.mariadbConf, atomically: true, encoding: .utf8)
                      log("Wrote \(Paths.mariadbConf)")
                      if Launchd.jobLoaded(Service.mariadb.id) {
                          log("Restarting MariaDB…")
                          Launchd.restart(.mariadb)
                      }
                  }),

        SetupStep(id: "mariadb-users", title: "MariaDB user root / root", detail: "Default login; anonymous users removed",
                  check: {
                      Shell.run(Paths.mariadb, ["-uroot", "-proot", "-h127.0.0.1", "-N", "-e",
                                                "SELECT COUNT(*) FROM mysql.global_priv WHERE User=''"]).output
                          .trimmingCharacters(in: .whitespacesAndNewlines) == "0"
                  },
                  run: { log in
                      if !Launchd.portOpen(Service.mariadb.port) {
                          log("Starting MariaDB…")
                          Launchd.start(.mariadb)
                          guard Launchd.waitUntilUp(.mariadb) else { throw SetupError("MariaDB did not start. See the MariaDB log.") }
                      }
                      // As the macOS user, which Homebrew's MariaDB grants full access via unix_socket.
                      let result = Shell.run(Paths.mariadb, [], input: """
                          ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket OR mysql_native_password USING PASSWORD('root');
                          DELETE FROM mysql.global_priv WHERE User='';
                          FLUSH PRIVILEGES;
                          """, onLine: log)
                      guard result.code == 0 else { throw SetupError("Could not configure the MariaDB users.") }
                      log("root password set to 'root'")
                  }),

        SetupStep(id: "phpmyadmin", title: "phpMyAdmin auto-login", detail: "No login screen",
                  check: {
                      (try? String(contentsOfFile: Paths.phpMyAdminConfig, encoding: .utf8))?.contains(pmaAutoLogin) ?? false
                  },
                  run: { log in
                      var config = try String(contentsOfFile: Paths.phpMyAdminConfig, encoding: .utf8)
                      if config.contains(pmaCookie) {
                          config = config.replacingOccurrences(of: pmaCookie, with: pmaAutoLogin)
                      } else {
                          config += "\n" + pmaAutoLogin + "\n"
                      }
                      let secret = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
                      config = config.replacingOccurrences(of: "$cfg['blowfish_secret'] = '';",
                                                           with: "$cfg['blowfish_secret'] = '\(secret)';")
                      try config.write(toFile: Paths.phpMyAdminConfig, atomically: true, encoding: .utf8)
                      log("Updated \(Paths.phpMyAdminConfig)")
                  }),

        SetupStep(id: "webserver", title: "Web server", detail: "~/Sites/localhost on localhost:8888, phpMyAdmin at /phpMyAdmin/",
                  check: {
                      let fm = FileManager.default
                      let plist = NSDictionary(contentsOfFile: Service.web.template)
                      return (try? String(contentsOfFile: Paths.router, encoding: .utf8)) == routerPHP
                          && plist?.isEqual(to: webPlist) == true
                          && (try? fm.destinationOfSymbolicLink(atPath: Paths.docroot + "/phpMyAdmin")) == Paths.phpMyAdmin
                          && hasIndex()
                  },
                  run: { log in
                      let fm = FileManager.default
                      for dir in [Paths.support, Paths.logs, Paths.docroot] {
                          try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                      }
                      try routerPHP.write(toFile: Paths.router, atomically: true, encoding: .utf8)
                      let data = try PropertyListSerialization.data(fromPropertyList: webPlist, format: .xml, options: 0)
                      try data.write(to: URL(fileURLWithPath: Service.web.template))
                      if fm.fileExists(atPath: Service.web.agent) {
                          try? fm.removeItem(atPath: Service.web.agent)
                          try fm.copyItem(atPath: Service.web.template, toPath: Service.web.agent)
                      }
                      let link = Paths.docroot + "/phpMyAdmin"
                      if (try? fm.destinationOfSymbolicLink(atPath: link)) != Paths.phpMyAdmin {
                          try? fm.removeItem(atPath: link)
                          try fm.createSymbolicLink(atPath: link, withDestinationPath: Paths.phpMyAdmin)
                      }
                      if !hasIndex() {
                          try welcomePHP.write(toFile: Paths.docroot + "/index.php", atomically: true, encoding: .utf8)
                          log("Added a start page to \(Paths.docroot)")
                      }
                      log("Configured the web server")
                      if Launchd.jobLoaded(Service.web.id) {
                          log("Restarting the web server…")
                          Launchd.restart(.web)
                      }
                  }),

        SetupStep(id: "cli", title: "Command line tool", detail: "miniamp in \(Paths.brew)/bin",
                  check: {
                      (try? FileManager.default.destinationOfSymbolicLink(atPath: Paths.cliLink)) == AppInfo.executable.path
                  },
                  run: { log in
                      let fm = FileManager.default
                      if (try? fm.destinationOfSymbolicLink(atPath: Paths.cliLink)) == nil && fm.fileExists(atPath: Paths.cliLink) {
                          throw SetupError("\(Paths.cliLink) exists and is not ours; leaving it alone.")
                      }
                      try? fm.removeItem(atPath: Paths.cliLink)
                      try fm.createSymbolicLink(atPath: Paths.cliLink, withDestinationPath: AppInfo.executable.path)
                      log("Linked \(Paths.cliLink) -> \(AppInfo.executable.path)")
                  }),
    ]

    static var isInstalled: Bool { steps.allSatisfy { $0.check() } }

    // MARK: operations

    /// Runs every step that is not done yet, then enables start at login and starts both services.
    @discardableResult
    static func install(log: @escaping Log, progress: @escaping Progress = { _, _ in }) -> Bool {
        let log = fileLogged(log, "Install")
        for step in steps {
            if step.check() {
                progress(step.id, .done)
                log("✓ \(step.title)")
                continue
            }
            progress(step.id, .running)
            log("==> \(step.title)")
            do {
                try step.run(log)
                guard step.check() else { throw SetupError("Still not done after running this step.") }
                progress(step.id, .done)
                log("✓ \(step.title)")
            } catch {
                progress(step.id, .failed)
                log("✗ \(error.localizedDescription)")
                log("Install stopped. Fix the problem above and click Install again.")
                return false
            }
        }
        log("==> Start at login, starting services")
        Launchd.setAutostart(true)
        for svc in Service.all {
            Launchd.start(svc)
            log(Launchd.waitUntilUp(svc) ? "✓ \(svc.name) running" : "✗ \(svc.name) did not start, see its log")
        }
        log("Done. Sites: http://localhost:8888 · phpMyAdmin: http://localhost:8888/phpMyAdmin/")
        return true
    }

    /// Upgrades the Homebrew packages, restarts what was running and repairs the setup if needed.
    @discardableResult
    static func update(log: @escaping Log, progress: @escaping Progress = { _, _ in }) -> Bool {
        let fileLog = fileLogged(log, "Update")
        do {
            fileLog("==> brew update")
            try brew(["update"], fileLog)
            fileLog("==> brew upgrade php mariadb phpmyadmin")
            try brew(["upgrade", "php", "mariadb", "phpmyadmin"], fileLog)
        } catch {
            fileLog("✗ \(error.localizedDescription)")
            return false
        }
        let wasRunning = Service.all.filter { Launchd.status($0).isOn }
        for svc in wasRunning {
            fileLog("Restarting \(svc.name)…")
            Launchd.restart(svc)
        }
        return install(log: log, progress: progress)
    }

    /// Stops the services and removes the Miniamp configuration. Sites and databases are always kept.
    @discardableResult
    static func uninstall(removePackages: Bool, log: @escaping Log, progress: @escaping Progress = { _, _ in }) -> Bool {
        let log = fileLogged(log, "Uninstall")
        let fm = FileManager.default
        for svc in Service.all {
            log("Stopping \(svc.name)…")
            Launchd.stop(svc)
        }
        Launchd.setAutostart(false)
        log("Removed start at login")
        if let config = try? String(contentsOfFile: Paths.phpMyAdminConfig, encoding: .utf8), config.contains(pmaAutoLogin) {
            try? config.replacingOccurrences(of: pmaAutoLogin, with: pmaCookie)
                .write(toFile: Paths.phpMyAdminConfig, atomically: true, encoding: .utf8)
            log("phpMyAdmin asks for a login again")
        }
        for path in [Paths.mariadbConf, Paths.docroot + "/phpMyAdmin", Paths.support] where fm.fileExists(atPath: path)
            || (try? fm.destinationOfSymbolicLink(atPath: path)) != nil {
            try? fm.removeItem(atPath: path)
            log("Removed \(path)")
        }
        if (try? fm.destinationOfSymbolicLink(atPath: Paths.cliLink)) == AppInfo.executable.path {
            try? fm.removeItem(atPath: Paths.cliLink)
            log("Removed \(Paths.cliLink)")
        }
        if removePackages {
            log("==> brew uninstall phpmyadmin mariadb php")
            do { try brew(["uninstall", "phpmyadmin", "mariadb", "php"], log) } catch {
                log("✗ \(error.localizedDescription)")
                return false
            }
        }
        for step in steps { progress(step.id, step.check() ? .done : .todo) }
        log("Done. Your sites in \(Paths.docroot) and databases in \(Paths.mariadbData) were kept.")
        return true
    }

    // MARK: helpers

    /// PHP's built-in server has no directory listing, so without an index page "/" is a 404.
    private static func hasIndex() -> Bool {
        ["index.php", "index.html", "index.htm"].contains { FileManager.default.fileExists(atPath: Paths.docroot + "/" + $0) }
    }

    private static func brew(_ args: [String], _ log: @escaping Log) throws {
        let result = Shell.run(Paths.brewBin, args, onLine: log)
        if result.code != 0 { throw SetupError("brew \(args.joined(separator: " ")) failed (exit code \(result.code)).") }
    }

    /// Also appends everything to ~/Library/Logs/miniamp/setup.log.
    private static func fileLogged(_ log: @escaping Log, _ title: String) -> Log {
        try? FileManager.default.createDirectory(atPath: Paths.logs, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: Paths.setupLog) {
            FileManager.default.createFile(atPath: Paths.setupLog, contents: nil)
        }
        let file = FileHandle(forWritingAtPath: Paths.setupLog)
        file?.seekToEndOfFile()
        let write = { (line: String) in file?.write(Data((line + "\n").utf8)) }
        write("\n=== \(title) \(Date().formatted(date: .numeric, time: .standard)) — Miniamp \(AppInfo.version)")
        return { line in
            write(line)
            log(line)
        }
    }

    // MARK: generated files

    static let mariadbConf = "[mysqld]\nbind-address = 127.0.0.1\n"

    static let pmaCookie = "$cfg['Servers'][$i]['auth_type'] = 'cookie';"
    static let pmaAutoLogin = """
        $cfg['Servers'][$i]['auth_type'] = 'config';
        $cfg['Servers'][$i]['user'] = 'root';
        $cfg['Servers'][$i]['password'] = 'root';
        """

    static var webPlist: [String: Any] {
        [
            "Label": Service.web.id,
            "ProgramArguments": [Paths.php, "-S", "127.0.0.1:\(Service.web.port)", "-t", Paths.docroot, Paths.router],
            "WorkingDirectory": Paths.docroot,
            "StandardOutPath": Paths.webLog,
            "StandardErrorPath": Paths.webLog,
            "RunAtLoad": true,
            "KeepAlive": true,
        ]
    }

    static let routerPHP = """
        <?php
        // Router for the PHP built-in server: redirect /phpMyAdmin to /phpMyAdmin/ so relative links work.
        if (preg_match('#^/phpmyadmin$#i', parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH))) {
            header('Location: /phpMyAdmin/', true, 301);
            return true;
        }
        return false;

        """

    static let welcomePHP = """
        <?php
        try {
            $dbVersion = (new mysqli('localhost', 'root', 'root'))->server_info;
        } catch (Throwable $e) {
            $dbVersion = 'not reachable';
        }
        ?>
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <title>Miniamp</title>
          <style>
            body { font: 15px -apple-system, system-ui, sans-serif; margin: 0; min-height: 100vh; display: grid;
                   place-items: center; background: linear-gradient(160deg, #9384ff, #3a27b8); color: #1d1d1f; }
            main { background: #fff; border-radius: 18px; padding: 32px 40px; box-shadow: 0 20px 60px #0004; max-width: 460px; }
            h1 { margin: 0 0 4px; font-size: 26px; }
            p { color: #555; }
            a { display: inline-block; margin: 6px 8px 0 0; padding: 8px 14px; border-radius: 8px; background: #5b47f0;
                color: #fff; text-decoration: none; }
            code { background: #f2f0ff; padding: 2px 6px; border-radius: 5px; }
          </style>
        </head>
        <body>
          <main>
            <h1>Miniamp is running</h1>
            <p>PHP <?= PHP_VERSION ?> · MariaDB <?= htmlspecialchars($dbVersion) ?></p>
            <p>Put your files in <code><?= htmlspecialchars(__DIR__) ?></code>.</p>
            <a href="/phpMyAdmin/">phpMyAdmin</a>
          </main>
        </body>
        </html>

        """
}
