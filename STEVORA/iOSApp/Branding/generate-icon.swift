import AppKit
import Foundation

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.09, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
let cyan = NSColor(calibratedRed: 0.22, green: 0.82, blue: 0.91, alpha: 1)
let symbol = "S" as NSString
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 700, weight: .black),
    .foregroundColor: cyan
]
let bounds = symbol.size(withAttributes: attrs)
symbol.draw(at: NSPoint(x: (CGFloat(size) - bounds.width) / 2,
                        y: (CGFloat(size) - bounds.height) / 2 - 18), withAttributes: attrs)
image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG generation failed") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
