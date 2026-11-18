// Generate macOS app icons from the unchanged TwistCast branding artwork.
// Run from the repository root: swift tool/macos_icons.swift
// Writes the existing AppIcon asset sizes with transparent Dock padding and rounded corners.
import AppKit

let source = URL(fileURLWithPath: "assets/branding/twistcast-icon.png")
guard let image = NSImage(contentsOf: source),
      let original = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
  fatalError("Could not read branding artwork")
}
let colorSpace = CGColorSpaceCreateDeviceRGB()
let canvasSize = 2048
let inset = CGFloat(canvasSize) * 0.1
let tile = CGRect(x: inset, y: inset, width: CGFloat(canvasSize) - inset * 2,
                  height: CGFloat(canvasSize) - inset * 2)
guard let masterContext = CGContext(data: nil, width: canvasSize, height: canvasSize,
    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Could not create canvas") }
masterContext.interpolationQuality = .high
masterContext.addPath(CGPath(roundedRect: tile, cornerWidth: tile.width * 0.22,
                            cornerHeight: tile.height * 0.22, transform: nil))
masterContext.clip()
masterContext.draw(original, in: tile)
guard let master = masterContext.makeImage() else { fatalError("Could not render icon") }
for size in [16, 32, 64, 128, 256, 512, 1024] {
  guard let context = CGContext(data: nil, width: size, height: size,
      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Could not create icon") }
  context.interpolationQuality = .high
  context.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
  guard let rendered = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon")
  }
  let output = URL(fileURLWithPath: "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_\(size).png")
  try png.write(to: output)
  print(output.path)
}
