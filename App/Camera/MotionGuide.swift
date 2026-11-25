// MotionGuide.swift
// 기울기 센서로 카메라가 바라보는 방향(좌우·위아래 각도)을 잽니다. 합성 촬영의 칸 안내용.

import CoreMotion
import Foundation

@MainActor
final class MotionGuide: ObservableObject {
    /// 기준 방향 대비 좌우 각도 (오른쪽 +, 도)
    @Published private(set) var yaw: Double = 0
    /// 수평 대비 위아래 각도 (위 +, 도)
    @Published private(set) var pitch: Double = 0
    @Published private(set) var isAvailable = false

    private let manager = CMMotionManager()
    private var absoluteYaw: Double = 0
    private var referenceYaw: Double = 0

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        isAvailable = true
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let reading = MotionGuide.cameraDirection(from: motion)
            MainActor.assumeIsolated { self?.apply(reading) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    /// 지금 바라보는 방향을 좌우 0° 로 삼습니다.
    func setReference() {
        referenceYaw = absoluteYaw
        yaw = 0
    }

    private func apply(_ reading: (yaw: Double, pitch: Double)) {
        absoluteYaw = reading.yaw
        pitch = reading.pitch
        var d = reading.yaw - referenceYaw
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        yaw = -d  // 세계 좌표(z 위)에서 오른쪽으로 돌면 각도가 줄어들므로 부호를 바꿉니다.
    }

    /// 뒷면 카메라가 향하는 방향(기기 좌표 −z)을 세계 좌표의 (좌우 각, 위아래 각)으로.
    /// 회전 행렬이 '세계→기기'인지 '기기→세계'인지 중력 벡터와 맞춰 보고 고릅니다.
    nonisolated static func cameraDirection(from m: CMDeviceMotion) -> (yaw: Double, pitch: Double) {
        let r = m.attitude.rotationMatrix
        let M = [[r.m11, r.m12, r.m13], [r.m21, r.m22, r.m23], [r.m31, r.m32, r.m33]]
        let g = [m.gravity.x, m.gravity.y, m.gravity.z]
        // 세계의 아래쪽 (0,0,−1) 을 기기 좌표로 옮긴 후보 두 가지
        let a = [-M[0][2], -M[1][2], -M[2][2]]  // M 이 세계→기기일 때
        let b = [-M[2][0], -M[2][1], -M[2][2]]  // Mᵀ 가 세계→기기일 때
        func dist2(_ p: [Double], _ q: [Double]) -> Double {
            zip(p, q).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
        }
        // 기기 −z 를 세계 좌표로: M 이 세계→기기면 Mᵀ·(0,0,−1) = b, 아니면 M·(0,0,−1) = a
        let f = dist2(a, g) <= dist2(b, g) ? b : a
        let yaw = atan2(f[1], f[0]) * 180 / .pi
        let pitch = asin(max(-1, min(1, f[2]))) * 180 / .pi
        return (yaw, pitch)
    }
}
