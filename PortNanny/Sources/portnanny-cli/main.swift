import Foundation
import PortNannyCore

// The standalone CLI (bundled as Contents/Helpers/portnanny): the same
// commands as `PortNanny.app/Contents/MacOS/PortNanny <command>`,
// without AppKit linked in. No arguments means usage, not a GUI.
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty {
    print(CLIArguments.usage)
    exit(CLIExit.ok)
}
exit(PortNannyCLI.run(arguments) ?? CLIExit.usage)
