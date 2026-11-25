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
