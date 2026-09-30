import AppKit

final class StubSharingService: NSSharingService {
    var acceptsItems = true
    var performedItems: [Any] = []
    override func canPerform(withItems items: [Any]?) -> Bool { acceptsItems }
    override func perform(withItems items: [Any]) { performedItems = items }
}

@main
struct SharingLifecycleChecks {
    @MainActor static func main() throws {
        let file = URL(fileURLWithPath: "/test-fixture/document.txt")
        let scope = URL(fileURLWithPath: "/test-fixture")
        let service = StubSharingService(title: "Fixture", image: NSImage(), alternateImage: nil, handler: {})
        var released: [URL] = []
        var activations = 0
        var failures = 0
        let actions = SystemActions(makeSharingService: { service }, activateForSharing: { activations += 1 }, releaseSharingScope: { released.append($0) })
        var scopes = [scope]
        try actions.airDrop([file], transferring: &scopes) { _ in failures += 1 }
        precondition(scopes.isEmpty && released.isEmpty && activations == 1)
        precondition((service.performedItems as? [URL]) == [file])
        var duplicateScopes = [scope]
        do {
            try actions.airDrop([file], transferring: &duplicateScopes) { _ in failures += 1 }
            preconditionFailure("An active service must not replace its session")
        } catch { precondition(duplicateScopes == [scope] && released.isEmpty) }
        actions.sharingService(service, didShareItems: [file])
        actions.sharingService(service, didShareItems: [file])
        precondition(released == [scope] && service.delegate == nil && failures == 0)
        scopes = [scope]
        try actions.airDrop([file], transferring: &scopes) { _ in failures += 1 }
        let cancellation = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        actions.sharingService(service, didFailToShareItems: [file], error: cancellation)
        actions.sharingService(service, didFailToShareItems: [file], error: cancellation)
        precondition(released == [scope, scope] && failures == 1 && service.delegate == nil)
        service.acceptsItems = false
        scopes = [scope]
        do {
            try actions.airDrop([file], transferring: &scopes) { _ in failures += 1 }
            preconditionFailure("Unsupported targets must fail")
        } catch { precondition(scopes == [scope] && released.count == 2) }
        let unavailable = SystemActions(makeSharingService: { nil }, activateForSharing: { preconditionFailure() })
        do {
            try unavailable.airDrop([file], transferring: &scopes) { _ in preconditionFailure() }
            preconditionFailure("Unavailable service must fail")
        } catch { precondition(scopes == [scope]) }
        print("Sharing lifecycle passed: deferred release, duplicate service, success, cancellation/failure, unavailable and unsupported service")
    }
}
