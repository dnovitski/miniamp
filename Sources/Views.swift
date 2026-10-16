import AppKit
import SwiftUI

enum Open {
    static func url(_ s: String) { NSWorkspace.shared.open(URL(string: s)!) }
    static func folder(_ path: String) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }

    static func inConsole(_ path: String) {
        NSWorkspace.shared.open([URL(fileURLWithPath: path)],
                                withApplicationAt: URL(fileURLWithPath: Paths.console),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    static func mariadbLog() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Paths.mariadbData)) ?? []
        if let err = files.first(where: { $0.hasSuffix(".err") }) { inConsole(Paths.mariadbData + "/" + err) }
    }
}

extension Status {
    var color: Color {
        switch self {
        case .running: .green
        case .starting: .orange
        case .conflict: .yellow
        case .stopped: .red
        }
    }

    var emoji: String {
        switch self {
        case .running: "🟢"
        case .starting: "🟠"
        case .conflict: "🟡"
        case .stopped: "🔴"
        }
    }
}

// MARK: window

struct ContentView: View {
    enum Tab { case servers, setup }

    @ObservedObject var servers: Servers
    @ObservedObject var setup: SetupModel
    @State var tab = Tab.servers
    @State private var choseTab = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading) {
                    Text("Miniamp").font(.title2.bold())
                    Text("PHP · MariaDB · phpMyAdmin").foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $tab) {
                    Text("Servers").tag(Tab.servers)
                    Text("Setup").tag(Tab.setup)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            switch tab {
            case .servers: ServersView(servers: servers, setup: setup, showSetup: { tab = .setup })
            case .setup: SetupView(setup: setup)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onChange(of: setup.checked) { _, checked in
            // First launch on a machine without the setup: go straight to the Setup tab.
            if checked && !choseTab && !setup.isInstalled { tab = .setup }
            choseTab = true
        }
    }
}

struct ServersView: View {
    @ObservedObject var servers: Servers
    @ObservedObject var setup: SetupModel
    let showSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if setup.checked && !setup.isInstalled && !setup.running {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Setup is not complete yet.")
                    Spacer()
                    Button("Open Setup", action: showSetup)
                }
                .padding(10)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            GroupBox {
                VStack(spacing: 0) {
                    ForEach(Service.all) { svc in
                        ServiceRow(servers: servers, svc: svc)
                        if svc.id != Service.all.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 6)
            }

            HStack {
                Button { servers.anyRunning ? servers.stopAll() : servers.startAll() } label: {
                    Label(servers.anyRunning ? "Stop All" : "Start All",
                          systemImage: servers.anyRunning ? "stop.fill" : "play.fill")
                        .frame(width: 110)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(servers.anyRunning ? .red : .green)
                .disabled(servers.busy || setup.running)
                if servers.busy { ProgressView().controlSize(.small) }
                Spacer()
                Toggle("Start at login", isOn: Binding(get: { servers.autostart }, set: { servers.setAutostart($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Divider()

            HStack {
                Button { Open.url("http://localhost:8888/") } label: { Label("Website", systemImage: "globe") }
                Button { Open.url("http://localhost:8888/phpMyAdmin/") } label: {
                    Label("phpMyAdmin", systemImage: "cylinder.split.1x2")
                }
                Button { Open.folder(Paths.docroot) } label: { Label("Folder", systemImage: "folder") }
                Menu {
                    Button("Web Server Log") { Open.inConsole(Paths.webLog) }
                    Button("MariaDB Log") { Open.mariadbLog() }
                    Button("Setup Log") { Open.inConsole(Paths.setupLog) }
                } label: {
                    Label("Logs", systemImage: "doc.text")
                }
                .fixedSize()
            }

            Text("Database: root / root on 127.0.0.1:3306 · Files: ~/Sites/localhost")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ServiceRow: View {
    @ObservedObject var servers: Servers
    let svc: Service

    var body: some View {
        let st = servers.status[svc.id] ?? .stopped
        HStack(spacing: 12) {
            Circle().fill(st.color).frame(width: 12, height: 12).shadow(color: st.color.opacity(0.7), radius: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(svc.name).font(.headline)
                Text("\(svc.detail) — \(st.label)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(st.isOn ? "Stop" : "Start") { st.isOn ? servers.stop(svc) : servers.start(svc) }
                .frame(width: 70)
                .disabled(servers.busy)
        }
        .padding(.vertical, 6)
    }
}

struct SetupView: View {
    @ObservedObject var setup: SetupModel
    @State private var confirmUninstall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Installs PHP, MariaDB and phpMyAdmin with Homebrew. No admin rights needed.")
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Setup.activeSteps) { step in
                        HStack(spacing: 10) {
                            StepIcon(state: setup.states[step.id])
                            VStack(alignment: .leading, spacing: 1) {
                                Text(step.title)
                                Text(step.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button { setup.install() } label: {
                    Label(setup.isInstalled ? "Repair" : "Install", systemImage: "arrow.down.circle.fill")
                        .frame(width: 90)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                Button { setup.update() } label: { Label("Update Packages", systemImage: "arrow.triangle.2.circlepath") }
                    .controlSize(.large)
                if setup.running { ProgressView().controlSize(.small) }
                Spacer()
                Button("Uninstall…", role: .destructive) { confirmUninstall = true }
                    .controlSize(.large)
            }
            .disabled(setup.running)
            .confirmationDialog("Uninstall Miniamp?", isPresented: $confirmUninstall) {
                Button("Remove Setup", role: .destructive) { setup.uninstall(removePackages: false) }
                Button("Remove Setup and Packages", role: .destructive) { setup.uninstall(removePackages: true) }
            } message: {
                Text("Stops the servers and removes the Miniamp configuration. Your sites in ~/Sites/localhost and your databases are kept.")
            }

            LogView(setup: setup)
        }
    }
}

struct StepIcon: View {
    let state: StepState?

    var body: some View {
        Group {
            switch state {
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .running: ProgressView().controlSize(.small)
            case .todo: Image(systemName: "circle").foregroundStyle(.secondary)
            case nil: Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
            }
        }
        .frame(width: 18, height: 18)
    }
}

struct LogView: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Log").font(.headline)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(setup.logText, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy log")
                    .disabled(setup.lines.isEmpty)
                Button { Open.inConsole(Paths.setupLog) } label: { Image(systemName: "clock.arrow.circlepath") }
                    .help("Show earlier runs in Console")
                Button { setup.clearLog() } label: { Image(systemName: "trash") }
                    .help("Clear")
                    .disabled(setup.lines.isEmpty || setup.running)
            }
            .buttonStyle(.borderless)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if setup.lines.isEmpty {
                            Text("Click Install to set everything up. Progress appears here.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(setup.lines) { line in
                            Text(line.text)
                                .foregroundStyle(color(line.text))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                }
                .frame(height: 220)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .onChange(of: setup.lines.count) { _, _ in
                    if let last = setup.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onAppear {
                    if let last = setup.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func color(_ line: String) -> Color {
        if line.hasPrefix("✗") || line.hasPrefix("Error") { return .red }
        if line.hasPrefix("✓") { return .green }
        if line.hasPrefix("==>") { return .accentColor }
        return .primary
    }
}

// MARK: menu bar

struct MenuContent: View {
    @ObservedObject var servers: Servers
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(Service.all) { svc in
            let st = servers.status[svc.id] ?? .stopped
            Text("\(st.emoji) \(svc.name) — \(st.label)")
        }
        Divider()
        Button(servers.anyRunning ? "Stop All" : "Start All") { servers.anyRunning ? servers.stopAll() : servers.startAll() }
            .disabled(servers.busy)
        Divider()
        Button("Open Website") { Open.url("http://localhost:8888/") }
        Button("Open phpMyAdmin") { Open.url("http://localhost:8888/phpMyAdmin/") }
        Button("Open Folder") { Open.folder(Paths.docroot) }
        Divider()
        Button("Show Control Panel…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit Control Panel") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
