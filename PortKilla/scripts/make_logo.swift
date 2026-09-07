#!/usr/bin/env swift
import AppKit

// Renders the README banner in both appearances from the mascot artwork:
//   swift scripts/make_logo.swift [output dir, default ../assets]
// Writes logo-dark.png and logo-light.png (2400 x 560).

let scriptDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let packageDirectory = scriptDirectory.deletingLastPathComponent()
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : packageDirectory.deletingLastPathComponent().appendingPathComponent("assets").path)
let mascotPath = packageDirectory.appendingPathComponent("assets/mascot/quokka-happy.png").path
guard let mascot = NSImage(contentsOfFile: mascotPath) else {
    FileHandle.standardError.write(Data("no mascot at \(mascotPath)\n".utf8))
    exit(1)
}

func banner(dark: Bool) -> NSImage {
    let width: CGFloat = 2400
    let height: CGFloat = 560
    return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
        NSBezierPath(roundedRect: rect, xRadius: 48, yRadius: 48).addClip()
        let top = dark ? NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 1) : NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)
        let bottom = dark ? NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.12, alpha: 1) : NSColor(calibratedRed: 0.90, green: 0.92, blue: 0.96, alpha: 1)
        NSGradient(starting: top, ending: bottom)!.draw(in: rect, angle: -90)
        // A soft glow behind the quokka in the icon's blue.
        let glow = NSGradient(starting: NSColor(calibratedRed: 0.23, green: 0.49, blue: 0.96, alpha: dark ? 0.35 : 0.22), ending: NSColor.clear)!
        glow.draw(in: NSBezierPath(ovalIn: NSRect(x: 60, y: -120, width: 900, height: 800)), relativeCenterPosition: .zero)

        NSGraphicsContext.current?.imageInterpolation = .high
        let mascotHeight = height * 0.92
        let mascotWidth = mascotHeight * mascot.size.width / mascot.size.height
        mascot.draw(in: NSRect(x: 150, y: (height - mascotHeight) / 2 - 10, width: mascotWidth, height: mascotHeight))

        let x = 150 + mascotWidth + 90
        let ink = dark ? NSColor.white : NSColor(calibratedWhite: 0.12, alpha: 1)
        let blue = NSColor(calibratedRed: 0.25, green: 0.52, blue: 0.97, alpha: 1)
        let bold = NSFont.systemFont(ofSize: 150, weight: .bold)
        let rounded = NSFont(descriptor: bold.fontDescriptor.withDesign(.rounded) ?? bold.fontDescriptor, size: 150) ?? bold
        let word = NSMutableAttributedString(string: "Port", attributes: [.font: rounded, .foregroundColor: ink])
        word.append(NSAttributedString(string: "Killa", attributes: [.font: rounded, .foregroundColor: blue]))
        word.draw(at: NSPoint(x: x, y: 262))
        let tagline = "The macOS port manager that knows whose server it is."
        NSAttributedString(string: tagline, attributes: [.font: NSFont.systemFont(ofSize: 52, weight: .medium), .foregroundColor: ink.withAlphaComponent(0.72)])
            .draw(at: NSPoint(x: x + 6, y: 172))
        let surfaces = "Menu bar app · Workbench · CLI · MCP server for AI agents"
        NSAttributedString(string: surfaces, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 38, weight: .regular), .foregroundColor: blue.withAlphaComponent(0.95)])
            .draw(at: NSPoint(x: x + 6, y: 104))
        return true
    }
}

for (name, dark) in [("logo-dark.png", true), ("logo-light.png", false)] {
    let image = banner(dark: dark)
    guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("could not encode \(name)\n".utf8))
        exit(1)
    }
    let destination = outputDirectory.appendingPathComponent(name)
    try! png.write(to: destination)
    print("wrote \(destination.path)")
}
