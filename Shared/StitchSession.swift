// StitchSession.swift
// 합성 작업(백그라운드)과 사진 앱 저장. 앱과 공유 확장이 함께 사용합니다.

import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

/// 투영 방식
/// 화면 순서: 원통 · 구형 · 평면. 기본은 평면.
nonisolated enum Projection: Int, CaseIterable, Identifiable, Sendable {
    case cylindrical = 0
    case spherical = 1
    case plane = 2

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .cylindrical: return "원통"
        case .spherical: return "구형"
        case .plane: return "평면 (기본)"
        }
    }
    var detail: String {
        switch self {
        case .cylindrical: return "세로선(건물 모서리)이 곧게 유지됩니다. 아주 넓게 찍어도 됩니다."
        case .spherical: return "위아래까지 넓게 찍었을 때 자연스럽습니다."
        case .plane: return "일반 사진처럼 직선이 곧게 유지됩니다. 너무 넓게 찍으면 자동으로 원통으로 바뀝니다."
        }
    }
    var objc: SSProjection {
        switch self {
        case .cylindrical: return .cylindrical
        case .spherical: return .spherical
        case .plane: return .plane
        }
    }
}

/// 결과 사진 형태
nonisolated enum OutputMode: Int, CaseIterable, Identifiable, Sendable {
    case fill43 = 0
    case fit43 = 1
    case original = 2

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .fill43: return "4:3 꽉 채우기"
        case .fit43: return "4:3 여백"
        case .original: return "원본 비율"
        }
    }
    var detail: String {
        switch self {
        case .fill43: return "4:3으로 꽉 채웁니다. 넓게 찍으면 양옆이 잘립니다."
        case .fit43: return "전체를 유지하고 흰 여백을 붙여 4:3으로 맞춥니다."
        case .original: return "빈 곳만 잘라낸 원래 비율입니다."
        }
    }
    var objc: SSOutputMode {
        switch self {
        case .fill43: return .fill43
        case .fit43: return .fit43
        case .original: return .original
        }
    }
}

nonisolated struct StitchCounts: Sendable {
    let used: Int
    let total: Int
    /// 평면을 요청했지만 너무 넓어서 원통으로 바꿨는지
    let planeFellBack: Bool
    /// 가운데 방향에서 가장 먼 사진 모서리까지의 각도 (도)
    let maxAngleDegrees: Double
}

/// OpenCV 합성기를 감싼 세션. 한 번 합성한 결과를 보관해 두고 형태만 바꿔 다시 만들 수 있습니다.
/// 내부 잠금으로 한 번에 하나의 작업만 실행됩니다.
nonisolated final class StitchSession: @unchecked Sendable {
    private let stitcher = PanoramaStitcher()
    private let lock = NSLock()
    private var metadataSource: Data?

    /// 합성 전에 각 사진을 줄일 크기 (긴 변 px)
    let maxPixelSize: Int
    /// 결과 사진의 긴 변 최대 px
    let maxOutputSide: Int

    init(maxPixelSize: Int, maxOutputSide: Int) {
        self.maxPixelSize = maxPixelSize
        self.maxOutputSide = maxOutputSide
    }

    func stitch(_ imageData: [Data], projection: Projection) throws -> StitchCounts {
        lock.lock()
        defer { lock.unlock() }
        try stitcher.stitch(imageData: imageData, maxPixelSize: maxPixelSize, projection: projection.objc)
        metadataSource = imageData.first
        return StitchCounts(used: stitcher.usedCount,
                            total: stitcher.inputCount,
                            planeFellBack: stitcher.planeFellBack,
                            maxAngleDegrees: stitcher.maxAngleDegrees)
    }

    func render(_ mode: OutputMode) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        let jpeg = try stitcher.jpeg(mode: mode.objc, maxOutputSide: maxOutputSide, quality: 98)
        guard let source = metadataSource else { return jpeg }
        return Self.copyCaptureMetadata(into: jpeg, from: source)
    }

    /// 첫 번째 원본 사진의 촬영 날짜·위치(GPS)·기종 정보를 결과 사진에 복사합니다.
    /// 사진 앱에서 촬영 날짜와 위치가 원본과 같게 표시됩니다.
    static func copyCaptureMetadata(into jpeg: Data, from original: Data) -> Data {
        guard
            let originalSource = CGImageSourceCreateWithData(original as CFData, nil),
            let originalProps = CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil) as? [String: Any],
            let jpegSource = CGImageSourceCreateWithData(jpeg as CFData, nil)
        else { return jpeg }

        var props: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: 0.92,
            kCGImagePropertyOrientation as String: 1,
        ]
        if let exif = originalProps[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            let keep: Set<String> = [
                kCGImagePropertyExifDateTimeOriginal as String,
                kCGImagePropertyExifDateTimeDigitized as String,
                kCGImagePropertyExifOffsetTime as String,
                kCGImagePropertyExifOffsetTimeOriginal as String,
                kCGImagePropertyExifOffsetTimeDigitized as String,
            ]
            props[kCGImagePropertyExifDictionary as String] = exif.filter { keep.contains($0.key) }
        }
        if let gps = originalProps[kCGImagePropertyGPSDictionary as String] {
            props[kCGImagePropertyGPSDictionary as String] = gps
        }
        if let tiff = originalProps[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            let keep: Set<String> = [
                kCGImagePropertyTIFFMake as String,
                kCGImagePropertyTIFFModel as String,
                kCGImagePropertyTIFFDateTime as String,
            ]
            var t = tiff.filter { keep.contains($0.key) }
            t[kCGImagePropertyTIFFOrientation as String] = 1
            props[kCGImagePropertyTIFFDictionary as String] = t
        }

        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output as CFMutableData,
                                                          UTType.jpeg.identifier as CFString, 1, nil)
        else { return jpeg }
        CGImageDestinationAddImageFromSource(dest, jpegSource, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return jpeg }
        return output as Data
    }
}

/// 사진 앱(보관함)에 저장
nonisolated enum PhotoSaver {
    enum SaveError: LocalizedError {
        case denied
        var errorDescription: String? {
            "사진 저장 권한이 없습니다.\n설정 > 개인정보 보호 및 보안 > 사진에서 이 앱의 '사진 추가'를 허용해 주세요."
        }
    }

    static func save(_ jpeg: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: jpeg, options: nil)
        }
    }
}
