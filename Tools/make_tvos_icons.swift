#!/usr/bin/env swift
// Generates LiveAirspaceTV/Assets.xcassets: the layered tvOS app icon and the Top Shelf images.
// Usage: swift Tools/make_tvos_icons.swift   (run from the repo root)
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = "LiveAirspaceTV/Assets.xcassets"
let brand = "\(root)/App Icon & Top Shelf Image.brandassets"
let bg = CGColor(red: 0.012, green: 0.022, blue: 0.035, alpha: 1)
let ink = CGColor(red: 0.55, green: 0.95, blue: 0.85, alpha: 1)
let cyan = CGColor(red: 0.40, green: 0.80, blue: 1.0, alpha: 1)
let amber = CGColor(red: 1.0, green: 0.78, blue: 0.35, alpha: 1)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func write(_ path: String, _ text: String) {
    try! FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try! text.write(toFile: path, atomically: true, encoding: .utf8)
}

func png(_ path: String, _ w: Int, _ h: Int, opaque: Bool, _ draw: (CGContext, CGFloat, CGFloat) -> Void) {
    let info = (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)  // y down, like the app
    ctx.setAllowsAntialiasing(true)
    draw(ctx, CGFloat(w), CGFloat(h))
    try! FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(dest))
}

// MARK: artwork

func background(_ c: CGContext, _ w: CGFloat, _ h: CGFloat, glowAt p: CGPoint) {
    c.setFillColor(bg); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let colors = [CGColor(red: 0.10, green: 0.30, blue: 0.30, alpha: 0.55), CGColor(red: 0, green: 0, blue: 0, alpha: 0)] as CFArray
    let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    c.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: max(w, h) * 0.7, options: [])
}

func rings(_ c: CGContext, center: CGPoint, radius: CGFloat) {
    c.setLineWidth(max(radius * 0.014, 1.5))
    for i in 1...3 {
        c.setStrokeColor(ink.copy(alpha: 0.10 + 0.05 * CGFloat(4 - i))!)
        let r = radius * CGFloat(i) / 3
        c.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    }
    c.setStrokeColor(ink.copy(alpha: 0.18)!)
    c.setLineDash(phase: 0, lengths: [radius * 0.02, radius * 0.04])
    c.move(to: CGPoint(x: center.x - radius, y: center.y)); c.addLine(to: CGPoint(x: center.x + radius, y: center.y))
    c.move(to: CGPoint(x: center.x, y: center.y - radius)); c.addLine(to: CGPoint(x: center.x, y: center.y + radius))
    c.strokePath(); c.setLineDash(phase: 0, lengths: [])
}

func trail(_ c: CGContext, from a: CGPoint, to b: CGPoint, width: CGFloat) {
    let steps = 14
    for i in 0..<steps {
        let t0 = CGFloat(i) / CGFloat(steps), t1 = CGFloat(i + 1) / CGFloat(steps)
        c.setStrokeColor(cyan.copy(alpha: 0.5 * t1)!)
        c.setLineWidth(width)
        c.setLineCap(.round)
        c.move(to: CGPoint(x: a.x + (b.x - a.x) * t0, y: a.y + (b.y - a.y) * t0))
        c.addLine(to: CGPoint(x: a.x + (b.x - a.x) * t1, y: a.y + (b.y - a.y) * t1))
        c.strokePath()
    }
}

/// The same airplane silhouette the radar uses, pointing up, scaled by `s`.
func plane(_ c: CGContext, at p: CGPoint, size s: CGFloat, headingDeg: CGFloat, color: CGColor) {
    let pts: [(CGFloat, CGFloat)] = [(0, -1), (0.16, -0.35), (0.95, 0.25), (0.95, 0.45), (0.16, 0.2), (0.12, 0.7), (0.4, 0.9), (0.4, 1.0),
                                      (0, 0.88), (-0.4, 1.0), (-0.4, 0.9), (-0.12, 0.7), (-0.16, 0.2), (-0.95, 0.45), (-0.95, 0.25), (-0.16, -0.35)]
    c.saveGState()
    c.translateBy(x: p.x, y: p.y); c.rotate(by: headingDeg * .pi / 180)
    c.beginPath()
    for (i, q) in pts.enumerated() { let pt = CGPoint(x: q.0 * s, y: q.1 * s); i == 0 ? c.move(to: pt) : c.addLine(to: pt) }
    c.closePath(); c.setFillColor(color); c.fillPath()
    c.restoreGState()
}

enum Layer { case back, middle, front }

func icon(_ layer: Layer, _ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let center = CGPoint(x: w / 2, y: h / 2)
    let r = h * 0.46
    switch layer {
    case .back:
        background(c, w, h, glowAt: center)
    case .middle:
        rings(c, center: center, radius: r)
        trail(c, from: CGPoint(x: center.x - r * 0.62, y: center.y + r * 0.62), to: CGPoint(x: center.x - r * 0.12, y: center.y + r * 0.12), width: h * 0.018)
    case .front:
        plane(c, at: center, size: h * 0.20, headingDeg: 45, color: cyan)
        let ring = h * 0.30
        c.setStrokeColor(cyan.copy(alpha: 0.55)!); c.setLineWidth(h * 0.009)
        c.strokeEllipse(in: CGRect(x: center.x - ring, y: center.y - ring, width: 2 * ring, height: 2 * ring))
        // an amber low-altitude blip
        c.setFillColor(amber); let b = h * 0.025
        c.fillEllipse(in: CGRect(x: center.x + r * 0.55 - b, y: center.y + r * 0.45 - b, width: 2 * b, height: 2 * b))
    }
}

func topShelf(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let radarCenter = CGPoint(x: w * 0.74, y: h * 0.5)
    background(c, w, h, glowAt: radarCenter)
    rings(c, center: radarCenter, radius: h * 0.46)
    trail(c, from: CGPoint(x: radarCenter.x - h * 0.30, y: radarCenter.y + h * 0.30), to: CGPoint(x: radarCenter.x - h * 0.05, y: radarCenter.y + h * 0.05), width: h * 0.012)
    plane(c, at: radarCenter, size: h * 0.13, headingDeg: 45, color: cyan)
    c.setFillColor(amber); let b = h * 0.016
    c.fillEllipse(in: CGRect(x: radarCenter.x + h * 0.25 - b, y: radarCenter.y + h * 0.2 - b, width: 2 * b, height: 2 * b))
    // title, drawn y-up for CoreText
    c.saveGState(); c.translateBy(x: 0, y: h); c.scaleBy(x: 1, y: -1)
    func text(_ s: String, size: CGFloat, color: CGColor, x: CGFloat, y: CGFloat, weight: CGFloat) {
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, size, nil)
        let attrs = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs)!)
        c.textPosition = CGPoint(x: x, y: y); CTLineDraw(line, c)
    }
    text("LIVE AIRSPACE", size: h * 0.12, color: ink, x: w * 0.07, y: h * 0.52, weight: 1)
    text("three feeds. one sky.", size: h * 0.055, color: ink.copy(alpha: 0.65)!, x: w * 0.07, y: h * 0.40, weight: 0)
    c.restoreGState()
}

// MARK: catalog

let info = #""info" : { "author" : "xcode", "version" : 1 }"#

func imageset(_ dir: String, name: String, sizes: [(scale: String, w: Int, h: Int)], draw: @escaping (CGContext, CGFloat, CGFloat) -> Void, opaque: Bool) {
    var images: [String] = []
    for s in sizes {
        let file = "\(name)-\(s.scale).png"
        png("\(dir)/\(file)", s.w, s.h, opaque: opaque, draw)
        images.append(#"{ "idiom" : "tv", "filename" : "\#(file)", "scale" : "\#(s.scale)" }"#)
    }
    write("\(dir)/Contents.json", "{\n  \"images\" : [\n    \(images.joined(separator: ",\n    "))\n  ],\n  \(info)\n}\n")
}

func imagestack(_ dir: String, w: Int, h: Int, twoX: Bool) {
    let layers: [(String, Layer)] = [("Front", .front), ("Middle", .middle), ("Back", .back)]
    write("\(dir)/Contents.json", "{\n  \"layers\" : [\n" + layers.map { "    { \"filename\" : \"\($0.0).imagestacklayer\" }" }.joined(separator: ",\n") + "\n  ],\n  \(info)\n}\n")
    for (name, layer) in layers {
        let ld = "\(dir)/\(name).imagestacklayer"
        write("\(ld)/Contents.json", "{\n  \(info)\n}\n")
        let sizes = twoX ? [("1x", w, h), ("2x", w * 2, h * 2)] : [("1x", w, h)]
        imageset("\(ld)/Content.imageset", name: name, sizes: sizes.map { (scale: $0.0, w: $0.1, h: $0.2) },
                 draw: { icon(layer, $0, $1, $2) }, opaque: layer == .back)
    }
}

try? FileManager.default.removeItem(atPath: root)
write("\(root)/Contents.json", "{\n  \(info)\n}\n")
write("\(brand)/Contents.json", """
{
  "assets" : [
    { "size" : "1280x768", "idiom" : "tv", "filename" : "App Icon - App Store.imagestack", "role" : "primary-app-icon" },
    { "size" : "400x240", "idiom" : "tv", "filename" : "App Icon.imagestack", "role" : "primary-app-icon" },
    { "size" : "2320x720", "idiom" : "tv", "filename" : "Top Shelf Image Wide.imageset", "role" : "top-shelf-image-wide" },
    { "size" : "1920x720", "idiom" : "tv", "filename" : "Top Shelf Image.imageset", "role" : "top-shelf-image" }
  ],
  \(info)
}

""")
imagestack("\(brand)/App Icon - App Store.imagestack", w: 1280, h: 768, twoX: false)
imagestack("\(brand)/App Icon.imagestack", w: 400, h: 240, twoX: true)
imageset("\(brand)/Top Shelf Image.imageset", name: "TopShelf", sizes: [("1x", 1920, 720), ("2x", 3840, 1440)], draw: topShelf, opaque: true)
imageset("\(brand)/Top Shelf Image Wide.imageset", name: "TopShelfWide", sizes: [("1x", 2320, 720), ("2x", 4640, 1440)], draw: topShelf, opaque: true)
print("wrote \(root)")
