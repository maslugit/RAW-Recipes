import Foundation

/// Creates a RapidRAW sidecar (DSCF1234.RAF.rrdata) with the Fujifilm settings translated
/// to RapidRAW's sliders. RapidRAW reads the file when the photo is opened.
///
/// The template below is RapidRAW's default values, taken from a real .rrdata (version 1).
/// We start from it and only change the fields we can translate.
enum RapidRAWSidecar {
    /// Calibration constants – adjust after comparing with the camera JPEG.
    enum Calibration {
        static let highlightPerStep = 15.0   // Fujifilm highlights +1 ≈ RapidRAW highlights +15
        static let shadowPerStep = -15.0     // Fujifilm shadows +1 (harder) ≈ RapidRAW shadows −15
        static let clarityPerStep = 10.0     // Fujifilm clarity ±5 → RapidRAW clarity ±50
        static let grainAmount = ["Weak": 25, "Strong": 50]
        static let grainSize = ["Small": 25, "Large": 50]
        /// Color filter for monochrome (hue in degrees). TODO: verify in RapidRAW.
        static let monochromeFilterHue = ["+R": 0, "+Ye": 60, "+G": 120]
        static let monochromeFilterStrength = 50
    }

    static func rrdata(for s: FujiSettings) throws -> Data {
        var adj = try JSONSerialization.jsonObject(with: Data(defaultAdjustments.utf8)) as? [String: Any] ?? [:]

        if let h = s.highlightTone, h != 0 {
            adj["highlights"] = Int((h * Calibration.highlightPerStep).rounded())
        }
        if let sh = s.shadowTone, sh != 0 {
            adj["shadows"] = Int((sh * Calibration.shadowPerStep).rounded())
        }
        if let c = s.clarity, c != 0 {
            adj["clarity"] = Int((c * Calibration.clarityPerStep).rounded())
        }
        if let rough = s.grainRoughness, let amount = Calibration.grainAmount[rough] {
            adj["grainAmount"] = amount
            if let size = s.grainSize.flatMap({ Calibration.grainSize[$0] }) { adj["grainSize"] = size }
        }
        if s.isMonochrome {
            adj["monochromeEnabled"] = true
            if let film = s.filmSimulation,
               let filter = Calibration.monochromeFilterHue.first(where: { film.hasSuffix($0.key) }) {
                adj["monochromeFilterHue"] = filter.value
                adj["monochromeFilterStrength"] = Calibration.monochromeFilterStrength
            }
        }
        // The film simulation colors (LUT) are not set – RapidRAW uses its own colors.

        let root: [String: Any] = [
            "version": 1,
            "rating": 0,
            "adjustments": adj,
            "tags": NSNull(),
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    // swiftlint:disable line_length
    static let defaultAdjustments = #"{"activeTools":{},"aiDenoiseAmount":100,"aiDenoiseDetail":0,"aiDenoiseEnabled":false,"aiDenoiseMethod":"ai","aiPatches":[],"aspectRatio":0,"baselineExposure":true,"blacks":0,"brightness":0,"centré":0,"centréX":0.5,"centréY":0.5,"chromaticAberrationBlueYellow":0,"chromaticAberrationRedCyan":0,"clarity":0,"colorCalibration":{"blueHue":0,"blueSaturation":0,"greenHue":0,"greenSaturation":0,"redHue":0,"redSaturation":0,"shadowsTint":0},"colorGrading":{"balance":0,"blending":50,"global":{"hue":0,"luminance":0,"saturation":0},"highlights":{"hue":0,"luminance":0,"saturation":0},"midtones":{"hue":0,"luminance":0,"saturation":0},"shadows":{"hue":0,"luminance":0,"saturation":0}},"colorNoiseReduction":0,"contrast":0,"crop":null,"curveMode":"point","curves":{"blue":[{"x":0,"y":0},{"x":255,"y":255}],"green":[{"x":0,"y":0},{"x":255,"y":255}],"luma":[{"x":0,"y":0},{"x":255,"y":255}],"red":[{"x":0,"y":0},{"x":255,"y":255}]},"dehaze":0,"exposure":0,"flareAmount":0,"flipHorizontal":false,"flipVertical":false,"fogAmount":50,"fogDensity":50,"fogDepthMap":null,"fogEnabled":false,"fogGlow":25,"fogHeight":0,"fogStart":0,"fogTemperature":0,"fogTint":0,"fogVariation":25,"glowAmount":0,"grainAmount":0,"grainRoughness":50,"grainSize":25,"guidedPerspective":{"autoCrop":true,"enabled":false,"lines":[]},"halationAmount":0,"highlights":0,"hsl":{"aquas":{"hue":0,"luminance":0,"saturation":0},"blues":{"hue":0,"luminance":0,"saturation":0},"greens":{"hue":0,"luminance":0,"saturation":0},"magentas":{"hue":0,"luminance":0,"saturation":0},"oranges":{"hue":0,"luminance":0,"saturation":0},"purples":{"hue":0,"luminance":0,"saturation":0},"reds":{"hue":0,"luminance":0,"saturation":0},"yellows":{"hue":0,"luminance":0,"saturation":0}},"hue":0,"lensBlurAmount":40,"lensBlurDepthMap":null,"lensBlurDiffusion":0,"lensBlurEnabled":false,"lensBlurMaxDepth":90,"lensBlurMaxFade":10,"lensBlurMinDepth":10,"lensBlurMinFade":10,"lensBlurShape":"circle","lensCorrectionMode":"manual","lensDistortionAmount":100,"lensDistortionEnabled":true,"lensDistortionParams":null,"lensMaker":null,"lensModel":null,"lensTcaAmount":100,"lensTcaEnabled":true,"lensVignetteAmount":100,"lensVignetteEnabled":true,"lumaNoiseReduction":0,"lutData":null,"lutIntensity":100,"lutIsSceneReferred":false,"lutName":null,"lutPath":null,"lutSize":0,"masks":[],"monochromeEnabled":false,"monochromeFilm":"neutral","monochromeFilterHue":0,"monochromeFilterStrength":0,"monochromeMix":{"aquas":0,"blues":0,"greens":0,"magentas":0,"oranges":0,"purples":0,"reds":0,"yellows":0},"monochromeToning":{"balance":0,"highlightHue":40,"highlightSaturation":0,"shadowHue":220,"shadowSaturation":0},"motionBlurAmount":0,"motionBlurAngle":0,"motionBlurDepth":50,"motionBlurDepthEnabled":false,"motionBlurDepthMap":null,"motionBlurHighlights":30,"motionBlurLayer":"auto","motionBlurType":"linear","negativeBlueWeight":1,"negativeContrast":1,"negativeConversionEnabled":false,"negativeExposure":0,"negativeGreenWeight":1,"negativeRedWeight":1,"orientationSteps":0,"parametricCurve":{"blue":{"blackLevel":0,"darks":0,"highlights":0,"lights":0,"shadows":0,"split1":25,"split2":50,"split3":75,"whiteLevel":0},"green":{"blackLevel":0,"darks":0,"highlights":0,"lights":0,"shadows":0,"split1":25,"split2":50,"split3":75,"whiteLevel":0},"luma":{"blackLevel":0,"darks":0,"highlights":0,"lights":0,"shadows":0,"split1":25,"split2":50,"split3":75,"whiteLevel":0},"red":{"blackLevel":0,"darks":0,"highlights":0,"lights":0,"shadows":0,"split1":25,"split2":50,"split3":75,"whiteLevel":0}},"pointCurves":{"blue":[{"x":0,"y":0},{"x":255,"y":255}],"green":[{"x":0,"y":0},{"x":255,"y":255}],"luma":[{"x":0,"y":0},{"x":255,"y":255}],"red":[{"x":0,"y":0},{"x":255,"y":255}]},"relightAmbient":-50,"relightEnabled":false,"relightLights":[],"relightNormalMap":null,"relightShadowSoftness":15,"relightShadows":false,"relightShine":0,"relightSoftness":25,"rotation":0,"saturation":0,"shadows":0,"sharpness":0,"sharpnessThreshold":15,"showClipping":false,"structure":0,"temperature":0,"tint":0,"toneMapper":"basic","transformAspect":0,"transformDistortion":0,"transformHorizontal":0,"transformRotate":0,"transformScale":100,"transformVertical":0,"transformXOffset":0,"transformYOffset":0,"vibrance":0,"vignetteAmount":0,"vignetteCenterX":0.5,"vignetteCenterY":0.5,"vignetteFeather":50,"vignetteMidpoint":50,"vignetteRoundness":0,"whiteBalance":null,"whites":0}"#
}
