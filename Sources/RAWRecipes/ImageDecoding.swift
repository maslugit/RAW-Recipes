import Foundation
import CoreGraphics
import CoreImage
import ImageIO

enum ImageDecoding {
    /// Decodes a JPEG (or any other ImageIO format) and applies the EXIF orientation.
    /// Without `maxPixelSize` the image is decoded at full resolution.
    static func cgImage(from data: Data, maxPixelSize: Int? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return decode(source, maxPixelSize: maxPixelSize)
    }

    static func cgImage(contentsOf url: URL, maxPixelSize: Int? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return decode(source, maxPixelSize: maxPixelSize)
    }

    private static func decode(_ source: CGImageSource, maxPixelSize: Int?) -> CGImage? {
        var size = maxPixelSize
        if size == nil,
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            size = max(w, h)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: size ?? 4096,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Develops a RAF with macOS's own RAW engine (Apple's rendering, not Fujifilm's).
    static func rawImage(at url: URL) -> CGImage? {
        guard let filter = CIRAWFilter(imageURL: url), let output = filter.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(output, from: output.extent)
    }
}
