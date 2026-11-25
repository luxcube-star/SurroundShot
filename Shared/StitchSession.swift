// StitchSession.swift
// 합성 작업(백그라운드)과 사진 앱 저장. 앱과 공유 확장이 함께 사용합니다.

import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

/// 투영 방식
nonisolated enum Projection: Int, CaseIterable, Identifiable, Sendable {
    case cylindrical = 0
    case spherical = 1

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .cylindrical: return "원통 (기본)"
        case .spherical: return "구면"
        }
    }
    var objc: SSProjection {
        switch self {
        case .cylindrical: return .cylindrical
        case .spherical: return .spherical
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
        return StitchCounts(used: stitcher.usedCount, total: stitcher.inputCount)
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
