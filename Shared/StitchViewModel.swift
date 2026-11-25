// StitchViewModel.swift
// 화면 상태 관리. 앱과 공유 확장이 함께 사용합니다.

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
    @Published var projection: Projection = .cylindrical
    @Published var outputMode: OutputMode {
        didSet { UserDefaults.standard.set(outputMode.rawValue, forKey: Self.outputModeKey) }
    }
    @Published private(set) var previewImage: UIImage?
    @Published private(set) var info: String = ""
    @Published private(set) var warning: String?
    @Published var saveMessage: String?
    @Published private(set) var isSaving = false

    private static let outputModeKey = "outputMode"
    private let session: StitchSession
    private var sourceData: [Data] = []
    private var jpegData: Data?
    private var counts: StitchCounts?

    init(maxPixelSize: Int, maxOutputSide: Int) {
        session = StitchSession(maxPixelSize: maxPixelSize, maxOutputSide: maxOutputSide)
        let saved = UserDefaults.standard.object(forKey: Self.outputModeKey) as? Int
        outputMode = saved.flatMap(OutputMode.init(rawValue:)) ?? .fit43
    }

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }
    var hasResult: Bool { jpegData != nil }

    /// 새 사진들로 합성 시작
    func start(with data: [Data]) {
        sourceData = data
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
        phase = .working("\(data.count)장 합성 중…\n(사진 수와 크기에 따라 수십 초 걸릴 수 있습니다)")
        previewImage = nil
        jpegData = nil
        counts = nil
        saveMessage = nil
        warning = nil

        Task {
            do {
                let (counts, jpeg) = try await Task.detached(priority: .userInitiated) {
                    let c = try session.stitch(data, projection: projection)
                    let j = try session.render(mode)
                    return (c, j)
                }.value
                self.counts = counts
                self.show(jpeg)
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// 합성은 그대로 두고 결과 형태(4:3 등)만 바꿔서 다시 만듭니다.
    func rerender() {
        guard counts != nil, !isWorking else { return }
        let mode = outputMode
        let session = session
        phase = .working("사진 만드는 중…")
        saveMessage = nil
        Task {
            do {
                let jpeg = try await Task.detached(priority: .userInitiated) {
                    try session.render(mode)
                }.value
                self.show(jpeg)
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func show(_ jpeg: Data) {
        jpegData = jpeg
        let image = UIImage(data: jpeg)
        previewImage = image
        var text = ""
        if let c = counts { text = "\(c.total)장 중 \(c.used)장 합성" }
        if let image {
            let w = Int(image.size.width * image.scale)
            let h = Int(image.size.height * image.scale)
            text += " · \(w)×\(h)"
        }
        info = text
        if let c = counts, c.used < c.total {
            warning = "\(c.total - c.used)장은 겹치는 부분을 찾지 못해 빠졌습니다."
        } else {
            warning = nil
        }
        phase = .done
    }

    func save() {
        guard let jpeg = jpegData, !isSaving else { return }
        isSaving = true
        saveMessage = nil
        Task {
            do {
                try await PhotoSaver.save(jpeg)
                self.saveMessage = "사진 앱에 저장했습니다."
            } catch {
                self.saveMessage = error.localizedDescription
            }
            self.isSaving = false
        }
    }
}
