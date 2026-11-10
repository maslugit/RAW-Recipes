import Foundation
import ImageCaptureCore

/// Reads the embedded JPEG preview from a Fujifilm RAF file.
///
/// RAF header (big-endian):
///   0–15   "FUJIFILMCCD-RAW "
///   84–87  offset of the embedded JPEG
///   88–91  length of the embedded JPEG
enum RAFReader {
    static let magic = Array("FUJIFILMCCD-RAW ".utf8)
    static let headerLength: Int64 = 108

    /// Fetches only the header and the JPEG part from the camera, not the whole RAW file.
    static func embeddedJPEG(from file: ICCameraFile) async throws -> Data {
        let header = try await file.readData(offset: 0, length: headerLength)
        let range = try jpegRange(header: [UInt8](header))
        return try await file.readData(offset: Int64(range.offset), length: Int64(range.length))
    }

    /// The same for a RAF that is already on disk.
    static func embeddedJPEG(fromLocalFile url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: Int(headerLength)) ?? Data()
        let range = try jpegRange(header: [UInt8](header))
        try handle.seek(toOffset: UInt64(range.offset))
        return try handle.read(upToCount: Int(range.length)) ?? Data()
    }

    static func jpegRange(header: [UInt8]) throws -> (offset: UInt32, length: UInt32) {
        guard header.count >= 92, Array(header[0..<16]) == magic else { throw CameraError.notARAF }
        let offset = bigEndianUInt32(header, at: 84)
        let length = bigEndianUInt32(header, at: 88)
        guard offset > 0, length > 0 else { throw CameraError.notARAF }
        return (offset, length)
    }

    private static func bigEndianUInt32(_ b: [UInt8], at i: Int) -> UInt32 {
        UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
    }
}
