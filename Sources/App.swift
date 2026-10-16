// SwiftUI app: window with Servers and Setup tabs, plus a menu bar extra.

import AppKit
import SwiftUI

/// Server status for the UI, polled every 2 seconds.
final class Servers: ObservableObject {
    @Published private(set) var status: [String: Status] = [:]
    @Published private(set) var autostart = false
    @Published private(set) var busy = false

    private let queue = DispatchQueue(label: "miniamp.servers")
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    var anyRunning: Bool { status.values.contains { $0.isOn } }

    func refresh() {
        queue.async {
            var result: [String: Status] = [:]
            for svc in Service.all { result[svc.id] = Launchd.status(svc) }
            let auto = Launchd.autostart
            DispatchQueue.main.async {
                self.status = result
                self.autostart = auto
            }
        }
    }

    func start(_ svc: Service) { perform { Launchd.start(svc) } }
    func stop(_ svc: Service) { perform { Launchd.stop(svc) } }
    func startAll() { perform { Service.all.forEach(Launchd.start) } }
    func stopAll() { perform { Service.all.forEach(Launchd.stop) } }

    func setAutostart(_ on: Bool) {
        autostart = on
        perform { Launchd.setAutostart(on) }
    }

    private func perform(_ work: @escaping () -> Void) {
        busy = true
        queue.async {
            work()
            DispatchQueue.main.async {
                self.busy = false
                self.refresh()
            }
        }
    }
}

/// Setup checklist and the live log of the last install/update/uninstall.
final class SetupModel: ObservableObject {
    struct Line: Identifiable {
        let id: Int
        let text: String
    }

    @Published private(set) var states: [String: StepState] = [:]
    @Published private(set) var lines: [Line] = []
    @Published private(set) var running = false
    @Published private(set) var checked = false

    private let queue = DispatchQueue(label: "miniamp.setup")
    var onFinish: () -> Void = {}

    var isInstalled: Bool { Setup.steps.allSatisfy { states[$0.id] == .done } }
    var logText: String { lines.map(\.text).joined(separator: "\n") }

    init() { refresh() }

    func refresh() {
        guard !running else { return }
        queue.async {
            var result: [String: StepState] = [:]
            for step in Setup.steps { result[step.id] = step.check() ? .done : .todo }
            DispatchQueue.main.async {
                self.states = result
                self.checked = true
            }
        }
    }

    func install() { operation { Setup.install(log: $0, progress: $1) } }
    func update() { operation { Setup.update(log: $0, progress: $1) } }
    func uninstall(removePackages: Bool) { operation { Setup.uninstall(removePackages: removePackages, log: $0, progress: $1) } }
    func clearLog() { lines = [] }

    private func operation(_ work: @escaping (@escaping Setup.Log, @escaping Setup.Progress) -> Bool) {
        running = true
        lines = []
        let log: Setup.Log = { text in
            DispatchQueue.main.async { self.lines.append(Line(id: self.lines.count, text: text)) }
        }
        let progress: Setup.Progress = { id, state in
            DispatchQueue.main.async { self.states[id] = state }
        }
        queue.async {
            _ = work(log, progress)
            DispatchQueue.main.async {
                self.running = false
                self.refresh()
                self.onFinish()
            }
        }
    }
}

struct MiniampApp: App {
    @StateObject private var servers = Servers()
    @StateObject private var setup = SetupModel()

    var body: some Scene {
        Window("Miniamp", id: "main") {
            ContentView(servers: servers, setup: setup)
                .onAppear { setup.onFinish = { [servers] in servers.refresh() } }
        }
        .windowResizability(.contentSize)
        MenuBarExtra("Miniamp", systemImage: "server.rack") { MenuContent(servers: servers) }
    }
}
