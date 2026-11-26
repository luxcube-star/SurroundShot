// CaptureModel.swift
// 촬영 화면의 상태: 1장 / 합성 모드, 배율, 합성 칸 안내, 촬영·저장.

import AVFoundation
import SwiftUI
import UIKit

enum CaptureMode: String, CaseIterable, Identifiable {
    case single
    case stitch

    var id: String { rawValue }
    var title: String { self == .single ? "1장" : "합성" }
}

/// 합성 촬영 칸 배치 (줄 × 장)
struct GridPreset: Hashable, Identifiable {
    let rows: Int
    let cols: Int

    var id: String { "\(rows)x\(cols)" }
    var count: Int { rows * cols }
    var title: String { "\(rows)줄 × \(cols)장" }

    static let all: [GridPreset] = [
        GridPreset(rows: 1, cols: 3), GridPreset(rows: 1, cols: 4),
        GridPreset(rows: 2, cols: 2), GridPreset(rows: 2, cols: 3), GridPreset(rows: 2, cols: 4),
    ]
    static let standard = GridPreset(rows: 2, cols: 4)
}

@MainActor
final class CaptureModel: ObservableObject {
    enum StitchPhase: Equatable {
        case aiming    // [시작] 전: 본건을 가운데 맞추는 중
        case shooting  // 칸 안내에 따라 촬영 중
    }

    // 화면 상태
    @Published var mode: CaptureMode = .single
    @Published var grid: GridPreset {
        didSet { UserDefaults.standard.set(grid.id, forKey: Keys.grid) }
    }
    @Published var saveOriginals: Bool {
        didSet { UserDefaults.standard.set(saveOriginals, forKey: Keys.saveOriginals) }
    }
    @Published private(set) var zoom: Double = 1
    @Published private(set) var zoomOptions: [Double] = [1]
    @Published private(set) var cameraReady = false
    @Published private(set) var cameraError: String?
    @Published private(set) var phase: StitchPhase = .aiming
    @Published private(set) var shotCount = 0
    @Published private(set) var isCapturing = false
    @Published private(set) var lastThumbnail: UIImage?
    @Published var toast: String?

    // 합성 결과 화면
    @Published var showResult = false
    @Published private(set) var resultModel: StitchViewModel?

    let camera = CameraService()
    let motion = MotionGuide()
    let location = LocationProvider()

    /// 옆 칸과 겹치게 할 비율
    let overlap = 0.35
    /// 이 각도 안으로 들어오면 '맞음'(초록)
    let alignTolerance = 3.0

    private var shots: [Data] = []
    private var wideFOV: Double = 70
    private var referencePitch: Double = 0
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var didSetup = false

    private enum Keys {
        static let grid = "captureGrid"
        static let saveOriginals = "captureSaveOriginals"
    }

    init() {
        let savedGrid = UserDefaults.standard.string(forKey: Keys.grid)
        grid = GridPreset.all.first { $0.id == savedGrid } ?? .standard
        saveOriginals = UserDefaults.standard.bool(forKey: Keys.saveOriginals)
    }

    // MARK: 시작·정지

    func setup() async {
        guard !didSetup else { resume(); return }
        guard await CameraService.requestAccess() else {
            cameraError = CameraError.denied.errorDescription
            return
        }
        do {
            let info = try await camera.configure()
            zoomOptions = info.zoomOptions
            wideFOV = info.wideFieldOfViewDegrees
            if let d = camera.device {
                rotation = AVCaptureDevice.RotationCoordinator(device: d, previewLayer: nil)
            }
            didSetup = true
            camera.start()
            cameraReady = true
        } catch {
            cameraError = error.localizedDescription
            return
        }
        motion.start()
        location.start()
    }

    func resume() {
        guard didSetup else { return }
        camera.start()
        motion.start()
        location.start()
    }

    func pause() {
        camera.stop()
        motion.stop()
        location.stop()
    }

    // MARK: 배율

    func setZoom(_ z: Double) {
        guard phase == .aiming else { return }
        zoom = z
        camera.setZoom(display: z)
    }

    // MARK: 화각 (세로로 들고 찍을 때)

    /// 지금 배율의 가로 화각 — 카메라를 가로로 눕혔을 때 기준
    private var landscapeHFOV: Double {
        let half = wideFOV / 2 * .pi / 180
        return 2 * atan(tan(half) / zoom) * 180 / .pi
    }

    /// 세로로 든 사진의 가로 화각 (4:3 사진의 짧은 변)
    var portraitHFOV: Double {
        let half = landscapeHFOV / 2 * .pi / 180
        return 2 * atan(tan(half) * 3 / 4) * 180 / .pi
    }

    /// 세로로 든 사진의 세로 화각
    var portraitVFOV: Double { landscapeHFOV }

    // MARK: 합성 칸 안내

    /// k 번째 사진의 칸 (줄, 칸). 윗줄은 왼→오, 아랫줄은 오→왼 (몸을 되돌리지 않게 'ㄹ' 자 순서)
    func cell(for k: Int) -> (row: Int, col: Int) {
        let row = k / grid.cols
        let i = k % grid.cols
        return (row, row % 2 == 0 ? i : grid.cols - 1 - i)
    }

    /// k 번째 사진을 찍을 방향 (좌우 각, 위아래 각) — [시작] 때 방향이 전체의 가운데
    func target(for k: Int) -> (yaw: Double, pitch: Double) {
        let (r, c) = cell(for: k)
        let stepH = portraitHFOV * (1 - overlap)
        let stepV = portraitVFOV * (1 - overlap)
        let yaw = (Double(c) - Double(grid.cols - 1) / 2) * stepH
        let pitch = referencePitch + (Double(grid.rows - 1) / 2 - Double(r)) * stepV
        return (yaw, pitch)
    }

    var currentTarget: (yaw: Double, pitch: Double)? {
        guard mode == .stitch, phase == .shooting, shotCount < grid.count else { return nil }
        return target(for: shotCount)
    }

    // MARK: 셔터

    func shutter() {
        guard cameraReady, !isCapturing else { return }
        switch mode {
        case .single:
            Task { await captureSingle() }
        case .stitch:
            if phase == .aiming {
                beginStitch()
            } else {
                Task { await captureStitchShot() }
            }
        }
    }

    private func beginStitch() {
        referencePitch = motion.pitch
        motion.setReference()
        camera.setLocked(true)
        shots = []
        shotCount = 0
        phase = .shooting
        show("노출·초점을 고정했습니다. 노란 원을 가운데 원에 맞추고 촬영하세요.")
    }

    /// 합성 촬영 중 마지막 한 장 취소
    func undoLast() {
        guard phase == .shooting, !shots.isEmpty, !isCapturing else { return }
        shots.removeLast()
        shotCount = shots.count
    }

    /// 합성 촬영 전체 취소
    func cancelStitch() {
        shots = []
        shotCount = 0
        phase = .aiming
        camera.setLocked(false)
    }

    private var captureAngle: Double {
        Double(rotation?.videoRotationAngleForHorizonLevelCapture ?? 90)
    }

    private func captureSingle() async {
        isCapturing = true
        defer { isCapturing = false }
        do {
            let data = try await camera.capture(rotationAngle: captureAngle, highQuality: true)
            lastThumbnail = Self.thumbnail(data)
            try await PhotoSaver.save(data, location: location.latest)
            show("사진 앱에 저장했습니다.")
        } catch {
            show(error.localizedDescription)
        }
    }

    private func captureStitchShot() async {
        isCapturing = true
        defer { isCapturing = false }
        if captureAngle != 90 {
            show("합성 촬영은 폰을 세로로 들고 찍어 주세요.")
        }
        do {
            // 합성용은 칸 안내 방향(세로)에 맞춰 항상 세로로 저장
            let data = try await camera.capture(rotationAngle: 90, highQuality: false)
            shots.append(data)
            shotCount = shots.count
            lastThumbnail = Self.thumbnail(data)
            if shots.count >= grid.count {
                finishStitch()
            }
        } catch {
            show(error.localizedDescription)
        }
    }

    private func finishStitch() {
        let data = shots
        let loc = location.latest
        camera.setLocked(false)
        shots = []
        shotCount = 0
        phase = .aiming

        if saveOriginals {
            Task {
                for d in data { try? await PhotoSaver.save(d, location: loc) }
            }
        }
        let vm = StitchViewModel(maxPixelSize: 2400, maxOutputSide: 6000)
        vm.start(with: data, location: loc)
        resultModel = vm
        showResult = true
    }

    // MARK: 도움

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast == message { toast = nil }
        }
    }

    private static func thumbnail(_ data: Data) -> UIImage? {
        UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 120, height: 160))
    }
}
