// ContentView.swift
// 앱 첫 화면 = 촬영 화면(CameraScreen).
// AlbumStitchView: 사진 보관함(기본 카메라로 찍은 사진)에서 2~12장을 골라 합성하는 화면.

import PhotosUI
import SwiftUI

struct ContentView: View {
    var body: some View {
        CameraScreen()
    }
}

/// 앨범에서 골라 합성 (촬영 화면의 [앨범에서 합성] 버튼)
struct AlbumStitchView: View {
    // 앱 본체는 메모리 여유가 있어 더 크게 합성합니다.
    @StateObject private var model = StitchViewModel(maxPixelSize: 2400, maxOutputSide: 6000)
    @State private var selection: [PhotosPickerItem] = []
    @State private var showGuide = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PhotosPicker(selection: $selection,
                                 maxSelectionCount: 12,
                                 selectionBehavior: .ordered,
                                 matching: .images,
                                 preferredItemEncoding: .current) {
                        Label("사진 선택 (2~12장)", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isWorking)

                    StitchPanel(model: model)
                }
                .padding()
            }
            .navigationTitle("앨범에서 합성")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showGuide = true } label: { Image(systemName: "questionmark.circle") }
                }
            }
            .sheet(isPresented: $showGuide) { GuideView() }
            .onChange(of: selection) {
                let items = selection
                Task { await load(items) }
            }
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        guard items.count >= 2 else {
            model.fail("사진을 2장 이상 선택해 주세요.")
            return
        }
        model.phase = .working("사진 불러오는 중…")
        var data: [Data] = []
        for item in items {
            if let d = try? await item.loadTransferable(type: Data.self) {
                data.append(d)
            }
        }
        model.start(with: data)
    }
}

/// 촬영 요령
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("앱으로 촬영 (추천)") {
                    Text("1. 아래 [합성] 모드를 고르고, 오른쪽 아래에서 칸 배치(예: 2줄 × 4장)를 고릅니다.\n2. 본건을 가운데 원에 두고 [시작]을 누릅니다. 이때 노출·초점이 고정됩니다.\n3. 노란 원을 가운데 원에 맞추면 초록색이 됩니다. 그때 셔터를 누릅니다.\n4. 마지막 장을 찍으면 바로 합성 결과가 열립니다.")
                    Text("순서: 윗줄 왼쪽 → 오른쪽, 아랫줄 오른쪽 → 왼쪽 ('ㄹ' 자). 왼쪽 위 칸 지도에 표시됩니다.")
                        .font(.caption)
                }
                Section("꼭 지킬 것") {
                    Label("제자리에 서서 몸(폰)만 돌리기", systemImage: "figure.stand")
                    Label("폰은 세로로 들기", systemImage: "iphone")
                    Label("가까운 물체(전봇대, 차량)는 경계에서 어긋날 수 있음", systemImage: "exclamationmark.triangle")
                }
                Section("1장 촬영") {
                    Text("[1장] 모드에서 셔터를 누르면 바로 사진 앱에 저장됩니다. 촬영 위치도 함께 기록됩니다.")
                }
                Section("밤에는") {
                    Text("기본 카메라의 야간 모드는 이 앱에서 쓸 수 없습니다. 밤에는 기본 카메라로 찍고, [앨범에서 합성] 또는 사진 앱 → 공유 → '주위환경 합성'으로 합성하세요.")
                }
                Section("결과가 이상할 때") {
                    Text("• 경계가 어긋나면: 가까운 물체를 피하고 다시 찍기\n• 일부 사진이 빠지면: 겹침을 더 크게\n• 평면이 원통으로 바뀌면: 너무 넓게 찍은 것 — 칸 수를 줄이거나 원통 사용")
                }
            }
            .navigationTitle("촬영 요령")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } }
            }
        }
    }
}
