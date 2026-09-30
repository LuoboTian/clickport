import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ServiceManagement
import ClickportCore

struct SettingsRoot: View {
    @Bindable var model: AppModel
    @State private var selection: String? = "通用"
    @State private var draft = MenuCustomization()
    @State private var resetConfirmation = false
    @State private var resetMenuConfirmation = false
    @State private var showingFailures = false
    @State private var editingApplication: ApplicationEntry?
    @State private var editingDirectory: DirectoryEntry?
    @State private var editingTemplate: TemplateEntry?
    private let sections = ["通用", "打开方式", "文件操作", "新建文件", "目录快捷入口", "右键菜单", "关于"]
    private let actionNames: [BuiltinAction: String] = [.copyPath: "复制路径", .hide: "隐藏选中项", .unhide: "取消隐藏选中项", .unhideChildren: "显示目录中的隐藏项目", .airDrop: "隔空投送", .deletePermanently: "永久删除"]
    private let groupNames: [MenuGroup: String] = [.applications: "打开方式", .templates: "新建文件", .operations: "文件操作", .directories: "目录快捷入口"]
    private let sectionSymbols = ["通用": "gearshape", "打开方式": "app", "文件操作": "doc.on.doc",
                                  "新建文件": "doc.badge.plus", "目录快捷入口": "folder",
                                  "右键菜单": "cursorarrow.click", "关于": "info.circle"]
    var body: some View {
        NavigationSplitView {
            List(sections, id: \.self, selection: $selection) { section in
                Label(L10n.text(section), systemImage: sectionSymbols[section] ?? "gearshape")
            }
                .navigationSplitViewColumnWidth(180)
        } detail: {
            Form {
                switch selection {
                case "通用": general
                case "打开方式": applications
                case "文件操作": operations
                case "新建文件": templates
                case "目录快捷入口": directories
                case "右键菜单": menu
                default: about
                }
                if model.processing {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(L10n.text(model.progressMessage))
                        Spacer()
                        Button("停止后续操作") { model.cancelOperation() }
                    }
                }
                if !model.resultMessage.isEmpty { Text(L10n.text(model.resultMessage)).font(.caption).foregroundStyle(.secondary) }
                if !model.operationFailures.isEmpty {
                    Button(L10n.format("查看全部失败项目（%@）…", String(model.operationFailures.count))) { showingFailures = true }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L10n.text(selection ?? "设置"))
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { draft = MenuCustomization(configuration: model.configuration) }
        .onChange(of: model.configuration) { _, current in draft.reconcile(with: current) }
        .sheet(isPresented: $showingFailures) { OperationFailureList(failures: model.operationFailures) }
        .sheet(item: $editingApplication) { entry in
            ApplicationEditor(entry: entry) { edited in
                model.errorMessage = nil
                update { config in
                    if let index = config.applications.firstIndex(where: { $0.id == edited.id }) { config.applications[index] = edited }
                }
                return model.errorMessage == nil
            }
        }
        .sheet(item: $editingTemplate) { entry in
            TemplateNameEditor(entry: entry) { edited in
                var config = model.configuration
                if let index = config.templates.firstIndex(where: { $0.id == edited.id }) { config.templates[index].name = edited.name }
                return model.save(config)
            }
        }
        .sheet(item: $editingDirectory) { entry in
            DirectoryEditor(entry: entry) { edited in
                model.errorMessage = nil
                update { config in
                    if let index = config.directories.firstIndex(where: { $0.id == edited.id }) { config.directories[index] = edited }
                }
                return model.errorMessage == nil
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("恢复默认设置？", isPresented: $resetConfirmation) {
            Button("恢复默认设置", role: .destructive) {
                if model.resetSettings() { draft = MenuCustomization(configuration: model.configuration) }
            }
        } message: { Text("将恢复通用选项和操作开关，关闭登录启动，清除自定义应用、目录和模板引用。个人文件和已保存的目录授权将保留。") }
        .confirmationDialog("恢复默认菜单？", isPresented: $resetMenuConfirmation) {
            Button("恢复默认菜单") {
                var next = model.configuration
                next.groups = MenuGroup.allCases
                next.shortcuts = [.builtin(.copyPath)]
                if model.save(next) { draft = MenuCustomization(configuration: model.configuration) }
            }
        } message: { Text("将恢复菜单分组顺序和复制路径快捷入口，替换当前未保存的菜单更改。应用、模板和目录列表会保留。") }
    }
    private func update(_ change: (inout Configuration) -> Void) {
        var next = model.configuration; change(&next); model.save(next)
    }
    private var general: some View {
        Group {
            Section("启动与入口") {
                Toggle("登录时启动", isOn: Binding(
                    get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval },
                    set: { model.setLoginItem($0) }
                ))
                Text(L10n.text(model.loginStatusText)).font(.caption).foregroundStyle(.secondary)
                if model.loginStatus == .requiresApproval {
                    Button("打开系统登录项设置…") { SMAppService.openSystemSettingsLoginItems() }
                }
                Toggle("显示菜单栏图标", isOn: Binding(get: { model.configuration.showMenuBar }, set: { value in update { $0.showMenuBar = value } }))
                Text("隐藏后，重新运行应用可打开设置。").font(.caption).foregroundStyle(.secondary)
            }
            Section("扩展状态") {
                LabeledContent("Finder 扩展", value: L10n.text(model.extensionEnabled ? "已启用" : "未启用"))
                Button("管理 Finder 扩展…") { model.manageExtension() }
            }
            Section("目录访问授权") {
                if let error = model.directoryAccess.loadError { Text(error).foregroundStyle(.red) }
                ForEach(model.directoryAccess.grants) { grant in
                    DirectoryGrantRow(grant: grant, access: model.directoryAccess, isBusy: model.processing) {
                        model.errorMessage = $0.localizedDescription
                    }
                }
                Button("添加授权目录…") {
                    do { try model.directoryAccess.chooseDirectory() }
                    catch { model.errorMessage = error.localizedDescription }
                }.disabled(model.processing)
                Text("授权只保存在本机，不随配置导出。撤销后再次操作该目录会重新请求；系统隐私权限由 macOS 管理。").font(.caption).foregroundStyle(.secondary)
                Text("当前通过 Finder 定位新文件，不需要辅助功能权限。").font(.caption).foregroundStyle(.secondary)
            }
            Section("配置") {
                HStack {
                    Button("导入配置…") { importConfiguration() }.disabled(model.processing)
                    Button("导出配置…") { exportConfiguration() }
                }
                Text("导出不包含环境变量值或目录访问授权。").font(.caption).foregroundStyle(.secondary)
                Button("导出诊断日志…") { exportDiagnostics() }
                Text("仅包含本次运行的时间和事件类别，不含文件路径、文件名、参数或环境变量。").font(.caption).foregroundStyle(.secondary)
                Button("恢复默认设置…", role: .destructive) { resetConfirmation = true }
            }
        }
    }
    private var applications: some View {
        Section {
            ForEach(model.configuration.applications) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle(entry.name, isOn: Binding(get: { entry.enabled }, set: { value in update { config in
                            if let index = config.applications.firstIndex(where: { $0.id == entry.id }) { config.applications[index].enabled = value }
                        } }))
                        Button("编辑…") { editingApplication = entry }.accessibilityLabel(L10n.format("编辑 %@", entry.name))
                        Button("上移") { update { config in
                            if let index = config.applications.firstIndex(where: { $0.id == entry.id }), index > 0 { config.applications.swapAt(index, index - 1) }
                        } }.disabled(model.configuration.applications.first?.id == entry.id)
                        .accessibilityLabel(L10n.format("上移 %@", entry.name))
                        Button("下移") { update { config in
                            if let index = config.applications.firstIndex(where: { $0.id == entry.id }), index + 1 < config.applications.count { config.applications.swapAt(index, index + 1) }
                        } }.disabled(model.configuration.applications.last?.id == entry.id)
                        .accessibilityLabel(L10n.format("下移 %@", entry.name))
                        Button("移除") { update { $0.applications.removeAll { $0.id == entry.id }; $0.shortcuts.removeAll { $0 == .application(entry.id) } } }.accessibilityLabel(L10n.format("移除 %@", entry.name))
                    }
                    Text(entry.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    SourceAvailabilityLabel(url: entry.url, access: model.directoryAccess, requiresDirectory: true)
                }
            }
            Button("添加应用…") {
                guard let url = choose(files: true, directories: false, types: [.application]) else { return }
                update { $0.applications.append(.init(name: url.deletingPathExtension().lastPathComponent, url: url)) }
            }
            Text("选中文件时传递全部选中项；空白处传递当前目录。应用需支持打开相应类型。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var operations: some View {
        Section("右键菜单中的文件操作") {
            ForEach(BuiltinAction.allCases, id: \.self) { action in
                Toggle(L10n.text(actionNames[action] ?? action.rawValue), isOn: Binding(get: { model.configuration.enabledActions.contains(action) }, set: { value in
                    update { if value { $0.enabledActions.insert(action) } else { $0.enabledActions.remove(action) } }
                }))
            }
            Text("永久删除默认关闭，每次执行仍需确认，不经过废纸篓。空白处不会出现删除操作。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var templates: some View {
        Section("新建文件模板") {
            ForEach(model.configuration.templates) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle("\(entry.displayName) (.\(entry.fileExtension))", isOn: Binding(get: { entry.enabled }, set: { value in update { config in
                            if let index = config.templates.firstIndex(where: { $0.id == entry.id }) { config.templates[index].enabled = value }
                        } }))
                        Button("改名…") { editingTemplate = entry }.accessibilityLabel(L10n.format("改名 %@", entry.displayName))
                        Button("上移") { update { config in
                            if let index = config.templates.firstIndex(where: { $0.id == entry.id }), index > 0 { config.templates.swapAt(index, index - 1) }
                        } }.disabled(model.configuration.templates.first?.id == entry.id)
                            .accessibilityLabel(L10n.format("上移 %@", entry.displayName))
                        Button("下移") { update { config in
                            if let index = config.templates.firstIndex(where: { $0.id == entry.id }), index + 1 < config.templates.count { config.templates.swapAt(index, index + 1) }
                        } }.disabled(model.configuration.templates.last?.id == entry.id)
                            .accessibilityLabel(L10n.format("下移 %@", entry.displayName))
                        if entry.source != nil {
                            Button("重新导入…") {
                                guard let url = choose(files: true, directories: false) else { return }
                                model.importTemplate(from: url, replacing: entry)
                            }.accessibilityLabel(L10n.format("重新导入 %@", entry.displayName))
                            Button("移除") { model.removeTemplate(entry) }.accessibilityLabel(L10n.format("移除 %@", entry.displayName))
                        }
                    }
                    if let source = entry.source {
                        SourceAvailabilityLabel(url: source, access: model.directoryAccess, unavailableMessage: "模板副本不可访问，请重新导入有效模板。")
                    }
                }
            }
            Button("导入模板…") {
                guard let url = choose(files: true, directories: false), !url.pathExtension.isEmpty else { return }
                model.importTemplate(from: url)
            }
            Text("导入后保留独立副本，不受原文件移动影响。Office / iWork 请先确认可在原应用打开；这里只检查基础结构。支持 TXT、MD、JSON、DOCX、XLSX、PPTX、Pages、Numbers、Keynote，单个模板最多 256 MB。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var directories: some View {
        Section("目录快捷入口") {
            ForEach(model.configuration.directories) { entry in
                VStack(alignment: .leading) {
                    HStack {
                        Toggle(entry.name, isOn: Binding(get: { entry.enabled }, set: { value in update { config in
                            if let index = config.directories.firstIndex(where: { $0.id == entry.id }) { config.directories[index].enabled = value }
                        } }))
                        Button("编辑…") { editingDirectory = entry }.accessibilityLabel(L10n.format("编辑 %@", entry.name))
                        Button("上移") { update { config in
                            if let index = config.directories.firstIndex(where: { $0.id == entry.id }), index > 0 { config.directories.swapAt(index, index - 1) }
                        } }.disabled(model.configuration.directories.first?.id == entry.id)
                        .accessibilityLabel(L10n.format("上移 %@", entry.name))
                        Button("下移") { update { config in
                            if let index = config.directories.firstIndex(where: { $0.id == entry.id }), index + 1 < config.directories.count { config.directories.swapAt(index, index + 1) }
                        } }.disabled(model.configuration.directories.last?.id == entry.id)
                        .accessibilityLabel(L10n.format("下移 %@", entry.name))
                        Button("移除") { update { $0.directories.removeAll { $0.id == entry.id }; $0.shortcuts.removeAll { $0 == .directory(entry.id) } } }.accessibilityLabel(L10n.format("移除 %@", entry.name))
                    }
                    Text(entry.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    SourceAvailabilityLabel(url: entry.url, access: model.directoryAccess, requiresDirectory: true)
                }
            }
            Button("添加目录…") {
                guard let url = choose(files: false, directories: true) else { return }
                update { $0.directories.append(.init(name: url.lastPathComponent, url: url)) }
            }
            Text("点击菜单入口会在 Finder 打开目录。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var menu: some View {
        Group {
            Section("第一层快捷操作 · 最多 5 项") {
                ForEach(shortcutChoices, id: \.reference) { item in
                    Toggle(item.title + (model.configuration.isEnabled(item.reference) ? "" : " · " + L10n.text("来源功能已关闭")), isOn: Binding(get: { draft.shortcuts.contains(item.reference) }, set: { value in
                        if value && draft.shortcuts.count < 5 { draft.shortcuts.append(item.reference) }
                        else if !value { draft.shortcuts.removeAll { $0 == item.reference } }
                    }))
                    .disabled(!draft.shortcuts.contains(item.reference) && draft.shortcuts.count >= 5)
                }
                Text("建议保留 1–3 项；来源关闭后自动隐藏，永久删除不能加入快捷操作。").font(.caption).foregroundStyle(.secondary)
            }
            if !draft.shortcuts.isEmpty {
                Section("快捷操作顺序") {
                    ForEach(Array(draft.shortcuts.enumerated()), id: \.element) { index, reference in
                        HStack {
                            Text(shortcutChoices.first(where: { $0.reference == reference })?.title ?? "操作不可用")
                            Spacer()
                            Button("上移") { draft.shortcuts.swapAt(index, index - 1) }.disabled(index == 0)
                                .accessibilityLabel(L10n.format("上移 %@", shortcutChoices.first(where: { $0.reference == reference })?.title ?? L10n.text("操作不可用")))
                            Button("下移") { draft.shortcuts.swapAt(index, index + 1) }.disabled(index + 1 == draft.shortcuts.count)
                                .accessibilityLabel(L10n.format("下移 %@", shortcutChoices.first(where: { $0.reference == reference })?.title ?? L10n.text("操作不可用")))
                        }
                    }
                }
            }
            Section("菜单分组顺序") {
                ForEach(Array(draft.groups.enumerated()), id: \.element) { index, group in
                    HStack {
                        Text(L10n.text(groupNames[group] ?? group.rawValue))
                        Spacer()
                        Button("上移") { draft.groups.swapAt(index, index - 1) }.disabled(index == 0)
                            .accessibilityLabel(L10n.format("上移 %@", L10n.text(groupNames[group] ?? group.rawValue)))
                        Button("下移") { draft.groups.swapAt(index, index + 1) }.disabled(index == draft.groups.count - 1)
                            .accessibilityLabel(L10n.format("下移 %@", L10n.text(groupNames[group] ?? group.rawValue)))
                    }
                }
                HStack {
                    Button("恢复默认菜单…") { resetMenuConfirmation = true }
                    Button("放弃更改") { draft = MenuCustomization(configuration: model.configuration) }
                        .disabled(draft == MenuCustomization(configuration: model.configuration))
                    Button("保存更改") { saveMenu() }
                        .keyboardShortcut("s")
                        .disabled(draft == MenuCustomization(configuration: model.configuration))
                }
            }
        }
    }
    private func saveMenu() {
        do {
            if model.save(try draft.applying(to: model.configuration)) {
                draft = MenuCustomization(configuration: model.configuration)
            }
        } catch { model.errorMessage = error.localizedDescription }
    }
    private var shortcutChoices: [MenuAction] {
        let context = TargetContext(selected: [], directory: URL(fileURLWithPath: "/"))
        var choices = model.configuration
        choices.enabledActions = Set(BuiltinAction.allCases)
        for i in choices.applications.indices { choices.applications[i].enabled = true }
        for i in choices.directories.indices { choices.directories[i].enabled = true }
        for i in choices.templates.indices { choices.templates[i].enabled = true }
        return MenuPlanner.plan(configuration: choices, context: context, isDirectory: { _ in true }).sections.flatMap(\.actions)
            .filter { $0.reference != .builtin(.deletePermanently) }
    }
    private var releaseLinks: ReleaseLinks {
        ReleaseLinks(gitHub: Bundle.main.object(forInfoDictionaryKey: "ClickportGitHubURL") as? String,
                     updates: Bundle.main.object(forInfoDictionaryKey: "ClickportUpdatesURL") as? String,
                     feedback: Bundle.main.object(forInfoDictionaryKey: "ClickportFeedbackURL") as? String)
    }
    private var about: some View {
        Section {
            Text("Clickport").font(.largeTitle)
            Text(L10n.format("版本 %@（%@）", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—", Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))
            Text("Finder 右键文件操作工具")
            if let url = releaseLinks.gitHub { Link("GitHub", destination: url) }
            else { Button("GitHub · 地址待配置") {}.disabled(true) }
            if let url = releaseLinks.updates { Link("查看更新…", destination: url) }
            else { Button("查看更新 · 尚未配置") {}.disabled(true) }
            if let url = releaseLinks.feedback { Link("反馈问题…", destination: url) }
            else { Button("反馈问题 · 尚未配置") {}.disabled(true) }
            Text("更新和反馈入口会在浏览器打开，不自动下载或发送诊断日志。").font(.caption).foregroundStyle(.secondary)
            Text("当前为本地开发构建，尚未完成 V1 验收。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func choose(files: Bool, directories: Bool, types: [UTType] = []) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = files; panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = false
        if !types.isEmpty { panel.allowedContentTypes = types }
        return panel.runModal() == .OK ? panel.url : nil
    }
    private func importConfiguration() {
        guard let url = choose(files: true, directories: false, types: [.json]) else { return }
        let originalDraft = draft
        model.importConfiguration(from: url) {
            if draft == originalDraft {
                draft = MenuCustomization(configuration: model.configuration)
            } else {
                draft.reconcile(with: model.configuration)
            }
        }
    }
    private func exportDiagnostics() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Clickport-diagnostics.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.diagnostics.exportData().write(to: url, options: .atomic)
            model.resultMessage = L10n.text("诊断日志已导出")
        }
        catch { model.errorMessage = error.localizedDescription }
    }
    private func exportConfiguration() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Clickport.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.configuration.exportData().write(to: url, options: .atomic)
            model.resultMessage = L10n.text("配置已导出")
        }
        catch { model.errorMessage = error.localizedDescription }
    }
}
