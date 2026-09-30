import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ClickportCore

private struct ArgumentField: Identifiable {
    let id = UUID()
    var value: String
}
private struct EnvironmentField: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}

struct ApplicationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entry: ApplicationEntry
    @State private var arguments: [ArgumentField]
    @State private var environment: [EnvironmentField]
    @State private var error: String?
    let save: (ApplicationEntry) -> Bool

    init(entry: ApplicationEntry, save: @escaping (ApplicationEntry) -> Bool) {
        _entry = State(initialValue: entry)
        _arguments = State(initialValue: entry.arguments.map { ArgumentField(value: $0) })
        _environment = State(initialValue: entry.environment.sorted { $0.key < $1.key }.map { EnvironmentField(key: $0.key, value: $0.value) })
        self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑打开方式").font(.title2)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("菜单名称", text: $entry.name)
                    HStack {
                        Text(entry.url.lastPathComponent)
                        Spacer()
                        Button("重新选择应用…") { chooseApplication() }
                    }
                    Text(entry.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Toggle("启用", isOn: $entry.enabled)
                    Toggle("请求启动新实例", isOn: $entry.newInstance)
                    Text("能否启动新实例以及如何处理参数，由目标应用决定。").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("启动参数").font(.headline)
                    Label("当前开发版本暂不支持传递启动参数和环境变量，已填写的配置会保留。", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach($arguments) { $argument in
                        HStack {
                            TextField("参数", text: $argument.value)
                            Button("移除参数") { arguments.removeAll { $0.id == argument.id } }
                        }
                    }
                    Button("添加参数") { arguments.append(ArgumentField(value: "")) }
                    Text("每行是一项参数，空格会保留，无需添加引号。文件和目录另外传递给应用，不执行 Shell 命令。").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("环境变量").font(.headline)
                    ForEach($environment) { $variable in
                        HStack {
                            TextField("变量名", text: $variable.key)
                            SecureField("变量值", text: $variable.value)
                            Button("移除变量") { environment.removeAll { $0.id == variable.id } }
                        }
                    }
                    Button("添加环境变量") { environment.append(EnvironmentField(key: "", value: "")) }
                    Text("值仅保存在本机配置，导出时排除。已运行应用可能不会应用新的启动环境。").font(.caption).foregroundStyle(.secondary)
                }.padding(2)
            }
            if let error { Text(error).foregroundStyle(.red).accessibilityLabel(L10n.format("保存失败：%@", error)) }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { commit() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 580, height: 550)
    }
    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { entry.url = url }
    }
    private func commit() {
        do {
            guard Set(environment.map(\.key)).count == environment.count else {
                throw ConfigurationError.invalid("环境变量名不能重复")
            }
            entry.arguments = arguments.map(\.value)
            entry.environment = Dictionary(uniqueKeysWithValues: environment.map { ($0.key, $0.value) })
            var candidate = Configuration()
            candidate.applications = [entry]
            _ = try candidate.validated()
            if save(entry) { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}

struct DirectoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: DirectoryEntry
    let save: (DirectoryEntry) -> Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑目录快捷入口").font(.title2)
            TextField("菜单名称", text: $entry.name)
            Text(entry.url.path).font(.caption).textSelection(.enabled)
            Button("重新选择目录…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false; panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url { entry.url = url }
            }
            Toggle("启用", isOn: $entry.enabled)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { if save(entry) { dismiss() } }
                    .disabled(entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 500)
    }
}

struct TemplateNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: TemplateEntry
    let save: (TemplateEntry) -> Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑模板名称").font(.title2)
            TextField("菜单名称", text: $entry.name)
            Text(L10n.format("文件类型：.%@", entry.fileExtension)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { if save(entry) { dismiss() } }
                    .disabled(entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 460)
    }
}
