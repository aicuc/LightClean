import AppKit
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.12, green: 0.40, blue: 0.33, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), xRadius: 225, yRadius: 225).fill()
if let symbol = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 500, weight: .regular).applying(.init(paletteColors: [.init(calibratedRed: 0.76, green: 0.91, blue: 0.72, alpha: 1)]))
    symbol.withSymbolConfiguration(config)?.draw(in: NSRect(x: 240, y: 230, width: 550, height: 550))
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
