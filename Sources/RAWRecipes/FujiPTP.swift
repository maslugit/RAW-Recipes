import Foundation
import ImageCaptureCore

/// Groundwork for in-camera RAW conversion (what Fujifilm X RAW Studio does).
///
/// Commands are sent through ImageCaptureCore, so macOS keeps control of the USB device
/// and we do not fight the system's own camera service.
///
/// The conversion protocol itself is NOT implemented yet. References for the next step:
///   - petabyt/fp         – Fujifilm's profile format (the d185 structure sent over PTP)
///   - petabyt/fudge      – working RAF→JPG conversion through the camera
///   - eggricesoy/filmkit – QUICK_REFERENCE.md with a protocol description
/// The camera must be in "USB RAW CONV./BACKUP RESTORE" mode for conversion,
/// and can only convert RAF files shot with the same camera model.
enum PTPOperation {
    static let getDeviceInfo: UInt16 = 0x1001
    static let getDevicePropValue: UInt16 = 0x1015
    static let setDevicePropValue: UInt16 = 0x1016
}

enum FujiPTPError: LocalizedError {
    case notImplemented
    case noResponse

    var errorDescription: String? {
        switch self {
        case .notImplemented: return "In-camera RAW conversion is not implemented yet."
        case .noResponse: return "The camera did not respond to the PTP command."
        }
    }
}

final class FujiRawConverter {
    let camera: ICCameraDevice
    private var transactionID: UInt32 = 1

    init(camera: ICCameraDevice) {
        self.camera = camera
    }

    /// Builds a PTP command container (little-endian):
    /// length (4) · type = 1 (2) · operation code (2) · transaction ID (4) · parameters (4 × n)
    static func commandContainer(code: UInt16, transactionID: UInt32, params: [UInt32] = []) -> Data {
        var data = Data()
        func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        put32(UInt32(12 + 4 * params.count))
        put16(1)
        put16(code)
        put32(transactionID)
        params.forEach(put32)
        return data
    }

    /// Sends a PTP command. Returns (data from the camera, PTP response).
    func send(code: UInt16, params: [UInt32] = [], outData: Data? = nil) async throws -> (data: Data, response: Data) {
        let command = Self.commandContainer(code: code, transactionID: transactionID, params: params)
        transactionID &+= 1
        return try await withCheckedThrowingContinuation { continuation in
            camera.requestSendPTPCommand(command, outData: outData) { data, response, error in
                let d: Data? = data
                let r: Data? = response
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (d ?? Data(), r ?? Data()))
                }
            }
        }
    }

    /// Simple check that the PTP channel works.
    func getDeviceInfo() async throws -> Data {
        let result = try await send(code: PTPOperation.getDeviceInfo)
        guard !result.data.isEmpty else { throw FujiPTPError.noResponse }
        return result.data
    }

    /// Reads a (Fujifilm-specific) device property, e.g. 0xD185.
    func getProperty(_ code: UInt16) async throws -> Data {
        try await send(code: PTPOperation.getDevicePropValue, params: [UInt32(code)]).data
    }

    /// Next step: send RAF + conversion profile and receive a JPEG from the camera.
    func convert(rafURL: URL) async throws -> Data {
        throw FujiPTPError.notImplemented
    }
}
