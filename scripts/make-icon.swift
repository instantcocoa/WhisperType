// Generates assets/AppIcon.icns (and assets/AppIcon-1024.png).
// Usage: swift scripts/make-icon.swift <assets-dir>
// Design: macOS squircle, indigo→violet gradient, white voice-waveform bars
// ending in a text caret (voice → text).
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets"
let S: CGFloat = 1024

func render() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Apple icon grid: 824pt squircle centered in 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    // Gradient body
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: cs, colors: [
        NSColor(red: 0.52, green: 0.33, blue: 0.98, alpha: 1).cgColor,
        NSColor(red: 0.20, green: 0.16, blue: 0.62, alpha: 1).cgColor] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Soft top highlight
    let hi = CGGradient(colorsSpace: cs, colors: [
        NSColor.white.withAlphaComponent(0.22).cgColor,
        NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(hi, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // Waveform bars + caret
    let heights: [CGFloat] = [120, 250, 400, 290, 470, 330, 190]
    let barW: CGFloat = 54, gap: CGFloat = 40
    let caretW: CGFloat = 30
    let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count) * gap + caretW
    var x = (S - totalW) / 2
    let midY = S / 2
    ctx.setFillColor(NSColor.white.cgColor)
    for h in heights {
        let r = CGRect(x: x, y: midY - h / 2, width: barW, height: h)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
        ctx.fillPath()
        x += barW + gap
    }
    // Caret in warm accent
    let ch: CGFloat = 400
    ctx.setFillColor(NSColor(red: 1.0, green: 0.78, blue: 0.30, alpha: 1).cgColor)
    let cr = CGRect(x: x, y: midY - ch / 2, width: caretW, height: ch)
    ctx.addPath(CGPath(roundedRect: cr, cornerWidth: 6, cornerHeight: 6, transform: nil))
    ctx.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let rep = render()
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/AppIcon-1024.png"))
