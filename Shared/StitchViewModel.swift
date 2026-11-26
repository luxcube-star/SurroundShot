// StitchViewModel.swift
// 화면 상태 관리. 앱과 공유 확장이 함께 사용합니다.

import ImageIO
import SwiftUI
import UIKit

@MainActor
final class StitchViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case working(String)
        case done
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var projection: Projection = .plane
    @Published var outputMode: OutputMode {
        didSet { UserDefaults.standard.set(outputMode.rawValue, forKey: Self.outputModeKey) }
    }
    /// 고른 넓이 (실제만 / 넓게 / 더 넓게)
    @Published private(set) var outputWidth: OutputWidth {
        didSet { UserDefaults.standard.set(outputWidth.rawValue, forKey: Self.outputWidthKey) }
    }
    /// 고른 결과의 큰 미리보기 (화면용으로 줄인 것)
    @Published private(set) var previewImage: UIImage?
    /// 넓이별 작은 미리보기
    @Published private(set) var widthThumbnails: [OutputWidth: UIImage] = [:]
    /// 넓이별 결과 크기 (픽셀)
    @Published private(set) var widthSizes: [OutputWidth: CGSize] = [:]
    @Published private(set) var info: String = ""
    @Published private(set) var warning: String?
    @Published var saveMessage: String?
    @Published private(set) var isSaving = false
    /// 입력 사진 작은 미리보기 (가운데 사진 고르기용)
    @Published private(set) var thumbnails: [UIImage] = []
    /// 가운데 사진 번호 (자동으로 찾았거나 직접 고른 것). nil = 특정 사진 없음
    @Published private(set) var centerIndex: Int?
    /// 가운데 사진을 자동으로 정하는 중인지 (직접 고르면 false)
    @Published private(set) var isAutoCenter = true

    private static let outputModeKey = "outputMode"
    private static let outputWidthKey = "outputWidth"
    private let session: StitchSession
    private var sourceData: [Data] = []
    /// 앱 카메라로 찍었을 때의 촬영 위치 (앨범·공유로 받은 사진은 nil — 원본 사진의 위치 정보를 복사)
    private var captureLocation: CaptureLocation?
    private var widthData: [OutputWidth: Data] = [:]
    private var counts: StitchCounts?
    private var centerFound = false

    init(maxPixelSize: Int, maxOutputSide: Int) {
        session = StitchSession(maxPixelSize: maxPixelSize, maxOutputSide: maxOutputSide)
        let savedMode = UserDefaults.standard.object(forKey: Self.outputModeKey) as? Int
        outputMode = savedMode.flatMap(OutputMode.init(rawValue:)) ?? .fit43
        let savedWidth = UserDefaults.standard.object(forKey: Self.outputWidthKey) as? Int
        outputWidth = savedWidth.flatMap(OutputWidth.init(rawValue:)) ?? .actual
    }

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }
    var hasResult: Bool { !widthData.isEmpty }

    // MARK: 시작·합성

    /// 새 사진들로 합성 시작. 가운데 사진은 자동으로 찾습니다.
    func start(with data: [Data], location: CaptureLocation? = nil) {
        sourceData = data
        captureLocation = location
        centerIndex = nil
        isAutoCenter = true
        thumbnails = data.compactMap { Self.downsample($0, maxPixel: 200) }
        stitch()
    }

    func fail(_ message: String) {
        phase = .failed(message)
    }

    /// 현재 사진·투영 방식으로 (다시) 합성
    func stitch() {
        guard sourceData.count >= 2 else {
            phase = .failed("사진을 2장 이상 선택해 주세요.")
            return
        }
        let data = sourceData
        let projection = projection
        let mode = outputMode
        let session = session
        let chosen: Int? = isAutoCenter ? nil : centerIndex
        phase = .working("\(data.count)장 합성 중…\n(사진 수와 크기에 따라 수십 초 걸릴 수 있습니다)")
        clearResult()

        Task {
            do {
                let (counts, center, results) = try await Task.detached(priority: .userInitiated) {
                    let c = try session.stitch(data, projection: projection)
                    let ci = session.setCenter(chosen)
                    let r = try session.renderAllWidths(mode)
                    return (c, ci, r)
                }.value
                self.counts = counts
                self.apply(center)
                self.show(results)
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// 합성은 그대로 두고 결과 형태(4:3 등)만 바꿔서 세 가지 넓이를 다시 만듭니다.
    func rerender() {
        guard counts != nil, !isWorking else { return }
        let mode = outputMode
        let session = session
        phase = .working("사진 만드는 중…")
        saveMessage = nil
        Task {
            do {
                let results = try await Task.detached(priority: .userInitiated) {
                    try session.renderAllWidths(mode)
                }.value
                self.show(results)
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// 가운데 사진을 바꿉니다. nil = 자동. (합성은 그대로, 자르기만 다시)
    func selectCenter(_ index: Int?) {
        guard counts != nil, !isWorking else { return }
        if index == nil && isAutoCenter { return }
        if let index, !isAutoCenter, index == centerIndex { return }
        isAutoCenter = (index == nil)
        let mode = outputMode
        let session = session
        phase = .working("가운데에 맞추는 중…")
        saveMessage = nil
        Task {
            do {
                let (center, results) = try await Task.detached(priority: .userInitiated) {
                    let ci = session.setCenter(index)
                    let r = try session.renderAllWidths(mode)
                    return (ci, r)
                }.value
                self.apply(center)
                self.show(results)
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// 넓이를 고릅니다 (이미 만들어 둔 결과 중에서 — 바로 바뀜).
    func selectWidth(_ width: OutputWidth) {
        guard widthData[width] != nil else { return }
        outputWidth = width
        saveMessage = nil
        updatePreview()
    }

    // MARK: 결과 표시

    private func clearResult() {
        previewImage = nil
        widthThumbnails = [:]
        widthSizes = [:]
        widthData = [:]
        counts = nil
        saveMessage = nil
        warning = nil
    }

    private func apply(_ center: CenterInfo) {
        centerFound = center.found
        centerIndex = center.index
    }

    private func show(_ results: [OutputWidth: Data]) {
        widthData = results
        var thumbs: [OutputWidth: UIImage] = [:]
        var sizes: [OutputWidth: CGSize] = [:]
        for (w, d) in results {
            if let t = Self.downsample(d, maxPixel: 480) { thumbs[w] = t }
            if let s = Self.pixelSize(d) { sizes[w] = s }
        }
        widthThumbnails = thumbs
        widthSizes = sizes
        updatePreview()
        phase = .done
    }

    private func updatePreview() {
        guard let data = widthData[outputWidth] else { return }
        previewImage = Self.downsample(data, maxPixel: 1400)

        var text = ""
        if let c = counts { text = "\(c.total)장 중 \(c.used)장 합성" }
        if let s = widthSizes[outputWidth] { text += " · \(Int(s.width))×\(Int(s.height))" }
        if let i = centerIndex { text += " · 가운데: \(i + 1)번" + (isAutoCenter ? " (자동)" : "") }
        info = text

        var warnings: [String] = []
        if let c = counts, c.planeFellBack {
            warnings.append("넓게 찍혀서(가운데에서 최대 \(Int(c.maxAngleDegrees.rounded()))°) 평면 대신 원통으로 합성했습니다. 평면은 가운데에서 60° 이내일 때만 됩니다.")
        }
        if !centerFound {
            warnings.append("가운데 기준을 찾지 못해 가장 크게 자르는 방식으로 잘랐습니다.")
        }
        if let c = counts, c.used < c.total {
            warnings.append("\(c.total - c.used)장은 겹치는 부분을 찾지 못해 빠졌습니다.")
        }
        if outputWidth != .actual {
            warnings.append("가장자리 일부는 실제로 찍히지 않은 곳을 주변 색으로 채운 것입니다.")
        }
        warning = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }

    // MARK: 저장

    func save() {
        guard let jpeg = widthData[outputWidth], !isSaving else { return }
        isSaving = true
        saveMessage = nil
        Task {
            do {
                try await PhotoSaver.save(jpeg, location: self.captureLocation)
                self.saveMessage = "사진 앱에 저장했습니다."
            } catch {
                self.saveMessage = error.localizedDescription
            }
            self.isSaving = false
        }
    }

    // MARK: 도움

    /// 이미지 데이터를 maxPixel 이하로 줄여 읽기 (메모리 절약)
    private static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func pixelSize(_ data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: w, height: h)
    }
}
