import SwiftUI
import ClickportCore

struct OperationFailureList: View {
    @Environment(\.dismiss) private var dismiss
    let failures: [BatchResult.Failure]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.format("未完成的项目 · %@ 项", String(failures.count))).font(.title2)
            List(Array(failures.enumerated()), id: \.offset) { _, failure in
                VStack(alignment: .leading, spacing: 4) {
                    Text(failure.url.lastPathComponent).font(.headline)
                    Text(failure.url.path).font(.caption).foregroundStyle(.secondary)
                    Text(failure.message).font(.caption)
                }.textSelection(.enabled)
            }
            HStack {
                Text("此列表仅在本次运行中显示，不写入诊断日志。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 620, height: 460)
    }
}
