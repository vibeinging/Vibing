//
//  GlyphCache.swift
//  VibeTerminal
//
//  字形纹理缓存 - 使用 Atlas 纹理存储所有字符
//

import Foundation
import Metal
import CoreGraphics
import CoreText
import UIKit

class GlyphCache {

    private let device: MTLDevice
    private(set) var texture: MTLTexture

    // 纹理配置
    private let atlasSize: Int = 2048  // 2048x2048 纹理
    private let glyphSize: CGFloat = 64   // 每个字符 64x64 像素
    private var glyphsPerRow: Int {
        Int(atlasSize / Int(glyphSize))
    }

    // UV 坐标缓存
    private var uvCache: [Character: SIMD4<Float>] = [:]
    private let cacheLock = NSLock()

    // 字体
    private var font: CTFont
    private var fontAttributes: [NSAttributedString.Key: Any]

    // 下一个可用的位置
    private var nextX: Int = 0
    private var nextY: Int = 0

    // 预渲染的字符范围
    private let asciiRange: ClosedRange<UInt32> = 32...126

    init?(device: MTLDevice) {
        self.device = device

        // 创建字体
        let fontSize: CGFloat = 48
        guard let menloFont = UIFont(name: "Menlo", size: fontSize) ??
                              UIFont(name: "Courier", size: fontSize) ??
                              UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular) else {
            return nil
        }

        self.font = CTFontCreateWithName(menlo.fontName as CFString, fontSize, nil)
        self.fontAttributes = [
            .font: menloFont,
            .foregroundColor: UIColor.white
        ]

        // 创建纹理集
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: atlasSize,
            height: atlasSize,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .renderTarget]
        textureDescriptor.storageMode = .shared

        guard let tex = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }
        self.texture = tex

        // 初始化并预渲染常用字符
        renderInitialGlyphs()
    }

    private func renderInitialGlyphs() {
        // ASCII 可打印字符
        for c: UInt32 in asciiRange {
            if let scalar = UnicodeScalar(c) {
                cacheCharacter(Character(scalar))
            }
        }

        // 额外的常用 Unicode 字符
        let commonUnicode: [Character] = [
            // 拉丁扩展
            "à", "á", "â", "ã", "ä", "å", "æ", "ç", "è", "é", "ê", "ë",
            "ì", "í", "î", "ï", "ð", "ñ", "ò", "ó", "ô", "õ", "ö", "ø",
            "ù", "ú", "û", "ü", "ý", "þ", "ÿ",
            // 符号
            "¡", "¢", "£", "¤", "¥", "¦", "§", "¨", "©", "ª", "«", "¬",
            "®", "¯", "°", "±", "²", "³", "´", "µ", "¶", "·", "¸", "¹",
            "º", "»", "¼", "½", "¾", "¿",
            // 箭头和其他符号
            "←", "↑", "→", "↓", "↔", "↕", "↖", "↗", "↘", "↙",
            "─", "│", "┌", "┐", "└", "┘", "├", "┤", "┬", "┴", "┼",
            "■", "□", "▪", "▫", "▬", "▲", "△", "▴", "▸", "▾", "▿",
            "◆", "◇", "○", "●", "◘", "◙",
            // 货币符号
            "€", "₩", "¥", "£", "¢",
            // 数学符号
            "×", "÷", "±", "∓", "√", "∞", "≈", "≠", "≤", "≥",
            // 引号
            """, """, """, """, "'", "'",
            // 破折号
            "–", "—",
            // 其他
            "…", "•", "°", "©", "®", "™", "§", "¶",
            // 方块绘制字符（用于终端 UI）
            "░", "▒", "▓", "█",
        ]

        for char in commonUnicode {
            cacheCharacter(char)
        }
    }

    private func cacheCharacter(_ char: Character) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        // 已经缓存过了
        if uvCache[char] != nil {
            return
        }

        // 检查是否有空间
        if nextY >= atlasSize {
            print("Glyph cache full - cannot cache character: \(char)")
            return
        }

        // 渲染字形
        renderGlyphToTexture(char, at: nextX, y: nextY)

        // 计算 UV 坐标
        let u = Float(nextX) / Float(atlasSize)
        let v = Float(nextY) / Float(atlasSize)
        let w = Float(glyphSize) / Float(atlasSize)
        let h = Float(glyphSize) / Float(atlasSize)

        uvCache[char] = SIMD4(u, v, w, h)

        // 移动到下一个位置
        nextX += Int(glyphSize)
        if nextX + Int(glyphSize) > atlasSize {
            nextX = 0
            nextY += Int(glyphSize)
        }
    }

    private func renderGlyphToTexture(_ char: Character, at x: Int, y: Int) {
        // 创建字形位图
        let size = CGSize(width: glyphSize, height: glyphSize)
        let bitsPerComponent = 8
        let bytesPerRow = Int(glyphSize.width) * 4

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: Int(glyphSize.width),
            height: Int(glyphSize.height),
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return
        }

        // 清空背景（透明黑色）
        context.clear(CGRect(origin: .zero, size: size))

        // 设置字体和颜色
        let attrString = NSAttributedString(string: String(char), attributes: fontAttributes)

        // 计算居中位置
        let bounds = attrString.boundingRect(with: size, options: .usesLineFragmentOrigin, context: nil)

        var textOrigin = CGPoint(
            x: (size.width - bounds.width) / 2 - bounds.origin.x,
            y: (size.height - bounds.height) / 2
        )

        // Core Graphics 坐标系是翻转的
        textOrigin.y = size.height - bounds.height - textOrigin.y

        // 绘制文字
        CTLineDraw(CTLineCreateWithAttributedString(attrString), context)

        // 获取图像数据
        guard let cgImage = context.makeImage() else {
            return
        }

        // 上传到纹理
        let textureLoader = MTKTextureLoader(device: device)
        do {
            try textureLoader.setCGImage(
                cgImage,
                to: texture,
                region: MTLRegionMake2D(x, y, Int(glyphSize.width), Int(glyphSize.height)),
                level: 0,
                slice: 0,
                textureLoaderOptions: [
                    .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                    .textureStorageMode: NSNumber(value: MTLStorageMode.shared.rawValue)
                ]
            )
        } catch {
            print("Failed to upload glyph texture for '\(char)': \(error)")
        }
    }

    func getUVRect(for char: Character) -> SIMD4<Float> {
        // 首先尝试从缓存获取
        if let uv = uvCache[char] {
            return uv
        }

        // 动态添加新字符
        cacheCharacter(char)

        // 再次尝试获取
        return uvCache[char] ?? SIMD4(0, 0, 0, 0)
    }

    // 获取字体度量信息
    func getFontMetrics() -> (ascent: CGFloat, descent: CGFloat, leading: CGFloat) {
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        return (ascent, descent, leading)
    }

    // 获取字符的宽度（比例）
    func getCharWidth(for char: Character) -> CGFloat {
        let unichars = [UniChar](char.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: 1)

        if CTFontGetGlyphsForCharacters(font, unichars, &glyphs, 1) {
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advance, 1)
            return advance.width
        }

        return glyphSize  // 默认宽度
    }

    // 预加载指定范围的 Unicode 字符
    func preloadUnicodeRange(_ range: ClosedRange<UInt32>) {
        for c in range {
            if let scalar = UnicodeScalar(c) {
                cacheCharacter(Character(scalar))
            }
        }
    }
}
