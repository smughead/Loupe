#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Configuration

let windowWidth: CGFloat = 660
let windowHeight: CGFloat = 400

let loupeIconCenter = CGPoint(x: 180, y: 180)
let appsIconCenter = CGPoint(x: 480, y: 180)
let iconRadius: CGFloat = 64

// Background color (dark gray)
let bgRed: CGFloat = 40 / 255.0
let bgGreen: CGFloat = 38 / 255.0
let bgBlue: CGFloat = 38 / 255.0

// Arrow style
let arrowColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.55)
let arrowStrokeWidth: CGFloat = 3.0

// Arrow geometry — gap from icon edges
let iconGap: CGFloat = 20
let arrowStartX = loupeIconCenter.x + iconRadius + iconGap   // 264
let arrowEndX = appsIconCenter.x - iconRadius - iconGap       // 396
let arrowY = loupeIconCenter.y                                 // 180
let arcPeak: CGFloat = 55  // How high above the icon center line the arc goes

// Arrowhead
let arrowheadLength: CGFloat = 14
let arrowheadHalfWidth: CGFloat = 7

// MARK: - Drawing

func generateBackground(scale: CGFloat, outputPath: String) {
    let pixelWidth = Int(windowWidth * scale)
    let pixelHeight = Int(windowHeight * scale)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixelWidth,
        height: pixelHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("Failed to create CGContext for \(outputPath)")
        return
    }

    // Scale all drawing by the scale factor
    ctx.scaleBy(x: scale, y: scale)

    // CoreGraphics has origin at bottom-left, but DMG Finder coordinates have origin at top-left.
    // Flip the coordinate system so our y-coordinates match the plan (top-left origin).
    ctx.translateBy(x: 0, y: windowHeight)
    ctx.scaleBy(x: 1, y: -1)

    // --- Background fill ---
    ctx.setFillColor(CGColor(red: bgRed, green: bgGreen, blue: bgBlue, alpha: 1.0))
    ctx.fill(CGRect(x: 0, y: 0, width: windowWidth, height: windowHeight))

    // --- Draw curved arrow ---
    // In our flipped coordinate system, y increases downward.
    // Arc peak should be ABOVE the icon center, so y is smaller.
    let startPoint = CGPoint(x: arrowStartX, y: arrowY)
    let endPoint = CGPoint(x: arrowEndX, y: arrowY)
    let peakY = arrowY - arcPeak  // above center line

    // Control points for a smooth upward arc (cubic bezier)
    let cp1 = CGPoint(x: arrowStartX + 30, y: peakY)
    let cp2 = CGPoint(x: arrowEndX - 30, y: peakY)

    // Draw the curve
    ctx.setStrokeColor(arrowColor)
    ctx.setLineWidth(arrowStrokeWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    ctx.beginPath()
    ctx.move(to: startPoint)
    ctx.addCurve(to: endPoint, control1: cp1, control2: cp2)
    ctx.strokePath()

    // --- Arrowhead at the end, aligned to curve tangent ---
    // Tangent at t=1 for cubic bezier: derivative = 3*(P3 - CP2)
    let tangentX = endPoint.x - cp2.x
    let tangentY = endPoint.y - cp2.y
    let tangentLen = sqrt(tangentX * tangentX + tangentY * tangentY)
    let unitTX = tangentX / tangentLen
    let unitTY = tangentY / tangentLen

    // Perpendicular to tangent
    let perpX = -unitTY
    let perpY = unitTX

    // Arrowhead tip is at endPoint; base is arrowheadLength back along tangent
    let baseCenter = CGPoint(
        x: endPoint.x - unitTX * arrowheadLength,
        y: endPoint.y - unitTY * arrowheadLength
    )
    let wingA = CGPoint(
        x: baseCenter.x + perpX * arrowheadHalfWidth,
        y: baseCenter.y + perpY * arrowheadHalfWidth
    )
    let wingB = CGPoint(
        x: baseCenter.x - perpX * arrowheadHalfWidth,
        y: baseCenter.y - perpY * arrowheadHalfWidth
    )

    ctx.setFillColor(arrowColor)
    ctx.beginPath()
    ctx.move(to: endPoint)
    ctx.addLine(to: wingA)
    ctx.addLine(to: wingB)
    ctx.closePath()
    ctx.fillPath()

    // --- Export as PNG ---
    guard let image = ctx.makeImage() else {
        print("Failed to create image for \(outputPath)")
        return
    }

    let url = URL(fileURLWithPath: outputPath)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        print("Failed to create image destination for \(outputPath)")
        return
    }

    // Set DPI metadata: 72 * scale
    let dpi = 72.0 * Double(scale)
    let properties: [CFString: Any] = [
        kCGImagePropertyDPIWidth: dpi,
        kCGImagePropertyDPIHeight: dpi
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)

    if CGImageDestinationFinalize(destination) {
        print("Generated: \(outputPath) (\(pixelWidth)×\(pixelHeight) @ \(Int(dpi)) DPI)")
    } else {
        print("Failed to write: \(outputPath)")
    }
}

// MARK: - Main

let desktopPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Desktop").path

generateBackground(scale: 1, outputPath: "\(desktopPath)/dmg_background_1x.png")
generateBackground(scale: 2, outputPath: "\(desktopPath)/dmg_background_2x.png")

print("Done! Background images saved to ~/Desktop/")
