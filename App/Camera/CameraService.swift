// CameraService.swift
// 아이폰 뒷면 카메라 제어 (AVFoundation). 모든 카메라 작업은 전용 큐에서 실행합니다.

import AVFoundation
import UIKit

nonisolated struct CameraInfo: Sendable {
    /// 화면에 보여 줄 배율 (예: 0.5, 1, 2)
    let zoomOptions: [Double]
    /// 1× (광각 렌즈) 의 가로 화각 — 카메라를 가로로 눕혔을 때 기준, 도 단위
    let wideFieldOfViewDegrees: Double
}

nonisolated enum CameraError: LocalizedError {
    case denied
    case unavailable
    case noData

    var errorDescription: String? {
        switch self {
        case .denied:
            return "카메라 권한이 없습니다.\n설정 > 개인정보 보호 및 보안 > 카메라에서 이 앱을 허용해 주세요."
        case .unavailable:
            return "카메라를 사용할 수 없습니다."
        case .noData:
            return "사진 데이터를 만들지 못했습니다."
        }
    }
}

nonisolated final class CameraService: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private(set) var device: AVCaptureDevice?

    private let queue = DispatchQueue(label: "kr.koh0001.surroundshot.camera")
    private let output = AVCapturePhotoOutput()
    private let lock = NSLock()
    private var pending: [Int64: CheckedContinuation<Data, Error>] = [:]
    private var configured = false
    /// 화면 배율 1× 에 해당하는 장치 줌 값 (초광각이 있는 기기는 보통 2)
    private var wideZoomFactor: Double = 1

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func configure() async throws -> CameraInfo {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CameraInfo, Error>) in
            queue.async {
                do { cont.resume(returning: try self.configureOnQueue()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    private func configureOnQueue() throws -> CameraInfo {
        if !configured {
            let types: [AVCaptureDevice.DeviceType] = [
                .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
            ]
            guard let d = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video,
                                                           position: .back).devices.first
            else { throw CameraError.unavailable }

            session.beginConfiguration()
            session.sessionPreset = .photo
            let input = try AVCaptureDeviceInput(device: d)
            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                throw CameraError.unavailable
            }
            session.addInput(input)
            session.addOutput(output)
            output.maxPhotoQualityPrioritization = .quality
            session.commitConfiguration()
            device = d
            configured = true
        }
        guard let d = device else { throw CameraError.unavailable }

        // 초광각이 있는 기기(트리플·듀얼와이드)는 장치 줌 1 = 0.5×, 전환점(보통 2) = 1×
        let hasUltraWide = d.deviceType == .builtInTripleCamera || d.deviceType == .builtInDualWideCamera
        wideZoomFactor = hasUltraWide ? (d.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue ?? 2) : 1

        var options: [Double] = []
        if hasUltraWide { options.append(0.5) }
        options.append(1)
        if wideZoomFactor * 2 <= Double(d.maxAvailableVideoZoomFactor) { options.append(2) }

        // 1× 화각: 구성 카메라 중 광각 렌즈의 화각 (없으면 장치 자체)
        let wideDevice = d.constituentDevices.first { $0.deviceType == .builtInWideAngleCamera } ?? d
        var fov = Double(wideDevice.activeFormat.videoFieldOfView)
        if !(40...90).contains(fov) { fov = 70 }  // 비정상 값 방어 (아이폰 1× ≈ 70°)

        setZoomOnQueue(1)
        return CameraInfo(zoomOptions: options, wideFieldOfViewDegrees: fov)
    }

    func start() {
        queue.async { if !self.session.isRunning { self.session.startRunning() } }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    /// 화면 배율(0.5, 1, 2 …)로 줌
    func setZoom(display zoom: Double) {
        queue.async { self.setZoomOnQueue(zoom) }
    }

    private func setZoomOnQueue(_ zoom: Double) {
        guard let d = device else { return }
        let f = min(max(zoom * wideZoomFactor, Double(d.minAvailableVideoZoomFactor)),
                    Double(d.maxAvailableVideoZoomFactor))
        do {
            try d.lockForConfiguration()
            d.videoZoomFactor = CGFloat(f)
            d.unlockForConfiguration()
        } catch {}
    }

    /// 노출·초점·화이트밸런스 고정(합성 촬영 중) / 해제
    func setLocked(_ locked: Bool) {
        queue.async {
            guard let d = self.device else { return }
            do {
                try d.lockForConfiguration()
                if locked {
                    if d.isExposureModeSupported(.locked) { d.exposureMode = .locked }
                    if d.isFocusModeSupported(.locked) { d.focusMode = .locked }
                    if d.isWhiteBalanceModeSupported(.locked) { d.whiteBalanceMode = .locked }
                } else {
                    if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
                    if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
                    if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        d.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                }
                d.unlockForConfiguration()
            } catch {}
        }
    }

    /// 사진 한 장 촬영 → HEIC(지원 안 하면 JPEG) 데이터
    /// - Parameter rotationAngle: 사진 회전 각도 (세로로 들고 찍으면 90)
    func capture(rotationAngle: Double, highQuality: Bool) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            queue.async {
                let settings: AVCapturePhotoSettings
                if self.output.availablePhotoCodecTypes.contains(.hevc) {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                } else {
                    settings = AVCapturePhotoSettings()
                }
                settings.photoQualityPrioritization = highQuality ? .quality : .balanced
                if let c = self.output.connection(with: .video),
                   c.isVideoRotationAngleSupported(CGFloat(rotationAngle)) {
                    c.videoRotationAngle = CGFloat(rotationAngle)
                }
                self.lock.withLock { self.pending[settings.uniqueID] = cont }
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    // MARK: AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: (any Error)?) {
        let cont = lock.withLock { pending.removeValue(forKey: photo.resolvedSettings.uniqueID) }
        if let error {
            cont?.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation() {
            cont?.resume(returning: data)
        } else {
            cont?.resume(throwing: CameraError.noData)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: (any Error)?) {
        // 사진 처리 콜백 없이 끝난 경우(오류)에도 기다리는 쪽을 깨웁니다.
        let cont = lock.withLock { pending.removeValue(forKey: resolvedSettings.uniqueID) }
        cont?.resume(throwing: error ?? CameraError.noData)
    }
}
