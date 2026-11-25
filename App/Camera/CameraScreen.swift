// CameraScreen.swift
// 앱을 열면 뜨는 촬영 화면. [1장] / [합성] 모드, 배율, 합성 칸 안내.

import AVFoundation
import SwiftUI

struct CameraScreen: View {
    @StateObject private var model = CaptureModel()
    @State private var showAlbum = false
    @State private var showGuide = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                topBar
                previewArea
                bottomControls
            }
            .padding(.bottom, 8)

            if let toast = model.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 200)
                }
                .padding(.horizontal, 24)
                .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .task { await model.setup() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { model.resume() } else if scenePhase == .background { model.pause() }
        }
        .sheet(isPresented: $showAlbum) { AlbumStitchView() }
        .sheet(isPresented: $showGuide) { GuideView() }
        .sheet(isPresented: $model.showResult) {
            if let vm = model.resultModel { StitchResultSheet(model: vm) }
        }
    }

    // MARK: 위

    private var topBar: some View {
        HStack {
            Button {
                showAlbum = true
            } label: {
                Label("앨범에서 합성", systemImage: "photo.on.rectangle.angled")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(model.phase == .shooting)
            Spacer()
            if model.location.latest != nil {
                Image(systemName: "location.fill").font(.caption).foregroundStyle(.green)
            }
            Button { showGuide = true } label: { Image(systemName: "questionmark.circle") }
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: 미리보기

    private var previewArea: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height * 3 / 4)
            let h = w * 4 / 3
            ZStack {
                if model.cameraReady {
                    CameraPreview(session: model.camera.session)
                } else if let error = model.cameraError {
                    Text(error).foregroundStyle(.white).multilineTextAlignment(.center).padding()
                } else {
                    ProgressView().tint(.white)
                }
                if model.mode == .stitch && model.cameraReady {
                    StitchOverlay(model: model, motion: model.motion, size: CGSize(width: w, height: h))
                }
            }
            .frame(width: w, height: h)
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: 아래

    private var bottomControls: some View {
        VStack(spacing: 14) {
            // 배율
            HStack(spacing: 10) {
                ForEach(model.zoomOptions, id: \.self) { z in
                    Button { model.setZoom(z) } label: {
                        Text(z == 0.5 ? ".5×" : "\(Int(z))×")
                            .font(.footnote.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.white.opacity(model.zoom == z ? 0.3 : 0.12)))
                            .foregroundStyle(model.zoom == z ? .yellow : .white)
                    }
                    .disabled(model.phase == .shooting)
                }
            }

            // 모드
            HStack(spacing: 28) {
                ForEach(CaptureMode.allCases) { m in
                    Button { model.mode = m } label: {
                        Text(m.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(model.mode == m ? .yellow : .white.opacity(0.8))
                    }
                    .disabled(model.phase == .shooting)
                }
            }

            // 셔터 줄
            HStack {
                leftControl.frame(width: 80)
                Spacer()
                shutterButton
                Spacer()
                rightControl.frame(width: 80)
            }
            .padding(.horizontal, 24)
        }
    }

    private var shutterButton: some View {
        Button { model.shutter() } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 74, height: 74)
                Circle().fill(model.isCapturing ? .gray : .white).frame(width: 62, height: 62)
                if model.mode == .stitch && model.phase == .aiming {
                    Text("시작").font(.headline).foregroundStyle(.black)
                } else if model.mode == .stitch {
                    Text("\(model.shotCount + 1)/\(model.grid.count)")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.black)
                }
            }
        }
        .disabled(!model.cameraReady || model.isCapturing)
    }

    @ViewBuilder
    private var leftControl: some View {
        if model.mode == .stitch && model.phase == .shooting {
            Button { model.undoLast() } label: {
                VStack(spacing: 2) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("한 장 취소").font(.caption2)
                }
            }
            .foregroundStyle(.white)
            .disabled(model.shotCount == 0)
        } else if let thumb = model.lastThumbnail {
            Image(uiImage: thumb)
                .resizable().scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Color.clear.frame(width: 48, height: 48)
        }
    }

    @ViewBuilder
    private var rightControl: some View {
        if model.mode == .stitch && model.phase == .shooting {
            Button(role: .cancel) { model.cancelStitch() } label: {
                VStack(spacing: 2) {
                    Image(systemName: "xmark")
                    Text("취소").font(.caption2)
                }
            }
            .foregroundStyle(.white)
        } else if model.mode == .stitch {
            Menu {
                Picker("칸 배치", selection: $model.grid) {
                    ForEach(GridPreset.all) { Text($0.title).tag($0) }
                }
                Toggle("원본 사진도 저장", isOn: $model.saveOriginals)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "square.grid.3x2")
                    Text(model.grid.title).font(.caption2)
                }
            }
            .foregroundStyle(.white)
        } else {
            Color.clear.frame(width: 48, height: 48)
        }
    }
}

// MARK: - 합성 칸 안내 (미리보기 위)

private struct StitchOverlay: View {
    @ObservedObject var model: CaptureModel
    @ObservedObject var motion: MotionGuide
    let size: CGSize

    var body: some View {
        ZStack {
            // 가운데 원 (지금 카메라가 보는 곳)
            Circle()
                .stroke(.white, lineWidth: 3)
                .frame(width: 56, height: 56)

            if let t = model.currentTarget {
                let dYaw = t.yaw - motion.yaw
                let dPitch = t.pitch - motion.pitch
                let aligned = abs(dYaw) < model.alignTolerance && abs(dPitch) < model.alignTolerance
                let x = dYaw * size.width / model.portraitHFOV
                let y = -dPitch * size.height / model.portraitVFOV
                let maxX = size.width / 2 - 30
                let maxY = size.height / 2 - 30
                Circle()
                    .fill((aligned ? Color.green : Color.yellow).opacity(0.85))
                    .frame(width: 40, height: 40)
                    .offset(x: min(max(x, -maxX), maxX), y: min(max(y, -maxY), maxY))
                    .animation(.linear(duration: 0.05), value: motion.yaw)

                Text(aligned ? "지금 촬영하세요" : guideText(dYaw: dYaw, dPitch: dPitch))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(aligned ? .green : .white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 12)
            } else if model.phase == .aiming {
                Text("본건을 가운데 원에 두고 [시작]을 누르세요")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 12)
            }

            gridMap
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
        }
        .frame(width: size.width, height: size.height)
    }

    private func guideText(dYaw: Double, dPitch: Double) -> String {
        var parts: [String] = []
        if abs(dYaw) >= model.alignTolerance { parts.append(dYaw > 0 ? "오른쪽으로" : "왼쪽으로") }
        if abs(dPitch) >= model.alignTolerance { parts.append(dPitch > 0 ? "위로" : "아래로") }
        return parts.joined(separator: " · ")
    }

    /// 왼쪽 위 작은 칸 지도: 찍은 칸 ✓, 지금 칸 ●
    private var gridMap: some View {
        let g = model.grid
        return VStack(spacing: 3) {
            ForEach(0..<g.rows, id: \.self) { r in
                HStack(spacing: 3) {
                    ForEach(0..<g.cols, id: \.self) { c in
                        let k = index(row: r, col: c)
                        let done = model.phase == .shooting && k < model.shotCount
                        let current = model.phase == .shooting && k == model.shotCount
                        ZStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(done ? Color.green.opacity(0.8) : current ? Color.yellow.opacity(0.85)
                                      : Color.black.opacity(0.45))
                            Text(done ? "✓" : "\(k + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(current ? .black : .white)
                        }
                        .frame(width: 22, height: 22)
                    }
                }
            }
        }
    }

    private func index(row: Int, col: Int) -> Int {
        let cols = model.grid.cols
        return row * cols + (row % 2 == 0 ? col : cols - 1 - col)
    }
}

// MARK: - 카메라 미리보기

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspect
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if let c = uiView.previewLayer.connection, c.isVideoRotationAngleSupported(90) {
            c.videoRotationAngle = 90  // 앱은 세로 화면 고정
        }
    }
}

// MARK: - 합성 결과 시트

struct StitchResultSheet: View {
    @ObservedObject var model: StitchViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                StitchPanel(model: model).padding()
            }
            .navigationTitle("합성 결과")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() } }
            }
        }
    }
}
