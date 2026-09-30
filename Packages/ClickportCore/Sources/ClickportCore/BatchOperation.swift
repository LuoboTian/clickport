import Foundation

public struct BatchResult: Sendable {
    public struct Failure: Sendable {
        public let url: URL
        public let message: String
    }
    public var completed = 0
    public var failures: [Failure] = []
    public var cancelled = false
    public var attempted: Int { completed + failures.count }
}

public enum BatchOperation {
    /// File-system calls run away from the UI actor. Cancellation takes effect between items.
    public static func run(_ urls: [URL], operation: @escaping @Sendable (URL) throws -> Void,
                           progress: @escaping @Sendable (Int, Int) async -> Void = { _, _ in }) async -> BatchResult {
        let worker = Task.detached(priority: .userInitiated) {
            var result = BatchResult()
            for url in urls {
                if Task.isCancelled { result.cancelled = true; break }
                do { try operation(url); result.completed += 1 }
                catch is CancellationError {
                    result.cancelled = true
                    break
                }
                catch { result.failures.append(.init(url: url, message: error.localizedDescription)) }
                await progress(result.attempted, urls.count)
            }
            return result
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
