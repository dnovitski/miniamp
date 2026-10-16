// Entry point: `miniamp <command>` runs the CLI, anything else opens the control panel.

import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
if let command = arguments.first, CLI.handles(command) {
    setvbuf(stdout, nil, _IOLBF, 0)  // stream install logs line by line, also when piped
    exit(CLI.run(arguments))
}
MiniampApp.main()
