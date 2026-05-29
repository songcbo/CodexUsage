import AppKit
import Foundation

struct PetManifest: Decodable {
    var id: String
    var displayName: String
    var spritesheetPath: String
}

@MainActor
final class PetSpritesheet {
    static let columns = 8
    static let rows = 9
    static let cellWidth = 192
    static let cellHeight = 208

    let isFallback: Bool
    let missingMessage: String?

    private let cgImage: CGImage?
    private var frameCache: [Int: NSImage] = [:]
    private lazy var fallbackImage: NSImage = Self.makeFallbackImage()

    private init(cgImage: CGImage?, isFallback: Bool, missingMessage: String?) {
        self.cgImage = cgImage
        self.isFallback = isFallback
        self.missingMessage = missingMessage
    }

    static func load(codexPath: String) -> PetSpritesheet {
        let petDirectory = URL(fileURLWithPath: codexPath)
            .appendingPathComponent("pets", isDirectory: true)
            .appendingPathComponent("lovely", isDirectory: true)
        let manifestURL = petDirectory.appendingPathComponent("pet.json")

        do {
            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(PetManifest.self, from: manifestData)
            let spritesheetURL = petDirectory.appendingPathComponent(manifest.spritesheetPath)

            guard let image = NSImage(contentsOf: spritesheetURL) else {
                return fallback("spritesheet.webp could not be loaded")
            }

            var imageRect = NSRect(origin: .zero, size: image.size)
            guard let cgImage = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil) else {
                return fallback("spritesheet.webp could not be decoded")
            }

            let expectedWidth = columns * cellWidth
            let expectedHeight = rows * cellHeight
            guard cgImage.width == expectedWidth, cgImage.height == expectedHeight else {
                return fallback("spritesheet.webp size is \(cgImage.width)x\(cgImage.height)")
            }

            return PetSpritesheet(cgImage: cgImage, isFallback: false, missingMessage: nil)
        } catch {
            return fallback(error.localizedDescription)
        }
    }

    func frame(row: Int, column: Int) -> NSImage {
        guard let cgImage else { return fallbackImage }

        let safeRow = min(max(row, 0), Self.rows - 1)
        let safeColumn = min(max(column, 0), Self.columns - 1)
        let cacheKey = safeRow * Self.columns + safeColumn
        if let cached = frameCache[cacheKey] {
            return cached
        }

        let cropRect = CGRect(
            x: safeColumn * Self.cellWidth,
            y: safeRow * Self.cellHeight,
            width: Self.cellWidth,
            height: Self.cellHeight
        )
        guard let cropped = cgImage.cropping(to: cropRect) else {
            return fallbackImage
        }

        let image = NSImage(
            cgImage: cropped,
            size: NSSize(width: Self.cellWidth, height: Self.cellHeight)
        )
        frameCache[cacheKey] = image
        return image
    }

    private static func fallback(_ detail: String) -> PetSpritesheet {
        PetSpritesheet(cgImage: nil, isFallback: true, missingMessage: detail)
    }

    private static func makeFallbackImage() -> NSImage {
        let size = NSSize(width: cellWidth, height: cellHeight)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 28, yRadius: 28).fill()

        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(ovalIn: NSRect(x: 38, y: 48, width: 116, height: 116)).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        ("lovely" as NSString).draw(
            in: NSRect(x: 0, y: 88, width: size.width, height: 36),
            withAttributes: attributes
        )

        image.unlockFocus()
        return image
    }
}
