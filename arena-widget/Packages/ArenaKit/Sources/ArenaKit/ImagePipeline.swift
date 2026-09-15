import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downloads block thumbnails and shrinks them to the size they'll be drawn at.
/// Full-size decoded images would blow through the widget extension's memory
/// ceiling, so nothing larger than a tile ever leaves this type.
public struct ImagePipeline: Sendable {
    public var session: URLSession

    public init(session: URLSession = .arena) {
        self.session = session
    }

    /// Returns encoded image data for a tile `pixelSize` pixels in size.
    public func thumbnail(from url: URL, pixelSize: CGSize) async throws -> Data? {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        return Self.thumbnail(from: data, filling: pixelSize)
    }

    /// Downsamples with `CGImageSourceCreateThumbnailAtIndex` just enough to
    /// aspect-fill `size`, center-crops to that aspect ratio, and re-encodes
    /// (JPEG, or PNG when the image has alpha). Small sources aren't upscaled.
    public static func thumbnail(from data: Data, filling size: CGSize) -> Data? {
        guard size.width >= 1, size.height >= 1 else { return nil }
        return autoreleasepool {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

            // ThumbnailMaxPixelSize bounds the long edge, so size that edge such
            // that the other one still covers the tile.
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let width = Double(properties?[kCGImagePropertyPixelWidth] as? Int ?? Int(size.width))
            let height = Double(properties?[kCGImagePropertyPixelHeight] as? Int ?? Int(size.height))
            let fillScale = min(1, max(size.width / max(width, 1), size.height / max(height, 1)))
            let maxPixelSize = min(
                (max(width, height) * fillScale).rounded(.up),
                max(size.width, size.height) * 4
            )

            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
            ] as CFDictionary
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }

            let thumbnailWidth = CGFloat(thumbnail.width)
            let thumbnailHeight = CGFloat(thumbnail.height)
            let aspect = size.width / size.height
            let cropSize = thumbnailWidth / thumbnailHeight > aspect
                ? CGSize(width: (thumbnailHeight * aspect).rounded(), height: thumbnailHeight)
                : CGSize(width: thumbnailWidth, height: (thumbnailWidth / aspect).rounded())
            let crop = CGRect(
                x: ((thumbnailWidth - cropSize.width) / 2).rounded(.down),
                y: ((thumbnailHeight - cropSize.height) / 2).rounded(.down),
                width: cropSize.width,
                height: cropSize.height
            )
            let cropped = thumbnail.cropping(to: crop) ?? thumbnail

            let opaque: [CGImageAlphaInfo] = [.none, .noneSkipFirst, .noneSkipLast]
            let type: UTType = opaque.contains(cropped.alphaInfo) ? .jpeg : .png
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
                return nil
            }
            CGImageDestinationAddImage(destination, cropped, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return output as Data
        }
    }
}
