import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

struct CatPortrait {
    let image: NSImage
    let isFramed: Bool
}

private struct SavedCatArtwork: Codable, Sendable {
    let source: Data
    let hasTransparentBackground: Bool
    var cutout: Data?
    var showsCutout = false

    var portrait: CatPortrait? {
        let displayedCutout = showsCutout ? cutout : nil
        let data = displayedCutout ?? source
        guard let image = NSImage(data: data) else { return nil }
        let isCutout = hasTransparentBackground || displayedCutout != nil
        return CatPortrait(image: image, isFramed: !isCutout || CatImageProcessor.hasClippedEdge(data))
    }
}

@MainActor
final class CatArtwork: ObservableObject {
    @Published private(set) var portrait: CatPortrait?
    @Published private(set) var isPreparing = false
    @Published var errorMessage: String?

    private let starter: CatPortrait?
    private let customURL: URL
    private let legacyURL: URL
    private var custom: SavedCatArtwork?

    var hasCustomImage: Bool { custom != nil }
    var canRemoveBackground: Bool { custom?.hasTransparentBackground == false }
    var removesBackground: Bool { custom?.showsCutout == true }

    init(directory: URL = .applicationSupportDirectory.appending(path: "Meimei Notes")) {
        customURL = directory.appending(path: "CatArtwork.plist")
        legacyURL = directory.appending(path: "Cat.png")
        starter = Bundle.main.url(forResource: "StarterCat", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
            .map { CatPortrait(image: $0, isFramed: false) }

        let saved = (try? Data(contentsOf: customURL)).flatMap {
            try? PropertyListDecoder().decode(SavedCatArtwork.self, from: $0)
        }
        if let saved, let portrait = saved.portrait {
            custom = saved
            self.portrait = portrait
        } else if let legacy = CatImageProcessor.loadLegacy(from: legacyURL), let portrait = legacy.portrait {
            custom = legacy
            self.portrait = portrait
        } else {
            portrait = starter
        }
    }

    func importImage(at url: URL) {
        prepare { try CatImageProcessor.prepareImport(at: url) }
    }

    func setRemovesBackground(_ remove: Bool) {
        guard let custom, canRemoveBackground, removesBackground != remove else { return }
        prepare {
            var updated = custom
            if remove, updated.cutout == nil {
                updated.cutout = try CatImageProcessor.makeCutout(from: updated.source)
            }
            updated.showsCutout = remove
            return updated
        }
    }

    private func prepare(_ operation: @escaping @Sendable () throws -> SavedCatArtwork) {
        guard !isPreparing else { return }
        isPreparing = true
        errorMessage = nil

        Task {
            defer { isPreparing = false }
            do {
                let artwork = try await Task.detached(priority: .userInitiated, operation: operation).value
                guard let portrait = artwork.portrait else { throw CatImageError.unreadable }
                try FileManager.default.createDirectory(at: customURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                try encoder.encode(artwork).write(to: customURL, options: .atomic)
                custom = artwork
                self.portrait = portrait
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func restoreStarter() {
        guard hasCustomImage, !isPreparing else { return }
        do {
            for url in [legacyURL, customURL] where FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            custom = nil
            portrait = starter
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum CatImageError: LocalizedError {
    case unreadable, empty, missingSubject, couldNotSave

    var errorDescription: String? {
        switch self {
        case .unreadable: "Choose a readable image such as a PNG, JPEG, or HEIC."
        case .empty: "The image is fully transparent. Choose an image with a visible cat."
        case .missingSubject: "A cutout couldn’t be made. Try a photo with one clearly visible cat or choose a transparent PNG."
        case .couldNotSave: "The processed image couldn’t be saved."
        }
    }
}

private enum CatImageProcessor {
    private struct TransparentContent {
        let bounds: CGRect
        let hasClippedEdge: Bool
    }

    static func loadLegacy(from url: URL) -> SavedCatArtwork? {
        guard let data = try? Data(contentsOf: url), let image = cgImage(from: data) else { return nil }
        let content = transparentContent(of: image)
        guard content?.bounds.isNull != true else { return nil }
        return SavedCatArtwork(source: data, hasTransparentBackground: content != nil)
    }

    static func hasClippedEdge(_ data: Data) -> Bool {
        guard let image = cgImage(from: data) else { return false }
        return transparentContent(of: image)?.hasClippedEdge == true
    }

    static func prepareImport(at url: URL) throws -> SavedCatArtwork {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let original = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CatImageError.unreadable
        }

        if let content = transparentContent(of: original) {
            guard !content.bounds.isNull else { throw CatImageError.empty }
            let cropped = crop(original, to: content.bounds)
            return SavedCatArtwork(source: try png(from: cropped), hasTransparentBackground: true)
        }

        let sourceData = try png(from: original)
        let cutout = try? foregroundPNG(of: original)
        return SavedCatArtwork(source: sourceData, hasTransparentBackground: false,
                               cutout: cutout, showsCutout: cutout != nil)
    }

    static func makeCutout(from data: Data) throws -> Data {
        guard let image = cgImage(from: data) else { throw CatImageError.unreadable }
        return try foregroundPNG(of: image)
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func png(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CatImageError.couldNotSave
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CatImageError.couldNotSave }
        return data as Data
    }

    private static func crop(_ image: CGImage, to bounds: CGRect) -> CGImage {
        let canvas = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        return image.cropping(to: bounds.insetBy(dx: -2, dy: -2).intersection(canvas)) ?? image
    }

    private static func foregroundPNG(of image: CGImage) throws -> Data {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try perform(request, with: handler)
            guard let result = request.results?.first, !result.allInstances.isEmpty else {
                throw CatImageError.missingSubject
            }
            let buffer = try result.generateMaskedImage(ofInstances: result.allInstances,
                                                        from: handler, croppedToInstancesExtent: false)
            let cutout = CIImage(cvPixelBuffer: buffer)
            let context = CIContext(options: [.useSoftwareRenderer: true])
            guard let image = context.createCGImage(cutout, from: cutout.extent),
                  let content = transparentContent(of: image), !content.bounds.isNull else {
                throw CatImageError.missingSubject
            }
            return try png(from: crop(image, to: content.bounds))
        } catch {
            throw CatImageError.missingSubject
        }
    }

    private static func perform(_ request: VNRequest, with handler: VNImageRequestHandler) throws {
        do {
            try handler.perform([request])
        } catch let initialError {
            var canRetry = false
            for (stage, devices) in try request.supportedComputeStageDevices {
                if let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } }) {
                    request.setComputeDevice(cpu, for: stage)
                    canRetry = true
                }
            }
            guard canRetry else { throw initialError }
            try handler.perform([request])
        }
    }

    private static func transparentContent(of image: CGImage) -> TransparentContent? {
        let alphaFormats: [CGImageAlphaInfo] = [.first, .last, .premultipliedFirst, .premultipliedLast]
        guard alphaFormats.contains(image.alphaInfo) else { return nil }

        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        defer { withExtendedLifetime(context) {} }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        var hasTransparentBackground = false
        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[y * bytesPerRow + x * 4 + 3]
                if alpha <= 8 { hasTransparentBackground = true }
                if alpha > 8 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard hasTransparentBackground else { return nil }
        guard minX <= maxX, minY <= maxY else { return TransparentContent(bounds: .null, hasClippedEdge: false) }
        let edgeAlpha: UInt8 = 64
        let left = (0..<height).lazy.filter { pixels[$0 * bytesPerRow + 3] >= edgeAlpha }.count
        let right = (0..<height).lazy.filter { pixels[$0 * bytesPerRow + bytesPerRow - 1] >= edgeAlpha }.count
        let top = (0..<width).lazy.filter { pixels[$0 * 4 + 3] >= edgeAlpha }.count
        let clipped = max(left, right) > height / 10 || top > width / 10
        let bounds = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        return TransparentContent(bounds: bounds, hasClippedEdge: clipped)
    }
}
