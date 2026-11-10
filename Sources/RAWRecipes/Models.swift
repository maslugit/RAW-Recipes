import Foundation
import CoreGraphics
import ImageCaptureCore

enum FileKind {
    case raw, jpeg, other

    init(name: String) {
        switch (name as NSString).pathExtension.lowercased() {
        case "raf": self = .raw
        case "jpg", "jpeg": self = .jpeg
        default: self = .other
        }
    }
}

/// Which files are imported for each shot.
enum ImportFileTypes: String, CaseIterable {
    case both, rawOnly, jpegOnly

    var title: String {
        switch self {
        case .both: return "RAW + JPG"
        case .rawOnly: return "RAW only"
        case .jpegOnly: return "JPG only"
        }
    }

    var includesRAW: Bool { self != .jpegOnly }

    func includes(_ file: ICCameraFile) -> Bool {
        switch FileKind(name: file.name ?? "") {
        case .raw: return self != .jpegOnly
        case .jpeg: return self != .rawOnly
        case .other: return self == .both
        }
    }
}

/// One exposure: RAF and/or JPG with the same file name (DSCF1234.RAF + DSCF1234.JPG).
final class Shot: ObservableObject, Identifiable {
    /// "folder/STEM", e.g. "100_FUJI/DSCF1234", so wrapped-around file numbers do not collide.
    let id: String
    let displayName: String

    private(set) var raw: ICCameraFile?
    private(set) var jpeg: ICCameraFile?
    private(set) var others: [ICCameraFile] = []

    @Published var thumbnail: CGImage?
    @Published var preview: CGImage?
    @Published var fullImage: CGImage?
    @Published var settings: FujiSettings?

    /// Files already downloaded to the cache (file name → local URL). Reused when importing.
    var localCopies: [String: URL] = [:]

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    func resetFiles() {
        raw = nil
        jpeg = nil
        others = []
    }

    func add(_ file: ICCameraFile) {
        switch FileKind(name: file.name ?? "") {
        case .raw: raw = file
        case .jpeg: jpeg = file
        case .other: others.append(file)
        }
    }

    var files: [ICCameraFile] { [raw, jpeg].compactMap { $0 } + others }
    var primary: ICCameraFile? { jpeg ?? raw ?? others.first }
    var date: Date? { primary?.creationDate }

    var kindLabel: String {
        switch (raw != nil, jpeg != nil) {
        case (true, true): return "RAW + JPEG"
        case (true, false): return "RAW"
        case (false, true): return "JPEG"
        default: return others.first.flatMap { ($0.name as NSString?)?.pathExtension.uppercased() } ?? "?"
        }
    }
}
