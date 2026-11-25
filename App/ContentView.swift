// ContentView.swift (앱 본체 화면)
// 사진 보관함에서 2~12장을 골라 합성합니다.
// 공유 확장이 메모리 부족으로 실패할 때도 이 화면에서는 더 큰 해상도로 합성할 수 있습니다.

import PhotosUI
import SwiftUI

struct ContentView: View {
    // 앱 본체는 메모리 여유가 있어 더 크게 합성합니다.
    @StateObject private var model = StitchViewModel(maxPixelSize: 2400, maxOutputSide: 6000)
    @State private var selection: [PhotosPickerItem] = []
    @State private var showGuide = false

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
            .navigationTitle("주위환경 합성")
            .toolbar {
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
                Section("촬영 순서 (2줄 × 4장 예시)") {
                    Text("윗줄: 1 → 2 → 3 → 4 (폰을 약간 위로)\n아랫줄: 5 → 6 → 7 → 8 (폰을 약간 아래로)")
                        .font(.body.monospaced())
                }
                Section("꼭 지킬 것") {
                    Label("제자리에 서서 몸(폰)만 돌리며 찍기", systemImage: "figure.stand")
                    Label("옆 사진·위아래 사진과 30% 이상 겹치기", systemImage: "square.on.square")
                    Label("모든 사진을 같은 배율(1x)로", systemImage: "camera.aperture")
                    Label("첫 장 전에 화면을 길게 눌러 노출·초점 고정 (AE/AF 잠금)", systemImage: "lock")
                }
                Section("사용 방법") {
                    Text("사진 앱에서 사진 여러 장 선택 → 공유 → 'Surround Shot' (주위환경 합성)\n또는 이 앱에서 '사진 선택'")
                }
                Section("결과가 이상할 때") {
                    Text("• 경계가 어긋나면: 가까운 물체(전봇대, 차량)를 피하고 다시 찍기\n• 일부 사진이 빠지면: 겹침을 더 크게\n• 공유 메뉴에서 갑자기 닫히면: 이 앱에서 합성 (메모리 여유가 더 큼)")
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
