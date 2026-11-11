import Foundation

/// Creates an XMP sidecar (DSCF1234.xmp) that Lightroom reads when the RAF is imported.
/// The mapping is a first approximation and should be calibrated against real camera JPEGs.
enum LightroomSidecar {
    /// Fujifilm film simulation → Adobe "Camera Matching" profile.
    /// TODO: verify the exact profile names in Lightroom (Profile → Camera Matching).
    static let profiles: [String: String] = [
        "Provia/Standard": "Camera PROVIA/Standard",
        "Astia/Soft": "Camera ASTIA/Soft",
        "Velvia/Vivid": "Camera Velvia/Vivid",
        "Pro Neg. Std": "Camera PRO Neg. Std",
        "Pro Neg. Hi": "Camera PRO Neg. Hi",
        "Classic Chrome": "Camera CLASSIC CHROME",
        "Eterna/Cinema": "Camera ETERNA/Cinema",
        "Classic Neg.": "Camera CLASSIC Neg.",
        "Eterna Bleach Bypass": "Camera ETERNA BLEACH BYPASS",
        "Nostalgic Neg.": "Camera NOSTALGIC Neg.",
        "Reala Ace": "Camera REALA ACE",
        "Monochrome": "Camera MONOCHROME",
        "Monochrome+R": "Camera MONOCHROME+R FILTER",
        "Monochrome+Ye": "Camera MONOCHROME+Ye FILTER",
        "Monochrome+G": "Camera MONOCHROME+G FILTER",
        "Sepia": "Camera MONOCHROME",
        "Acros": "Camera ACROS",
        "Acros+R": "Camera ACROS+R FILTER",
        "Acros+Ye": "Camera ACROS+Ye FILTER",
        "Acros+G": "Camera ACROS+G FILTER",
    ]

    /// Calibration constants – adjust after comparing with the camera JPEG.
    enum Calibration {
        static let highlightPerStep = 15.0   // Fujifilm highlights +1 ≈ Lightroom Highlights +15
        static let shadowPerStep = -15.0     // Fujifilm shadows +1 (harder) ≈ Lightroom Shadows −15
        static let grainAmount = ["Weak": 25, "Strong": 50]
        static let grainSize = ["Small": 25, "Large": 50]
    }

    static func xmp(for s: FujiSettings) -> String {
        var attrs: [(String, String)] = [
            ("crs:Version", "15.0"),
            ("crs:ProcessVersion", "11.0"),
            ("crs:HasSettings", "True"),
        ]
        if let film = s.filmSimulation, let profile = profiles[film] {
            attrs.append(("crs:CameraProfile", profile))
        }
        if s.isMonochrome {
            attrs.append(("crs:ConvertToGrayscale", "True"))
        }
        if let h = s.highlightTone, h != 0 {
            attrs.append(("crs:Highlights2012", signed(Int((h * Calibration.highlightPerStep).rounded()))))
        }
        if let sh = s.shadowTone, sh != 0 {
            attrs.append(("crs:Shadows2012", signed(Int((sh * Calibration.shadowPerStep).rounded()))))
        }
        if let rough = s.grainRoughness, let amount = Calibration.grainAmount[rough] {
            attrs.append(("crs:GrainAmount", "\(amount)"))
            attrs.append(("crs:GrainSize", "\(s.grainSize.flatMap { Calibration.grainSize[$0] } ?? 25)"))
            attrs.append(("crs:GrainFrequency", "50"))
        }
        if let c = s.clarity, c != 0 {
            attrs.append(("crs:Clarity2012", signed(Int((c * 10).rounded()))))
        }
        // Color Chrome and tone curves have no direct equivalent – left for calibration.

        let attributeLines = attrs
            .map { "    \($0.0)=\"\(escape($0.1))\"" }
            .joined(separator: "\n")

        return """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="RAW Recipes">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
        \(attributeLines)/>
         </rdf:RDF>
        </x:xmpmeta>

        """
    }

    private static func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : "\(v)" }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}
