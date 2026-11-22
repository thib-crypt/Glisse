// Génère Resources/AppIcon.icns — usage : swift scripts/make_icon.swift <dossier-sortie>
import AppKit

let S: CGFloat = 1024
func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func render() -> CGImage {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Grille d'icône macOS : corps 824 pt centré, coins continus.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Ombre portée
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(rgb(0x15122E)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    // Fond : dégradé nuit
    let bg = CGGradient(colorsSpace: space, colors: [rgb(0x2A1B5C), rgb(0x120F2A)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Lueur derrière le cadran
    let glow = CGGradient(colorsSpace: space, colors: [rgb(0x8B6CFF, 0.45), rgb(0x8B6CFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 440), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 440), endRadius: 420, options: [])
    // Reflet en haut
    let sheen = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])

    let c = CGPoint(x: 512, y: 440), R: CGFloat = 238, W: CGFloat = 62

    // Piste de l'anneau
    ctx.setLineWidth(W); ctx.setStrokeColor(rgb(0xFFFFFF, 0.09))
    ctx.addArc(center: c, radius: R, startAngle: 0, endAngle: .pi * 2, clockwise: false); ctx.strokePath()

    // Graduations
    for i in 0..<12 {
        let a = CGFloat(i) / 12 * .pi * 2
        let r1: CGFloat = R - W / 2 - 26, r2: CGFloat = r1 - (i % 3 == 0 ? 34 : 18)
        ctx.setLineWidth(i % 3 == 0 ? 10 : 7); ctx.setLineCap(.round)
        ctx.setStrokeColor(rgb(0xFFFFFF, i % 3 == 0 ? 0.42 : 0.2))
        ctx.move(to: CGPoint(x: c.x + sin(a) * r1, y: c.y + cos(a) * r1))
        ctx.addLine(to: CGPoint(x: c.x + sin(a) * r2, y: c.y + cos(a) * r2)); ctx.strokePath()
    }

    // Arc de progression (de midi, sens horaire, 3/4 de tour) en dégradé conique
    let start = CGFloat.pi / 2, sweep = CGFloat.pi * 2 * 0.72
    ctx.saveGState()
    ctx.setLineWidth(W); ctx.setLineCap(.round)
    ctx.addArc(center: c, radius: R, startAngle: start, endAngle: start - sweep, clockwise: true)
    ctx.replacePathWithStrokedPath(); ctx.clip()
    let stops: [UInt32] = [0x3EE6C8, 0x5AA8FF, 0x8B6CFF, 0xFF4FB3]
    let steps = 240
    for k in 0..<steps {
        let t0 = CGFloat(k) / CGFloat(steps), t1 = CGFloat(k + 1) / CGFloat(steps)
        let seg = t0 * CGFloat(stops.count - 1), i = min(Int(seg), stops.count - 2), f = seg - CGFloat(i)
        let a = stops[i], b = stops[i + 1]
        func ch(_ x: UInt32, _ s: UInt32) -> CGFloat { CGFloat((x >> s) & 255) / 255 }
        let col = CGColor(srgbRed: ch(a,16) + (ch(b,16) - ch(a,16)) * f, green: ch(a,8) + (ch(b,8) - ch(a,8)) * f,
                          blue: ch(a,0) + (ch(b,0) - ch(a,0)) * f, alpha: 1)
        let a0 = start + 0.25 - (sweep + 0.5) * t0, a1 = start + 0.25 - (sweep + 0.5) * t1
        ctx.move(to: c)
        ctx.addArc(center: c, radius: R + W, startAngle: a0, endAngle: a1 - 0.01, clockwise: true)
        ctx.closePath(); ctx.setFillColor(col); ctx.fillPath()
    }
    ctx.restoreGState()

    // Fil tiré depuis le haut (la barre des menus) jusqu'au centre
    let top = CGPoint(x: 512, y: 924)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 22, color: rgb(0x3EE6C8, 0.8))
    ctx.setLineWidth(16); ctx.setLineCap(.round)
    ctx.move(to: top); ctx.addLine(to: c)
    ctx.replacePathWithStrokedPath(); ctx.clip()
    let rope = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.15), rgb(0xBFFFF3)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(rope, start: top, end: c, options: [])
    ctx.restoreGState()

    // Bouton tiré, au centre
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 30, color: rgb(0x3EE6C8, 0.9))
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: c.x - 46, y: c.y - 46, width: 92, height: 92))
    ctx.restoreGState()
    ctx.setFillColor(rgb(0x3EE6C8))
    ctx.fillEllipse(in: CGRect(x: c.x - 22, y: c.y - 22, width: 44, height: 44))

    ctx.restoreGState()
    // Liseré fin
    ctx.addPath(shape); ctx.setLineWidth(3); ctx.setStrokeColor(rgb(0xFFFFFF, 0.12)); ctx.strokePath()
    return ctx.makeImage()!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let set = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
let master = render()
for (pt, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let px = pt * scale
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent(name))
}
try! NSBitmapImageRep(cgImage: master).representation(using: .png, properties: [:])!
    .write(to: out.appendingPathComponent("AppIcon-1024.png"))
print("ok")
