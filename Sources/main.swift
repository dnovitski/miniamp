// Entry point. Started by launchd (Finder, Spotlight, Dock, `open`, `miniamp open`) it is the control panel;
// started from a shell or script it is the `miniamp` CLI, where no arguments prints the help.

import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let launchedByLaunchd = getppid() == 1
// Cocoa may pass its own "-Flag value" arguments to the app; anything else is a CLI command.
if !launchedByLaunchd || arguments.first.map({ !$0.hasPrefix("-") || CLI.handles($0) }) == true {
    setvbuf(stdout, nil, _IOLBF, 0)  // stream install logs line by line, also when piped
    exit(CLI.run(arguments.isEmpty ? ["help"] : arguments))
}
MiniampApp.main()
