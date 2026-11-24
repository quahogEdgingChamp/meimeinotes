import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

@MainActor
final class CatArtwork: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var hasCustomImage: Bool
    @Published private(set) var isPreparing = false
    @Published var errorMessage: String?

    private let starter: NSImage?
    private let customURL: URL

    init(directory: URL = .applicationSupportDirectory.appending(path: "Meimei Notes")) {
        let url = directory.appending(path: "Cat.png")
        let custom = NSImage(contentsOf: url)
        let starter = Bundle.main.url(forResource: "StarterCat", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
        self.customURL = url
        self.starter = starter
        self.image = custom ?? starter
        self.hasCustomImage = custom != nil
    }

    func importImage(at url: URL, removeBackground: Bool) {
        guard !isPreparing else { return }
        isPreparing = true
        errorMessage = nil

        Task {
            defer { isPreparing = false }
            do {
                let artwork = try await Task.detached(priority: .userInitiated) {
                    try CatImageProcessor.makePNG(from: url, removeBackground: removeBackground)
                }.value
                guard let newImage = NSImage(data: artwork) else { throw CatImageError.unreadable }
                try FileManager.default.createDirectory(at: customURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try artwork.write(to: customURL, options: .atomic)
                image = newImage
                hasCustomImage = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func restoreStarter() {
        guard hasCustomImage, !isPreparing else { return }
        do {
            try FileManager.default.removeItem(at: customURL)
            image = starter
            hasCustomImage = false
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

enum CatImageProcessor {
    static func makePNG(from url: URL, removeBackground: Bool) throws -> Data {
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

        let artwork: CGImage
        if let bounds = transparentBounds(of: original) {
            guard !bounds.isNull, let cropped = original.cropping(to: bounds) else { throw CatImageError.empty }
            artwork = cropped
        } else if removeBackground {
            artwork = try foreground(of: original)
        } else {
            artwork = original
        }

        let image = try resized(artwork)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CatImageError.couldNotSave
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CatImageError.couldNotSave }
        return data as Data
    }

    private static func resized(_ image: CGImage) throws -> CGImage {
        let longestSide = max(image.width, image.height)
        guard longestSide > 512 else { return image }

        let scale = 512.0 / Double(longestSide)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CatImageError.couldNotSave
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else { throw CatImageError.couldNotSave }
        return resized
    }

    private static func foreground(of image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try perform(request, with: handler)
            guard let result = request.results?.first, !result.allInstances.isEmpty else {
                throw CatImageError.missingSubject
            }
            let buffer = try result.generateMaskedImage(ofInstances: result.allInstances,
                                                        from: handler, croppedToInstancesExtent: true)
            let cutout = CIImage(cvPixelBuffer: buffer)
            let context = CIContext(options: [.useSoftwareRenderer: true])
            guard let foreground = context.createCGImage(cutout, from: cutout.extent) else {
                throw CatImageError.missingSubject
            }
            return foreground
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

    private static func transparentBounds(of image: CGImage) -> CGRect? {
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
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        var hasTransparency = false
        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[y * bytesPerRow + x * 4 + 3]
                if alpha < 245 { hasTransparency = true }
                if alpha > 8 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard hasTransparency else { return nil }
        guard minX <= maxX, minY <= maxY else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
