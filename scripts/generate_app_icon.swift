// アプリアイコン(1024x1024 PNG)を生成するスクリプト。
// 実行: swift scripts/generate_app_icon.swift <出力パス>
// App Store 要件のためアルファチャンネルなしで出力する。

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("CGContext の作成に失敗")
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// 背景: インディゴ→ブルーの対角グラデーション
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [color(0x6366F1), color(0x2456D6)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: CGFloat(size)),
    end: CGPoint(x: CGFloat(size), y: 0),
    options: []
)

// 書類カード(白・角丸・影付き)
let docRect = CGRect(x: (1024 - 560) / 2, y: (1024 - 656) / 2, width: 560, height: 656)
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -14),
    blur: 56,
    color: color(0x0B1B4D, alpha: 0.35)
)
ctx.addPath(CGPath(roundedRect: docRect, cornerWidth: 52, cornerHeight: 52, transform: nil))
ctx.setFillColor(color(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

// 本文の行(グレーの角丸バー)。CGContext は原点が左下なので上から順に y を下げていく
let padX: CGFloat = 76
let lineHeight: CGFloat = 34
let lineGap: CGFloat = 34
let lineWidths: [CGFloat] = [408, 408, 328, 408, 368, 408, 216]
let lineColor = color(0xC5CCDA)

var lineY = docRect.maxY - 88 - lineHeight
for width in lineWidths {
    let rect = CGRect(x: docRect.minX + padX, y: lineY, width: width, height: lineHeight)
    ctx.addPath(CGPath(
        roundedRect: rect,
        cornerWidth: lineHeight / 2,
        cornerHeight: lineHeight / 2,
        transform: nil
    ))
    ctx.setFillColor(lineColor)
    ctx.fillPath()
    lineY -= lineHeight + lineGap
}

// 最終行の直後に入力カーソル(アクセントブルーの縦棒)
let lastLineY = docRect.maxY - 88 - lineHeight - CGFloat(lineWidths.count - 1) * (lineHeight + lineGap)
let cursorRect = CGRect(
    x: docRect.minX + padX + lineWidths[lineWidths.count - 1] + 28,
    y: lastLineY - 18,
    width: 16,
    height: lineHeight + 36
)
ctx.addPath(CGPath(roundedRect: cursorRect, cornerWidth: 8, cornerHeight: 8, transform: nil))
ctx.setFillColor(color(0x3B82F6))
ctx.fillPath()

// PNG として書き出し
guard let image = ctx.makeImage() else {
    fatalError("画像の生成に失敗")
}
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.png"
let url = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fatalError("出力先の作成に失敗: \(outputPath)")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("PNG の書き出しに失敗")
}
print("生成完了: \(outputPath)")
