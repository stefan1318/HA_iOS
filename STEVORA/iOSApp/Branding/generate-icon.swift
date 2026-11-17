import AppKit
import Foundation

// Use the exact approved STEVORA visual asset, shared with Android.
let source = URL(fileURLWithPath: "STEVORA/iOSApp/Branding/stevora-logo.png")
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
guard let image = NSImage(contentsOf: source),
      let tiff = image.tiffRepresentation,
      let representation = NSBitmapImageRep(data: tiff),
      let sourceCG = representation.cgImage else { fatalError("Official STEVORA logo is missing") }
let size = 1024
guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Cannot create icon context")
}
context.interpolationQuality = .high
context.draw(sourceCG, in: CGRect(x: 0, y: 0, width: size, height: size))
guard let result = context.makeImage() else { fatalError("Cannot render icon") }
let bitmap = NSBitmapImageRep(cgImage: result)
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
try png.write(to: destination)
