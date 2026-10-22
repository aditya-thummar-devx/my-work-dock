// Renders each emoji the way SwiftUI's Text draws it (system font, `size` pt) into <dir>/<name>.png at 3x, on a canvas that is
// its layout box plus `margin` pt on every side (the bitmap is taller than the line box, and a wave swings out of it), and
// prints "<name> <width> <height>": the layout box in points, which is what the wave pivots around. Used by bake-buddies.py.
//
//   swift scripts/bake-emoji.swift <dir> <size> <margin> name:🐱 name:👀 ...
import AppKit

let args = CommandLine.arguments
let dir = args[1]
let size = CGFloat(Double(args[2])!)
let margin = Int(args[3])!
let scale = 3

for pair in args[4...] {
    let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
    let text = NSAttributedString(string: parts[1], attributes: [.font: NSFont.systemFont(ofSize: size)])
    let box = text.size()
    let w = Int(ceil(box.width)), h = Int(ceil(box.height))
    let cw = w + 2 * margin, ch = h + 2 * margin
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cw * scale, pixelsHigh: ch * scale, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: cw, height: ch)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    text.draw(at: NSPoint(x: CGFloat(margin) + (CGFloat(w) - box.width) / 2, y: CGFloat(margin) + (CGFloat(h) - box.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(parts[0]).png"))
    print(parts[0], w, h)
}
