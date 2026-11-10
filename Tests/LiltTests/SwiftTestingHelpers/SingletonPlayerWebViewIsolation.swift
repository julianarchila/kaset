import Testing
@testable import Lilt

// MARK: - SingletonPlayerWebViewIsolation

/// Serializes tests that read or replace process-wide `SingletonPlayerWebView.shared` state.
///
/// `.serialized` only orders tests within one suite; different suites still run in parallel and,
/// being `@MainActor`, interleave at every `await`. A test that installs its own coordinator can
/// then lose events because another suite tore the singleton down, replaced its coordinator, or
/// advanced its document generation. Every suite that touches the singleton should use this trait.
struct SingletonPlayerWebViewIsolation: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool {
        true
    }

    func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        // Scopes nest (suite, test, test case); only the outermost one takes the lock.
        if ExclusiveTestLock.isHeld {
            try await function()
            return
        }
        await ExclusiveTestLock.singletonPlayerWebView.acquire()
        do {
            try await ExclusiveTestLock.$isHeld.withValue(true) {
                try await function()
            }
        } catch {
            await ExclusiveTestLock.singletonPlayerWebView.release()
            throw error
        }
        await ExclusiveTestLock.singletonPlayerWebView.release()
    }
}

extension Trait where Self == SingletonPlayerWebViewIsolation {
    /// Runs the suite or test exclusively with respect to other users of `SingletonPlayerWebView.shared`.
    static var singletonPlayerWebView: Self {
        Self()
    }
}

// MARK: - ExclusiveTestLock

/// A FIFO async lock shared across suites.
actor ExclusiveTestLock {
    static let singletonPlayerWebView = ExclusiveTestLock()

    @TaskLocal static var isHeld = false

    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard self.isLocked else {
            self.isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            self.waiters.append(continuation)
        }
    }

    func release() {
        if self.waiters.isEmpty {
            self.isLocked = false
        } else {
            self.waiters.removeFirst().resume()
        }
    }
}
