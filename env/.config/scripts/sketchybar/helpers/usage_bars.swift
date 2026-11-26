import AppKit

guard CommandLine.arguments.count == 7 || CommandLine.arguments.count == 8 else { exit(1) }

let output = CommandLine.arguments[1]
let five = max(-1, min(100, Int(CommandLine.arguments[2]) ?? -1))
let week = max(-1, min(100, Int(CommandLine.arguments[3]) ?? -1))
let mode = CommandLine.arguments.count == 8 ? CommandLine.arguments[7] : "dual"

func color(_ value: String) -> NSColor {
    let hex = String(value.suffix(6))
    let number = UInt64(hex, radix: 16) ?? 0
    return NSColor(
        red: CGFloat((number >> 16) & 0xff) / 255,
        green: CGFloat((number >> 8) & 0xff) / 255,
        blue: CGFloat(number & 0xff) / 255,
        alpha: 1
    )
}

let fiveColor = color(CommandLine.arguments[4])
let weekColor = color(CommandLine.arguments[5])
let trackColor = color(CommandLine.arguments[6])
let barWidth: CGFloat = mode == "progress" ? 140 : 52 // 今日进度 70pt，用量条 26pt。
let barHeight: CGFloat = 8 // 以 2x 生成，栏中显示为 4pt。
let gap: CGFloat = 8
let width = Int(mode == "dual" ? barWidth * 2 + gap : barWidth)
let height = Int(barHeight)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { exit(1) }

bitmap.size = NSSize(width: width, height: height)
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

func drawBar(x: CGFloat, percentage: Int, fillColor: NSColor) {
    let rect = NSRect(x: x, y: 0, width: barWidth, height: barHeight)
    let track = NSBezierPath(roundedRect: rect, xRadius: barHeight / 2, yRadius: barHeight / 2)
    trackColor.setFill()
    track.fill()

    guard percentage >= 0 else { return }
    let fillWidth = barWidth * CGFloat(percentage) / 100
    guard fillWidth > 0 else { return }
    NSGraphicsContext.saveGraphicsState()
    track.addClip()
    fillColor.setFill()
    NSRect(x: x, y: 0, width: fillWidth, height: barHeight).fill()
    NSGraphicsContext.restoreGraphicsState()
}

if mode == "week" || mode == "progress" {
    drawBar(x: 0, percentage: week, fillColor: weekColor)
} else {
    drawBar(x: 0, percentage: five, fillColor: fiveColor)
    drawBar(x: barWidth + gap, percentage: week, fillColor: weekColor)
}

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: output))
