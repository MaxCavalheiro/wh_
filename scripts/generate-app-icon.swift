//
//  generate-app-icon.swift
//  wh
//
//  Regenerates Assets.xcassets/AppIcon.appiconset from the wordmark used on wh_.app's
//  website (wh-web/src/app/icon.svg), following Apple's macOS icon grid.
//
//  Usage: swift scripts/generate-app-icon.swift wh/Assets.xcassets/AppIcon.appiconset
//

import AppKit
import CoreText

// Colours from wh-web/src/app/icon.svg
let bg = NSColor(srgbRed: 0x0b/255, green: 0x0b/255, blue: 0x0d/255, alpha: 1)
let fg = NSColor(srgbRed: 0xf4/255, green: 0xf4/255, blue: 0xf5/255, alpha: 1)
let accent = NSColor(srgbRed: 0xf6/255, green: 0xa5/255, blue: 0x3a/255, alpha: 1)

// Apple's macOS icon grid, in units of a 1024 canvas.
let refCanvas: CGFloat = 1024
let refSide: CGFloat = 824
let refRadius: CGFloat = 185.4

func attributed(_ size: CGFloat) -> NSAttributedString {
    let font = NSFont.systemFont(ofSize: size, weight: .bold)
    let s = NSMutableAttributedString()
    s.append(NSAttributedString(string: "wh", attributes: [
        .font: font, .foregroundColor: fg, .kern: -size * 0.028,
    ]))
    s.append(NSAttributedString(string: "_", attributes: [
        .font: font, .foregroundColor: accent,
    ]))
    return s
}

/// Tight bounds of the drawn glyphs — what should be centred. The typographic line box
/// would push the mark up, since "_" sits below the baseline.
func glyphBounds(_ s: NSAttributedString) -> CGRect {
    CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(s), .useGlyphPathBounds)
}

/// Draws the icon at its native pixel size, so the text is hinted for that size rather
/// than downscaled from a large master. `fill` is the share of the body the wordmark spans;
/// small sizes need a bigger share to keep the letters legible.
func makeIcon(px: Int, fill: CGFloat) -> NSBitmapImageRep {
    let canvas = CGFloat(px)
    let scale = canvas / refCanvas
    let side = refSide * scale
    let origin = (canvas - side) / 2

    let probe = glyphBounds(attributed(100))
    let fontSize = (side * fill / probe.width) * 100
    let text = attributed(fontSize)
    let bounds = glyphBounds(text)

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext

    // Continuous-corner squircle, the shape macOS uses. `render(in:)` ignores the layer's
    // position and draws at the context origin, so translate first.
    let layer = CALayer()
    layer.frame = CGRect(x: 0, y: 0, width: side, height: side)
    layer.backgroundColor = bg.cgColor
    layer.cornerRadius = refRadius * scale
    layer.cornerCurve = .continuous
    ctx.saveGState()
    ctx.translateBy(x: origin, y: origin)
    layer.render(in: ctx)
    ctx.restoreGState()

    ctx.textPosition = CGPoint(x: canvas / 2 - bounds.midX, y: canvas / 2 - bounds.midY)
    CTLineDraw(CTLineCreateWithAttributedString(text), ctx)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
    ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in specs {
    // Below ~64px the wordmark needs the extra width to stay readable.
    let fill: CGFloat = px <= 32 ? 0.80 : (px <= 64 ? 0.70 : 0.62)
    let rep = makeIcon(px: px, fill: fill)
    try! rep.representation(using: .png, properties: [:])!
        .write(to: out.appending(path: "\(name).png"))
}
print("wrote \(specs.count) files")
