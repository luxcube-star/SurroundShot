// ShareViewController.swift (공유 확장)
// 사진 앱에서 여러 장 선택 → 공유 → 'Surround Shot' 을 누르면 이 화면이 뜹니다.
// 공유 확장은 메모리 제한이 앱보다 엄격하므로 작게 줄여서 합성합니다.

import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let model = StitchViewModel(maxPixelSize: 1200, maxOutputSide: 3000)

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareRootView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)

        Task { await loadInputs() }
    }

    private func loadInputs() async {
        model.phase = .working("사진 불러오는 중…")
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }

        var data: [Data] = []
        for provider in providers {
            if let d = await loadData(provider) { data.append(d) }
        }
        guard data.count >= 2 else {
            model.fail("사진을 2장 이상 선택해 주세요.")
            return
        }
        model.start(with: data)
    }

    private func loadData(_ provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

struct ShareRootView: View {
    @ObservedObject var model: StitchViewModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                StitchPanel(model: model).padding()
            }
            .navigationTitle("주위환경 합성")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기", action: onClose)
                }
            }
        }
    }
}
