#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct Palette {
  let backgroundTop: CGColor
  let backgroundBottom: CGColor
  let layers: [CGColor]
  let edge: CGColor
  let signal: CGColor
  let signalRing: CGColor
}

private enum IconGeneratorError: LocalizedError {
  case contextCreationFailed
  case imageCreationFailed
  case destinationCreationFailed(URL)
  case imageWriteFailed(URL)

  var errorDescription: String? {
    switch self {
    case .contextCreationFailed:
      "Der Zeichenkontext konnte nicht erstellt werden."
    case .imageCreationFailed:
      "Das App-Icon konnte nicht gerendert werden."
    case .destinationCreationFailed(let url):
      "Das PNG-Ziel konnte nicht erstellt werden: \(url.path)"
    case .imageWriteFailed(let url):
      "Das PNG konnte nicht geschrieben werden: \(url.path)"
    }
  }
}

private func color(_ red: Int, _ green: Int, _ blue: Int, alpha: CGFloat = 1) -> CGColor {
  CGColor(
    red: CGFloat(red) / 255,
    green: CGFloat(green) / 255,
    blue: CGFloat(blue) / 255,
    alpha: alpha
  )
}

private let defaultPalette = Palette(
  backgroundTop: color(48, 54, 63),
  backgroundBottom: color(25, 29, 35),
  layers: [color(215, 73, 69), color(239, 102, 85), color(255, 139, 113)],
  edge: color(255, 224, 207, alpha: 0.28),
  signal: color(82, 211, 142),
  signalRing: color(235, 250, 241)
)

private let darkPalette = Palette(
  backgroundTop: color(23, 27, 33),
  backgroundBottom: color(8, 11, 15),
  layers: [color(184, 52, 53), color(226, 78, 68), color(255, 116, 94)],
  edge: color(255, 222, 207, alpha: 0.24),
  signal: color(76, 231, 143),
  signalRing: color(18, 27, 23)
)

private let tintedPalette = Palette(
  backgroundTop: color(50, 50, 52),
  backgroundBottom: color(17, 17, 18),
  layers: [color(126, 126, 130), color(178, 178, 183), color(231, 231, 235)],
  edge: color(255, 255, 255, alpha: 0.22),
  signal: color(255, 255, 255),
  signalRing: color(44, 44, 46)
)

private let macIconCornerRadius: CGFloat = 328

private func renderIcon(
  size: Int,
  palette: Palette,
  clipsToMacIconShape: Bool = false
) throws -> CGImage {
  guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  ) else {
    throw IconGeneratorError.contextCreationFailed
  }

  let scale = CGFloat(size) / 1024
  context.scaleBy(x: scale, y: scale)

  if clipsToMacIconShape {
    let iconBounds = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    context.addPath(
      CGPath(
        roundedRect: iconBounds,
        cornerWidth: macIconCornerRadius,
        cornerHeight: macIconCornerRadius,
        transform: nil
      )
    )
    context.clip()
  }

  let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [palette.backgroundBottom, palette.backgroundTop] as CFArray,
    locations: [0, 1]
  )!
  context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 512, y: 0),
    end: CGPoint(x: 512, y: 1024),
    options: []
  )

  let layerRects = [
    CGRect(x: 170, y: 214, width: 684, height: 152),
    CGRect(x: 170, y: 430, width: 684, height: 152),
    CGRect(x: 170, y: 646, width: 684, height: 152),
  ]

  for (index, rect) in layerRects.enumerated() {
    context.saveGState()
    context.setShadow(
      offset: CGSize(width: 0, height: -18),
      blur: 24,
      color: color(0, 0, 0, alpha: 0.28)
    )
    context.setFillColor(palette.layers[index])
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 46, cornerHeight: 46, transform: nil))
    context.fillPath()
    context.restoreGState()

    let highlight = CGRect(x: rect.minX + 45, y: rect.maxY - 29, width: rect.width - 90, height: 7)
    context.setFillColor(palette.edge)
    context.addPath(CGPath(roundedRect: highlight, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil))
    context.fillPath()
  }

  let signalCenter = CGPoint(x: 790, y: 756)
  context.setFillColor(palette.signalRing)
  context.fillEllipse(in: CGRect(x: signalCenter.x - 58, y: signalCenter.y - 58, width: 116, height: 116))
  context.setFillColor(palette.signal)
  context.fillEllipse(in: CGRect(x: signalCenter.x - 39, y: signalCenter.y - 39, width: 78, height: 78))

  guard let image = context.makeImage() else {
    throw IconGeneratorError.imageCreationFailed
  }
  return image
}

private func writePNG(_ image: CGImage, to url: URL) throws {
  guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
  ) else {
    throw IconGeneratorError.destinationCreationFailed(url)
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw IconGeneratorError.imageWriteFailed(url)
  }
}

private func generate() throws {
  let scriptURL = URL(fileURLWithPath: #filePath)
  let repositoryRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
  let outputDirectory = repositoryRoot
    .appendingPathComponent("Varan/Resources/Assets.xcassets/AppIcon.appiconset")
  try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
  )

  let variants: [(String, Palette)] = [
    ("AppIcon-Default-1024.png", defaultPalette),
    ("AppIcon-Dark-1024.png", darkPalette),
    ("AppIcon-Tinted-1024.png", tintedPalette),
  ]
  for (filename, palette) in variants {
    try writePNG(try renderIcon(size: 1024, palette: palette), to: outputDirectory.appendingPathComponent(filename))
  }

  for size in [16, 32, 64, 128, 256, 512, 1024] {
    let filename = "AppIcon-Mac-\(size).png"
    try writePNG(
      try renderIcon(size: size, palette: defaultPalette, clipsToMacIconShape: true),
      to: outputDirectory.appendingPathComponent(filename)
    )
  }

  print("Generated AppIcon assets in \(outputDirectory.path)")
}

do {
  try generate()
} catch {
  fputs("ERROR: \(error.localizedDescription)\n", stderr)
  exit(1)
}
