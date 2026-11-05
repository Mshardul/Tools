import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let fileManager = FileManager.default
try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

let slots: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (side, name) in slots {
    try writePNG(side: side, to: iconset.appendingPathComponent(name))
}

let strip = Process()
strip.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
strip.arguments = ["-cr", iconset.path]
try strip.run()
strip.waitUntilExit()

let icns = root.appendingPathComponent("AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try task.run()
task.waitUntilExit()
if task.terminationStatus != 0 {
    fputs("iconutil failed\n", stderr)
    exit(1)
}

try fileManager.removeItem(at: iconset)

func writePNG(side: Int, to url: URL) throws {
    let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    draw(side: CGFloat(side), in: context)
    guard let image = context.makeImage() else { exit(1) }
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { exit(1) }
    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) {
        exit(1)
    }
}

func draw(side: CGFloat, in ctx: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: side, height: side)
    ctx.clear(rect)
    let tile = rect.insetBy(dx: side * 0.04, dy: side * 0.04)
    let corner = tile.width * 0.223
    let tilePath = CGPath(roundedRect: tile, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.setFillColor(CGColor(red: 0x0C / 255, green: 0x10 / 255, blue: 0x13 / 255, alpha: 1))
    ctx.addPath(tilePath)
    ctx.fillPath()

    let orb = tile.insetBy(dx: tile.width * 0.18, dy: tile.width * 0.18)
    let center = CGPoint(x: orb.midX, y: orb.midY)
    let orbRadius = orb.width / 2
    let stops: [(CGFloat, (CGFloat, CGFloat, CGFloat))] = [
        (0, (0x5E, 0xF2, 0xC8)),
        (0.33, (0x8B, 0x7B, 0xFF)),
        (0.66, (0xFF, 0x7A, 0x6B)),
        (1, (0x5E, 0xF2, 0xC8))
    ]
    guard let pixels = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return }
    let width = Int(side)
    for y in 0 ..< width {
        for x in 0 ..< width {
            let dx = CGFloat(x) + 0.5 - center.x
            let dy = CGFloat(y) + 0.5 - center.y
            if hypot(dx, dy) > orbRadius {
                continue
            }
            var angle = atan2(dy, dx)
            if angle < 0 {
                angle += 2 * .pi
            }
            let color = mix(stops, at: angle / (2 * .pi))
            let offset = (y * width + x) * 4
            pixels[offset] = UInt8(color.0.rounded())
            pixels[offset + 1] = UInt8(color.1.rounded())
            pixels[offset + 2] = UInt8(color.2.rounded())
            pixels[offset + 3] = 255
        }
    }

    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
    ctx.setLineWidth(max(1, side * 0.012))
    ctx.strokeEllipse(in: orb.insetBy(dx: side * 0.006, dy: side * 0.006))
}

func mix(
    _ stops: [(CGFloat, (CGFloat, CGFloat, CGFloat))],
    at position: CGFloat
) -> (CGFloat, CGFloat, CGFloat) {
    var lower = stops[0]
    var upper = stops[stops.count - 1]
    for index in 0 ..< (stops.count - 1) where position >= stops[index].0 && position <= stops[index + 1].0 {
        lower = stops[index]
        upper = stops[index + 1]
    }
    let span = max(upper.0 - lower.0, 0.0001)
    let amount = min(max((position - lower.0) / span, 0), 1)
    func channel(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
        start + (end - start) * amount
    }
    return (
        channel(lower.1.0, upper.1.0),
        channel(lower.1.1, upper.1.1),
        channel(lower.1.2, upper.1.2)
    )
}
