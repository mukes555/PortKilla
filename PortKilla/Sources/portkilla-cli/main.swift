import Foundation
import PortKillaCore

// The standalone CLI (bundled as Contents/Helpers/portkilla): the same
// commands as `PortKilla.app/Contents/MacOS/PortKilla <command>`,
// without AppKit linked in. No arguments means usage, not a GUI.
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty {
    print(CLIArguments.usage)
    exit(CLIExit.ok)
}
exit(PortKillaCLI.run(arguments) ?? CLIExit.usage)
