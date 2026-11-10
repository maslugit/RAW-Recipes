import Foundation
import ImageCaptureCore

enum CameraError: LocalizedError {
    case noData
    case notARAF
    case downloadFailed
    case truncated(expected: Int64, got: Int64)

    var errorDescription: String? {
        switch self {
        case .noData: return "The camera sent no data."
        case .notARAF: return "The file does not look like a Fujifilm RAF."
        case .downloadFailed: return "The download failed."
        case let .truncated(expected, got): return "The file is incomplete (\(got) of \(expected) bytes)."
        }
    }
}

extension ICCameraFile {
    /// Reads part of the file straight from the camera without downloading all of it.
    func readData(offset: Int64, length: Int64) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            requestReadData(atOffset: off_t(offset), length: off_t(length)) { data, error in
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CameraError.noData)
                }
            }
        }
    }

    func thumbnailData(maxPixelSize: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            requestThumbnailData(options: [.imageSourceThumbnailMaxPixelSize: maxPixelSize]) { data, error in
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CameraError.noData)
                }
            }
        }
    }

    /// Downloads the whole file to `destination` by reading it in chunks.
    ///
    /// ImageCaptureCore's `requestDownload` produced truncated files with the X-E4, so we read
    /// the file ourselves with `requestReadData`, write it to a `.partial` file, check that the
    /// size matches, and only then move it into place. A half-written file is never visible.
    func downloadVerified(to destination: URL, chunkSize: Int64 = 4 << 20) async throws {
        let total = Int64(fileSize)
        guard total > 0 else { throw CameraError.noData }

        let fm = FileManager.default
        let partial = destination.appendingPathExtension("partial")
        try? fm.removeItem(at: partial)
        guard fm.createFile(atPath: partial.path, contents: nil) else { throw CameraError.downloadFailed }

        let handle = try FileHandle(forWritingTo: partial)
        do {
            var offset: Int64 = 0
            while offset < total {
                let chunk = try await readData(offset: offset, length: min(chunkSize, total - offset))
                try handle.write(contentsOf: chunk)
                offset += Int64(chunk.count)
            }
            try handle.close()
        } catch {
            try? handle.close()
            try? fm.removeItem(at: partial)
            throw error
        }

        let written = (try? fm.attributesOfItem(atPath: partial.path)[.size] as? Int64) ?? -1
        guard written == total else {
            try? fm.removeItem(at: partial)
            throw CameraError.truncated(expected: total, got: written)
        }

        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: partial, to: destination)
    }
}
