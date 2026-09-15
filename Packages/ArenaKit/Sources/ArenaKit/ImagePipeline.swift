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

    /// Returns encoded image data for a square tile `pixelSize` pixels on a side.
    public func thumbnail(from url: URL, pixelSize: Int) async throws -> Data? {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        return Self.squareThumbnail(from: data, side: pixelSize)
    }

    /// Downsamples with `CGImageSourceCreateThumbnailAtIndex` so the short edge
    /// lands at `side`, center-crops to a square, and re-encodes (JPEG, or PNG
    /// when the image has alpha).
    public static func squareThumbnail(from data: Data, side: Int) -> Data? {
        autoreleasepool {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

            // ThumbnailMaxPixelSize bounds the long edge; scale it up by the aspect
            // ratio so the short edge still covers the tile after cropping.
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? side
            let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? side
            let shortEdge = max(1, min(width, height))
            let longEdge = max(width, height)
            let maxPixelSize = min(Int((Double(side) * Double(longEdge) / Double(shortEdge)).rounded(.up)), side * 4)

            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }

            let edge = min(thumbnail.width, thumbnail.height)
            let crop = CGRect(
                x: (thumbnail.width - edge) / 2,
                y: (thumbnail.height - edge) / 2,
                width: edge,
                height: edge
            )
            let square = thumbnail.cropping(to: crop) ?? thumbnail

            let opaque: [CGImageAlphaInfo] = [.none, .noneSkipFirst, .noneSkipLast]
            let type: UTType = opaque.contains(square.alphaInfo) ? .jpeg : .png
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
                return nil
            }
            CGImageDestinationAddImage(destination, square, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return output as Data
        }
    }
}
