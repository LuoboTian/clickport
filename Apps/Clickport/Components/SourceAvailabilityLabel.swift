import SwiftUI
import ClickportCore

struct SourceAvailabilityLabel: View {
    let url: URL
    let access: DirectoryAccess
    var unavailableMessage = "暂时不可访问：可能已移动、离线或缺少权限，请重新选择。"
    var requiresDirectory = false
    @State private var unavailable = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if unavailable {
                Label(L10n.text(unavailableMessage), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            // Probe only this configured item when its row appears; never enumerate its contents.
            let leases = (try? access.beginAccess(to: [url], requestIfNeeded: false)) ?? []
            defer { for root in leases { root.stopAccessingSecurityScopedResource() } }
            let reachable = await Task.detached {
                var currentURL = url
                currentURL.removeAllCachedResourceValues()
                guard (try? currentURL.checkResourceIsReachable()) == true else { return false }
                return !requiresDirectory || (try? currentURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }.value
            if !Task.isCancelled { unavailable = !reachable }
        }
    }
}

struct DirectoryGrantRow: View {
    let grant: DirectoryAccess.Grant
    let access: DirectoryAccess
    let isBusy: Bool
    let onError: (Error) -> Void
    @State private var resolvedPath: String?
    @State private var needsAuthorization = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(resolvedPath ?? grant.displayPath).font(.caption).textSelection(.enabled)
                if needsAuthorization {
                    Label(L10n.text("目录授权不可用，请重新选择"), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("撤销") {
                do { try access.revoke(grant) }
                catch { onError(error) }
            }
            .disabled(isBusy)
            .accessibilityLabel(L10n.format("撤销目录授权 %@", resolvedPath ?? grant.displayPath))
        }
        .task(id: grant.bookmark) {
            let bookmark = grant.bookmark
            let result = await Task.detached { () -> (String?, Bool) in
                var stale = false
                let url = try? URL(resolvingBookmarkData: bookmark,
                                   options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                   relativeTo: nil, bookmarkDataIsStale: &stale)
                return (url?.path, stale || url == nil)
            }.value
            guard !Task.isCancelled else { return }
            resolvedPath = result.0
            needsAuthorization = result.1
        }
    }
}
