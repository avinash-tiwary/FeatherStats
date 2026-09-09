import AppKit

let destination = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let outer = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 210, yRadius: 210)
NSColor(calibratedRed: 0.075, green: 0.12, blue: 0.14, alpha: 1).setFill()
outer.fill()

let gauge = NSBezierPath()
gauge.lineWidth = 54
gauge.lineCapStyle = .round
gauge.appendArc(withCenter: NSPoint(x: 512, y: 480), radius: 255, startAngle: 195, endAngle: -15, clockwise: true)
NSColor(calibratedRed: 0.35, green: 0.9, blue: 0.72, alpha: 1).setStroke()
gauge.stroke()

let needle = NSBezierPath()
needle.lineWidth = 38
needle.lineCapStyle = .round
needle.move(to: NSPoint(x: 512, y: 480))
needle.line(to: NSPoint(x: 675, y: 645))
NSColor.white.setStroke()
needle.stroke()

let center = NSBezierPath(ovalIn: NSRect(x: 466, y: 434, width: 92, height: 92))
NSColor.white.setFill()
center.fill()

let feather = NSBezierPath()
feather.move(to: NSPoint(x: 356, y: 258))
feather.curve(to: NSPoint(x: 702, y: 330), controlPoint1: NSPoint(x: 430, y: 368), controlPoint2: NSPoint(x: 630, y: 365))
feather.curve(to: NSPoint(x: 356, y: 258), controlPoint1: NSPoint(x: 562, y: 222), controlPoint2: NSPoint(x: 445, y: 220))
feather.close()
NSColor(calibratedRed: 0.35, green: 0.9, blue: 0.72, alpha: 1).setFill()
feather.fill()

image.unlockFocus()
guard let data = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: data),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon")
}
try png.write(to: URL(fileURLWithPath: destination))
