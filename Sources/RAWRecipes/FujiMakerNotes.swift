import Foundation

// MARK: - Camera image settings

/// Fujifilm image settings as stored in the MakerNote part of EXIF.
/// Tag numbers and values follow ExifTool's documentation of the FujiFilm tags.
/// Unrecognized values are shown raw (hex) so the mapping can be extended.
struct FujiSettings {
    let tags: [UInt16: [Int]]

    enum Tag {
        static let sharpness: UInt16 = 0x1001
        static let whiteBalance: UInt16 = 0x1002
        static let color: UInt16 = 0x1003          // "Saturation" – also holds the monochrome modes
        static let contrast: UInt16 = 0x1004
        static let wbFineTune: UInt16 = 0x100A
        static let noiseReduction: UInt16 = 0x100E
        static let clarity: UInt16 = 0x100F
        static let shadowTone: UInt16 = 0x1040
        static let highlightTone: UInt16 = 0x1041
        static let grainRoughness: UInt16 = 0x1047
        static let colorChrome: UInt16 = 0x1048
        static let grainSize: UInt16 = 0x104C
        static let colorChromeBlue: UInt16 = 0x104E
        static let filmMode: UInt16 = 0x1401
        static let dynamicRangeSetting: UInt16 = 0x1402
        static let developmentDynamicRange: UInt16 = 0x1403
    }

    static let films: [Int: String] = [
        0x000: "Provia/Standard",
        0x120: "Astia/Soft",
        0x200: "Velvia/Vivid",
        0x400: "Velvia/Vivid",
        0x500: "Pro Neg. Std",
        0x501: "Pro Neg. Hi",
        0x600: "Classic Chrome",
        0x700: "Eterna/Cinema",
        0x800: "Classic Neg.",
        0x900: "Eterna Bleach Bypass",
        0xA00: "Nostalgic Neg.",
        0xB00: "Reala Ace",
    ]

    static let monochrome: [Int: String] = [
        0x300: "Monochrome",
        0x301: "Monochrome+R",
        0x302: "Monochrome+Ye",
        0x303: "Monochrome+G",
        0x310: "Sepia",
        0x500: "Acros",
        0x501: "Acros+R",
        0x502: "Acros+Ye",
        0x503: "Acros+G",
    ]

    func value(_ tag: UInt16) -> Int? { tags[tag]?.first }

    var filmSimulation: String? {
        if let c = value(Tag.color), let mono = Self.monochrome[c] { return mono }
        if let f = value(Tag.filmMode) { return Self.films[f] ?? String(format: "Unknown (0x%X)", f) }
        return nil
    }

    var isMonochrome: Bool {
        value(Tag.color).map { Self.monochrome[$0] != nil } ?? false
    }

    /// The camera stores tone as -16 × steps (e.g. −32 = +2).
    var highlightTone: Double? { value(Tag.highlightTone).map { -Double($0) / 16 } }
    var shadowTone: Double? { value(Tag.shadowTone).map { -Double($0) / 16 } }

    var grainRoughness: String? { value(Tag.grainRoughness).map { [0: "Off", 32: "Weak", 64: "Strong"][$0] ?? "\($0)" } }
    var grainSize: String? { value(Tag.grainSize).map { [0: "Off", 16: "Small", 32: "Large"][$0] ?? "\($0)" } }
    var colorChrome: String? { value(Tag.colorChrome).map { [0: "Off", 32: "Weak", 64: "Strong"][$0] ?? "\($0)" } }
    var colorChromeBlue: String? { value(Tag.colorChromeBlue).map { [0: "Off", 32: "Weak", 64: "Strong"][$0] ?? "\($0)" } }

    var dynamicRange: String? {
        guard let dr = value(Tag.developmentDynamicRange) else { return nil }
        let auto = value(Tag.dynamicRangeSetting) == 0 ? " (auto)" : ""
        return "DR\(dr)\(auto)"
    }

    /// Newer cameras store the white balance shift × 20. TODO: verify against X-E4 files.
    var whiteBalanceShift: (red: Int, blue: Int)? {
        guard let v = tags[Tag.wbFineTune], v.count >= 2 else { return nil }
        return (v[0] / 20, v[1] / 20)
    }

    var clarity: Double? { value(Tag.clarity).map { Double($0) / 1000 } }

    struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    var rows: [Row] {
        var r: [Row] = []
        func signed(_ d: Double) -> String {
            let s = d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
            return d > 0 ? "+\(s)" : s
        }
        if let f = filmSimulation { r.append(Row(label: "Film simulation", value: f)) }
        if let d = dynamicRange { r.append(Row(label: "Dynamic range", value: d)) }
        if let h = highlightTone { r.append(Row(label: "Highlights", value: signed(h))) }
        if let s = shadowTone { r.append(Row(label: "Shadows", value: signed(s))) }
        if let g = grainRoughness { r.append(Row(label: "Grain", value: g + (grainSize.map { " / \($0)" } ?? ""))) }
        if let c = colorChrome { r.append(Row(label: "Color Chrome", value: c)) }
        if let c = colorChromeBlue { r.append(Row(label: "Color Chrome FX Blue", value: c)) }
        if let wb = whiteBalanceShift { r.append(Row(label: "WB shift", value: "R \(wb.red), B \(wb.blue)")) }
        if let c = clarity { r.append(Row(label: "Clarity", value: signed(c))) }
        // Raw values until the mapping has been verified against real files.
        for (label, tag) in [("Color (raw)", Tag.color), ("Sharpness (raw)", Tag.sharpness), ("Noise red. (raw)", Tag.noiseReduction)] {
            if let v = value(tag), !(tag == Tag.color && isMonochrome) {
                r.append(Row(label: label, value: String(format: "0x%X", v)))
            }
        }
        return r
    }
}

// MARK: - Parsing EXIF / MakerNote

enum FujiMakerNotes {
    /// Reads the Fujifilm MakerNote from a JPEG (the camera JPEG or the preview embedded in a RAF).
    static func parse(jpegData: Data) -> FujiSettings? {
        let bytes = [UInt8](jpegData)
        guard let tiff = exifTIFF(inJPEG: bytes), tiff.count > 8 else { return nil }

        let reader = ByteReader(bytes: tiff, littleEndian: tiff[0] == 0x49)
        guard let ifd0 = reader.u32(4),
              let exifPointer = reader.entries(ifdOffset: Int(ifd0), base: 0).first(where: { $0.tag == 0x8769 }),
              let exifOffset = reader.integers(exifPointer).first,
              let makerNote = reader.entries(ifdOffset: exifOffset, base: 0).first(where: { $0.tag == 0x927C })
        else { return nil }

        let start = makerNote.valueOffset
        let end = start + Int(makerNote.count)
        guard start >= 0, end <= tiff.count, end - start > 12 else { return nil }
        let note = Array(tiff[start..<end])
        guard String(bytes: note[0..<8], encoding: .ascii) == "FUJIFILM" else { return nil }

        // The Fujifilm MakerNote is always little-endian, with offsets relative to the start of the MakerNote.
        let noteReader = ByteReader(bytes: note, littleEndian: true)
        guard let ifd = noteReader.u32(8) else { return nil }

        var tags: [UInt16: [Int]] = [:]
        for entry in noteReader.entries(ifdOffset: Int(ifd), base: 0) {
            let values = noteReader.integers(entry)
            if !values.isEmpty { tags[entry.tag] = values }
        }
        return tags.isEmpty ? nil : FujiSettings(tags: tags)
    }

    /// Finds the APP1 segment "Exif\0\0" and returns the TIFF block after it.
    static func exifTIFF(inJPEG d: [UInt8]) -> [UInt8]? {
        guard d.count > 4, d[0] == 0xFF, d[1] == 0xD8 else { return nil }
        var i = 2
        let exifHeader: [UInt8] = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]
        while i + 4 <= d.count {
            guard d[i] == 0xFF else { return nil }
            let marker = d[i + 1]
            if marker == 0xFF { i += 1; continue }           // padding
            if marker == 0xDA || marker == 0xD9 { return nil } // image data starts
            let length = Int(d[i + 2]) << 8 | Int(d[i + 3])
            let start = i + 4
            let end = i + 2 + length
            guard length >= 2, end <= d.count else { return nil }
            if marker == 0xE1, end - start > 6, Array(d[start..<start + 6]) == exifHeader {
                return Array(d[(start + 6)..<end])
            }
            i = end
        }
        return nil
    }
}

// MARK: - Minimal TIFF/IFD reader

struct IFDEntry {
    let tag: UInt16
    let type: UInt16
    let count: UInt32
    /// Absolute position (in the reader's buffer) of the value.
    let valueOffset: Int
}

struct ByteReader {
    let bytes: [UInt8]
    let littleEndian: Bool

    func u8(_ o: Int) -> UInt8? {
        o >= 0 && o < bytes.count ? bytes[o] : nil
    }

    func u16(_ o: Int) -> UInt16? {
        guard o >= 0, o + 2 <= bytes.count else { return nil }
        let a = UInt16(bytes[o]), b = UInt16(bytes[o + 1])
        return littleEndian ? (a | b << 8) : (a << 8 | b)
    }

    func u32(_ o: Int) -> UInt32? {
        guard o >= 0, o + 4 <= bytes.count else { return nil }
        let b0 = UInt32(bytes[o]), b1 = UInt32(bytes[o + 1]), b2 = UInt32(bytes[o + 2]), b3 = UInt32(bytes[o + 3])
        return littleEndian ? (b0 | b1 << 8 | b2 << 16 | b3 << 24) : (b0 << 24 | b1 << 16 | b2 << 8 | b3)
    }

    static func typeSize(_ type: UInt16) -> Int {
        switch type {
        case 1, 2, 6, 7: return 1
        case 3, 8: return 2
        case 4, 9, 11: return 4
        case 5, 10, 12: return 8
        default: return 1
        }
    }

    /// IFD offsets are relative to `base`.
    func entries(ifdOffset: Int, base: Int) -> [IFDEntry] {
        let start = base + ifdOffset
        guard let n = u16(start), n > 0, n < 1000 else { return [] }
        var result: [IFDEntry] = []
        for i in 0..<Int(n) {
            let e = start + 2 + i * 12
            guard let tag = u16(e), let type = u16(e + 2), let count = u32(e + 4) else { break }
            let size = Self.typeSize(type) * Int(count)
            let valueOffset: Int
            if size <= 4 {
                valueOffset = e + 8
            } else {
                guard let o = u32(e + 8) else { break }
                valueOffset = base + Int(o)
            }
            result.append(IFDEntry(tag: tag, type: type, count: count, valueOffset: valueOffset))
        }
        return result
    }

    /// Integer values of a tag (at most 16).
    func integers(_ e: IFDEntry) -> [Int] {
        let n = min(Int(e.count), 16)
        var out: [Int] = []
        for i in 0..<n {
            let v: Int?
            switch e.type {
            case 1, 7: v = u8(e.valueOffset + i).map { Int($0) }
            case 6: v = u8(e.valueOffset + i).map { Int(Int8(bitPattern: $0)) }
            case 3: v = u16(e.valueOffset + i * 2).map { Int($0) }
            case 8: v = u16(e.valueOffset + i * 2).map { Int(Int16(bitPattern: $0)) }
            case 4: v = u32(e.valueOffset + i * 4).map { Int($0) }
            case 9: v = u32(e.valueOffset + i * 4).map { Int(Int32(bitPattern: $0)) }
            default: v = nil
            }
            if let v { out.append(v) } else { break }
        }
        return out
    }
}
