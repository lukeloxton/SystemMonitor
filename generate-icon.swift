#!/usr/bin/env swift
import AppKit

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // Background: rounded square
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                        cornerWidth: size * 0.22, cornerHeight: size * 0.22, transform: nil)
    ctx.addPath(bgPath)
    ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1))
    ctx.fillPath()

    // Render SF Symbol
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .medium)
    let symbol = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!

    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    NSColor.white.set()
    symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
    NSGraphicsContext.current!.cgContext.setBlendMode(.sourceIn)
    NSGraphicsContext.current!.cgContext.fill(NSRect(origin: .zero, size: symbol.size))
    tinted.unlockFocus()

    let symbolRect = NSRect(
        x: (size - tinted.size.width) / 2,
        y: (size - tinted.size.height) / 2,
        width: tinted.size.width,
        height: tinted.size.height
    )
    tinted.draw(in: symbolRect)

    img.unlockFocus()
    return img
}

let iconsetPath = "/tmp/SystemMonitor.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (name, size) in sizes {
    let img = drawIcon(size: CGFloat(size))
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetPath, "-o", "AppIcon.icns"]
try! proc.run()
proc.waitUntilExit()
print("Generated AppIcon.icns")
