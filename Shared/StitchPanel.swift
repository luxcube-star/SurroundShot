// StitchPanel.swift
// 합성 설정·진행 상태·결과 미리보기·저장 버튼 화면. 앱과 공유 확장이 함께 사용합니다.

import SwiftUI

struct StitchPanel: View {
    @ObservedObject var model: StitchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("결과 형태").font(.subheadline.weight(.semibold))
                Picker("결과 형태", selection: $model.outputMode) {
                    ForEach(OutputMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(model.isWorking)
                Text(model.outputMode.detail).font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("투영 방식").font(.subheadline.weight(.semibold))
                Picker("투영 방식", selection: $model.projection) {
                    ForEach(Projection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(model.isWorking)
                Text(model.projection.detail).font(.caption).foregroundStyle(.secondary)
            }

            if model.hasResult {
                widthPicker
            }

            if model.thumbnails.count >= 2 {
                centerPicker
            }

            Divider()

            content
        }
        .onChange(of: model.outputMode) {
            model.rerender()
        }
        .onChange(of: model.projection) {
            if model.hasResult || isFailed { model.stitch() }
        }
    }

    /// 넓이 고르기: 세 결과를 나란히 보여 주고, 누르면 아래 큰 미리보기가 바뀝니다.
    private var widthPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("넓이").font(.subheadline.weight(.semibold))
            HStack(alignment: .top, spacing: 10) {
                ForEach(OutputWidth.allCases) { w in
                    let selected = model.outputWidth == w
                    Button { model.selectWidth(w) } label: {
                        VStack(spacing: 4) {
                            Group {
                                if let t = model.widthThumbnails[w] {
                                    Image(uiImage: t).resizable().scaledToFill()
                                } else {
                                    Color.secondary.opacity(0.15)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(4.0 / 3.0, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(selected ? Color.yellow : .clear, lineWidth: 3))
                            Text(w.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selected ? Color.yellow : .primary)
                            if let s = model.widthSizes[w] {
                                Text("\(Int(s.width))×\(Int(s.height))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .disabled(model.isWorking)
            Text("넓게·더 넓게는 가장자리의 찍히지 않은 곳을 주변 색으로 채워 배경을 더 담습니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// 가운데 사진 고르기: 누른 사진이 결과의 정중앙에 옵니다.
    private var centerPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("가운데 사진").font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { model.selectCenter(nil) } label: {
                        Text("자동")
                            .font(.caption.weight(.semibold))
                            .frame(width: 56, height: 56)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(model.isAutoCenter ? Color.yellow : .clear, lineWidth: 3))
                    }
                    ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { i, img in
                        Button { model.selectCenter(i) } label: {
                            ZStack(alignment: .topLeading) {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text("\(i + 1)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                                    .padding(2)
                            }
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(model.centerIndex == i ? Color.yellow : .clear, lineWidth: 3))
                        }
                    }
                }
                .padding(.vertical, 3)
            }
            .disabled(model.isWorking)
            Text(centerCaption)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var centerCaption: String {
        if model.isAutoCenter {
            if let i = model.centerIndex {
                return "자동: 위치를 보고 \(i + 1)번 사진을 가운데 사진으로 찾았습니다. 다른 사진을 누르면 바꿀 수 있습니다."
            }
            return "자동: 가운데 사진이 따로 없어, 모든 사진의 한가운데를 정중앙에 둡니다."
        }
        return "노란 테두리 사진이 결과의 정중앙에 옵니다. '자동'을 누르면 다시 자동으로 찾습니다."
    }

    private var isFailed: Bool {
        if case .failed = model.phase { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            EmptyView()

        case .working(let message):
            HStack(spacing: 12) {
                ProgressView()
                Text(message).font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label("합성 실패", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.headline)
                Text(message).font(.callout)
                Button("다시 시도") { model.stitch() }
                    .buttonStyle(.bordered)
            }

        case .done:
            VStack(alignment: .leading, spacing: 10) {
                if let image = model.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .border(Color.secondary.opacity(0.4))
                }
                Text(model.info).font(.caption).foregroundStyle(.secondary)
                if let warning = model.warning {
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button {
                    model.save()
                } label: {
                    if model.isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("사진 앱에 저장", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isSaving)

                if let message = model.saveMessage {
                    Text(message).font(.callout)
                }
            }
        }
    }
}
