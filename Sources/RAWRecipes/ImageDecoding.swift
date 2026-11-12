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

    /// The EXIF orientation (1–8) stored in image data, or 1 if there is none.
    /// 6 means "rotate 90° clockwise to display", 8 "rotate 90° counter-clockwise".
    static func orientation(of data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return 1 }
        return (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    }

    /// A smaller copy of an image, with its longest side at most `maxPixelSize`.
    static func downscaled(_ image: CGImage, maxPixelSize: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxPixelSize else { return image }
        let scale = Double(maxPixelSize) / Double(longest)
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Camera thumbnails are always 160×120 (4:3). Photos with another aspect ratio – 3:2,
    /// portrait, 16:9, 1:1 – get black bars baked in by the camera. This crops them off.
    ///
    /// To never crop a genuinely dark photo, the bars must be symmetric and the result must
    /// have a common photo aspect ratio; otherwise the image is returned unchanged.
    static func trimLetterbox(_ image: CGImage) -> CGImage {
        let w = image.width, h = image.height
        guard w > 8, h > 8, w * h <= 1_000_000,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data
        else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        let threshold: UInt8 = 24   // JPEG noise keeps the bars from being exactly 0
        func isDark(_ x: Int, _ y: Int) -> Bool {
            let i = (y * w + x) * 4
            return px[i] <= threshold && px[i + 1] <= threshold && px[i + 2] <= threshold
        }
        func rowIsDark(_ y: Int) -> Bool { (0..<w).allSatisfy { isDark($0, y) } }
        func columnIsDark(_ x: Int) -> Bool { (0..<h).allSatisfy { isDark(x, $0) } }

        var top = 0, bottom = 0, left = 0, right = 0
        while top < h / 2, rowIsDark(top) { top += 1 }
        while bottom < h / 2, rowIsDark(h - 1 - bottom) { bottom += 1 }
        while left < w / 2, columnIsDark(left) { left += 1 }
        while right < w / 2, columnIsDark(w - 1 - right) { right += 1 }

        guard top + bottom + left + right > 0,
              abs(top - bottom) <= 2, abs(left - right) <= 2 else { return image }

        let cropWidth = w - left - right, cropHeight = h - top - bottom
        guard cropWidth > 0, cropHeight > 0 else { return image }
        let ratio = Double(cropWidth) / Double(cropHeight)
        let photoRatios: [Double] = [3.0 / 2, 2.0 / 3, 16.0 / 9, 9.0 / 16, 1, 5.0 / 4, 4.0 / 5]
        guard photoRatios.contains(where: { abs($0 - ratio) / $0 < 0.05 }) else { return image }

        return image.cropping(to: CGRect(x: left, y: top, width: cropWidth, height: cropHeight)) ?? image
    }

    /// Develops a RAF with macOS's own RAW engine (Apple's rendering, not Fujifilm's).
    static func rawImage(at url: URL) -> CGImage? {
        guard let filter = CIRAWFilter(imageURL: url), let output = filter.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(output, from: output.extent)
    }
}
