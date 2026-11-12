import Foundation
import AppKit
import SwiftUI
import ImageCaptureCore

@MainActor
final class CameraService: NSObject, ObservableObject {
    @Published private(set) var camera: ICCameraDevice?
    @Published private(set) var shots: [Shot] = []
    @Published private(set) var isBusy = false
    @Published var status = "Connect your camera with a USB cable…"

    private let browser = ICDeviceBrowser()
    private let cacheDirectory: URL
    private var inFlight: [String: Task<URL, Error>] = [:]

    override init() {
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RAWRecipes-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        super.init()

        browser.delegate = self
        let mask = ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: mask) ?? .camera
        // On macOS camera access is handled by the system – no authorization calls needed (those are iOS only).
        browser.start()
    }

    // MARK: Camera and catalog

    private func attach(_ device: ICDevice) {
        guard camera == nil, let cam = device as? ICCameraDevice else { return }
        camera = cam
        cam.delegate = self
        status = "Connecting to \(cam.name ?? "camera")…"
        cam.requestOpenSession()
    }

    private func detach() {
        camera = nil
        shots = []
        status = "Camera disconnected."
    }

    fileprivate func rebuildCatalog() {
        guard let cam = camera else { return }
        let existing = Dictionary(uniqueKeysWithValues: shots.map { ($0.id, $0) })
        var result: [String: Shot] = [:]

        for case let file as ICCameraFile in cam.mediaFiles ?? [] {
            guard let name = file.name else { continue }
            let stem = (name as NSString).deletingPathExtension.uppercased()
            let folder = file.parentFolder?.name ?? ""
            let id = "\(folder)/\(stem)"

            let shot: Shot
            if let s = result[id] {
                shot = s
            } else {
                shot = existing[id] ?? Shot(id: id, displayName: stem)
                shot.resetFiles()
                result[id] = shot
            }
            shot.add(file)
        }

        shots = result.values.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        status = "\(cam.name ?? "Camera") – \(shots.count) photos"
    }

    // MARK: Thumbnails, preview, 100 %

    func loadThumbnail(for shot: Shot) {
        guard shot.thumbnail == nil, let file = shot.primary else { return }
        Task {
            if let data = try? await file.thumbnailData(maxPixelSize: 320) {
                if let image = ImageDecoding.cgImage(from: data, maxPixelSize: 320) {
                    shot.thumbnail = ImageDecoding.trimLetterbox(image)
                }
            }
        }
    }

    /// Large preview: Fujifilm's embedded JPEG from the RAF (reads only a few hundred kB),
    /// otherwise the camera JPEG. Also reads the camera settings.
    func loadPreview(for shot: Shot) async {
        guard shot.preview == nil else { return }
        do {
            let jpegData: Data
            if let raw = shot.raw {
                jpegData = try await RAFReader.embeddedJPEG(from: raw)
            } else if let jpg = shot.jpeg {
                let url = try await localCopy(of: jpg, in: shot)
                jpegData = try Data(contentsOf: url)
            } else {
                return
            }
            shot.settings = FujiMakerNotes.parse(jpegData: jpegData)
            let preview = await Task.detached(priority: .userInitiated) {
                ImageDecoding.cgImage(from: jpegData, maxPixelSize: 3000)
            }.value
            shot.preview = preview

            // The preview is always correctly rotated and sharper than the camera's thumbnail,
            // so it replaces the filmstrip thumbnail.
            if let preview, let small = ImageDecoding.downscaled(preview, maxPixelSize: 360) {
                await replaceThumbnail(of: shot, with: small,
                                       orientation: ImageDecoding.orientation(of: jpegData))
            }
        } catch {
            status = "Preview failed: \(error.localizedDescription)"
        }
    }

    /// Swaps in a better thumbnail. If the old one had the wrong orientation (landscape instead
    /// of portrait or the other way round), it first turns 90° in the direction the EXIF
    /// orientation says, while the cell resizes; then the sharp image takes its place.
    /// Otherwise the new image simply fades in.
    private func replaceThumbnail(of shot: Shot, with image: CGImage, orientation: Int) async {
        let newAspect = CGFloat(image.width) / CGFloat(image.height)
        let duration = 0.45

        if let old = shot.thumbnail, (old.height > old.width) != (image.height > image.width) {
            let angle: Double = orientation == 8 ? -90 : 90
            withAnimation(.easeInOut(duration: duration)) {
                shot.thumbnailRotation = angle
                shot.displayAspect = newAspect
            }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

            // Now the old image shows the same orientation as the new one – swap without a fade.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                shot.thumbnail = image
                shot.thumbnailRotation = 0
            }
        } else {
            withAnimation(.easeInOut(duration: duration)) {
                shot.thumbnail = image
                shot.displayAspect = newAspect
            }
        }
    }

    /// 100 %: the camera JPEG if there is one (Fujifilm's rendering), otherwise the RAF via the macOS RAW engine.
    func loadFullResolution(for shot: Shot) async {
        guard shot.fullImage == nil else { return }
        do {
            if let jpg = shot.jpeg {
                let url = try await localCopy(of: jpg, in: shot)
                shot.fullImage = await Task.detached(priority: .userInitiated) {
                    ImageDecoding.cgImage(contentsOf: url)
                }.value
            } else if let raw = shot.raw {
                let url = try await localCopy(of: raw, in: shot)
                shot.fullImage = await Task.detached(priority: .userInitiated) {
                    ImageDecoding.rawImage(at: url)
                }.value
            }
        } catch {
            status = "Could not load the original: \(error.localizedDescription)"
        }
    }

    /// Downloads the file to the cache once; reused when importing.
    /// If the same file is already being downloaded we wait for it instead of starting another.
    private func localCopy(of file: ICCameraFile, in shot: Shot) async throws -> URL {
        let name = file.name ?? UUID().uuidString
        if let url = shot.localCopies[name], isComplete(url, file) {
            return url
        }
        let key = "\(shot.id)/\(name)"
        if let running = inFlight[key] {
            return try await running.value
        }

        let dir = cacheDirectory.appendingPathComponent(
            shot.id.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(name)

        let task = Task<URL, Error> {
            try await file.downloadVerified(to: destination)
            return destination
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let url = try await task.value
        shot.localCopies[name] = url
        return url
    }

    /// Does the file exist and have the same size as on the camera?
    private func isComplete(_ url: URL, _ file: ICCameraFile) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? -1
        return size == Int64(file.fileSize)
    }

    // MARK: Import

    /// File names among the selected shots that already exist in `folder`.
    func existingFiles(for selected: [Shot], in folder: URL, fileTypes: ImportFileTypes = .both) -> [String] {
        selected.flatMap(\.files).filter(fileTypes.includes).compactMap(\.name).filter {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    /// - Parameter overwrite: `true` replaces existing files, `false` skips them.
    func importShots(_ selected: [Shot], to folder: URL, overwrite: Bool,
                     fileTypes: ImportFileTypes = .both,
                     writeXMP: Bool, writeRRData: Bool = false) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let fm = FileManager.default
        var imported = 0, skipped = 0, failed = 0
        var lastError: String?

        for (index, shot) in selected.enumerated() {
            status = "Importing \(index + 1) of \(selected.count)…"

            for file in shot.files where fileTypes.includes(file) {
                guard let name = file.name else { continue }
                let destination = folder.appendingPathComponent(name)
                if fm.fileExists(atPath: destination.path) {
                    if !overwrite { skipped += 1; continue }
                    // Fetch a fresh copy from the camera instead of reusing the file being replaced.
                    if shot.localCopies[name]?.standardizedFileURL == destination.standardizedFileURL {
                        shot.localCopies[name] = nil
                    }
                }
                do {
                    let cached = try await localCopy(of: file, in: shot)
                    if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                    try fm.moveItem(at: cached, to: destination)
                    shot.localCopies[name] = destination   // the preview now reads from the imported file
                    imported += 1
                } catch {
                    failed += 1
                    lastError = "\(name): \(error.localizedDescription)"
                }
            }

            // Sidecars belong to the RAW file – only when RAW is imported.
            if fileTypes.includesRAW, (writeXMP || writeRRData), let raw = shot.raw, let rawName = raw.name {
                if shot.settings == nil {
                    let rafURL = folder.appendingPathComponent(rawName)
                    if let jpeg = try? RAFReader.embeddedJPEG(fromLocalFile: rafURL) {
                        shot.settings = FujiMakerNotes.parse(jpegData: jpeg)
                    }
                }
                if let settings = shot.settings {
                    // Existing sidecars are never overwritten – they may contain your own edits.
                    if writeXMP {
                        let xmpURL = folder.appendingPathComponent((rawName as NSString).deletingPathExtension + ".xmp")
                        if !fm.fileExists(atPath: xmpURL.path) {
                            try? LightroomSidecar.xmp(for: settings).write(to: xmpURL, atomically: true, encoding: .utf8)
                        }
                    }
                    if writeRRData {
                        let rrURL = folder.appendingPathComponent(rawName + ".rrdata")
                        if !fm.fileExists(atPath: rrURL.path),
                           let data = try? RapidRAWSidecar.rrdata(for: settings) {
                            try? data.write(to: rrURL, options: .atomic)
                        }
                    }
                }
            }
        }

        var summary = "Done: \(imported) files imported"
        if skipped > 0 { summary += ", \(skipped) skipped" }
        if failed > 0 { summary += ", \(failed) failed (last: \(lastError ?? "unknown error"))" }
        status = summary
    }

    // MARK: PTP test

    func testPTPConnection() async {
        guard let cam = camera else { status = "No camera connected."; return }
        do {
            let info = try await FujiRawConverter(camera: cam).getDeviceInfo()
            status = "PTP works – DeviceInfo: \(info.count) bytes"
        } catch {
            status = "PTP error: \(error.localizedDescription)"
        }
    }
}

// MARK: - ICDeviceBrowserDelegate

extension CameraService: ICDeviceBrowserDelegate {
    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        Task { @MainActor in self.attach(device) }
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        Task { @MainActor in
            if self.camera === device { self.detach() }
        }
    }
}

// MARK: - ICCameraDeviceDelegate

extension CameraService: ICCameraDeviceDelegate {
    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        Task { @MainActor in
            if let error { self.status = "Could not open the camera: \(error.localizedDescription)" }
            else { self.status = "Reading photo list…" }
        }
    }

    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}

    nonisolated func didRemove(_ device: ICDevice) {
        Task { @MainActor in
            if self.camera === device { self.detach() }
        }
    }

    nonisolated func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        Task { @MainActor in self.rebuildCatalog() }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        Task { @MainActor in if !self.shots.isEmpty { self.rebuildCatalog() } }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        Task { @MainActor in self.rebuildCatalog() }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}
}
