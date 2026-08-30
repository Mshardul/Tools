import Foundation
@testable import GrabberKit

public final class FakeProcessRunner: ProcessRunning, Sendable {
    public struct Script: Sendable {
        public var lines: [ProcessLine]
        public var exitCode: Int32

        public init(lines: [ProcessLine] = [], exitCode: Int32 = 0) {
            self.lines = lines
            self.exitCode = exitCode
        }

        public static func stdout(_ text: String, exitCode: Int32 = 0) -> Script {
            let lines = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { ProcessLine.stdout(String($0)) }
            return Script(lines: lines, exitCode: exitCode)
        }

        public static func stderr(_ text: String, exitCode: Int32 = 1) -> Script {
            let lines = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { ProcessLine.stderr(String($0)) }
            return Script(lines: lines, exitCode: exitCode)
        }
    }

    private struct Delays {
        var perRun: Duration = .zero
        var perLine: Duration = .zero
    }

    private struct State {
        var scripts: [String: Script] = [:]
        var launches: [ProcessLaunch] = []
        var maxConcurrent = 0
        var currentConcurrent = 0
        var delays = Delays()
        var cancelledCount = 0
    }

    private let box = LockedBox(State())

    public init() {}

    public var perRunDelay: Duration {
        get { box.read { $0.delays.perRun } }
        set { box.mutate { $0.delays.perRun = newValue } }
    }

    public var perLineDelay: Duration {
        get { box.read { $0.delays.perLine } }
        set { box.mutate { $0.delays.perLine = newValue } }
    }

    public var launches: [ProcessLaunch] {
        box.read { $0.launches }
    }

    public var maxConcurrent: Int {
        box.read { $0.maxConcurrent }
    }

    public var cancelledCount: Int {
        box.read { $0.cancelledCount }
    }

    public func script(_ script: Script, forPathEndingIn suffix: String) {
        box.mutate { $0.scripts[suffix] = script }
    }

    public func script(_ script: Script, forExactPath path: String) {
        box.mutate { $0.scripts[path] = script }
    }

    public func run(_ launch: ProcessLaunch) -> ProcessExecution {
        let (script, delays) = box.mutate { state -> (Script, Delays) in
            state.launches.append(launch)
            state.currentConcurrent += 1
            state.maxConcurrent = max(state.maxConcurrent, state.currentConcurrent)
            let script = state.scripts[launch.executableURL.path]
                ?? state.scripts[launch.executableURL.lastPathComponent]
                ?? Script(exitCode: 127)
            return (script, state.delays)
        }
        return makeExecution(script: script, delays: delays)
    }

    private func makeExecution(script: Script, delays: Delays) -> ProcessExecution {
        let (stream, continuation) = AsyncStream<ProcessLine>.makeStream()
        let exitBox = FakeExitBox()
        let box = box
        let settled = LockedBox(false)
        let markSettled: @Sendable () -> Bool = {
            settled.mutate { done in
                if done {
                    return false
                }
                done = true
                return true
            }
        }

        let emitter = Task {
            if delays.perRun != .zero {
                try? await Task.sleep(for: delays.perRun)
            }
            try Task.checkCancellation()
            for line in script.lines {
                if delays.perLine != .zero {
                    try await Task.sleep(for: delays.perLine)
                }
                continuation.yield(line)
            }
            continuation.finish()
            if markSettled() {
                exitBox.set(ProcessResult(exitCode: script.exitCode, wasCancelled: false))
                box.mutate { $0.currentConcurrent -= 1 }
            }
        }

        return ProcessExecution(lines: stream) {
            await withTaskCancellationHandler {
                await exitBox.value()
            } onCancel: {
                emitter.cancel()
                continuation.finish()
                if markSettled() {
                    box.mutate {
                        $0.cancelledCount += 1
                        $0.currentConcurrent -= 1
                    }
                    exitBox.set(ProcessResult(exitCode: -15, wasCancelled: true))
                }
            }
        }
    }
}

private final class FakeExitBox: @unchecked Sendable {
    private let box = LockedBox(Storage())

    private struct Storage {
        var result: ProcessResult?
        var waiters: [CheckedContinuation<ProcessResult, Never>] = []
    }

    func set(_ value: ProcessResult) {
        let pending = box.mutate { storage -> [CheckedContinuation<ProcessResult, Never>] in
            guard storage.result == nil else { return [] }
            storage.result = value
            let waiters = storage.waiters
            storage.waiters.removeAll()
            return waiters
        }
        for waiter in pending {
            waiter.resume(returning: value)
        }
    }

    func value() async -> ProcessResult {
        await withCheckedContinuation { continuation in
            let immediate = box.mutate { storage -> ProcessResult? in
                if let result = storage.result {
                    return result
                }
                storage.waiters.append(continuation)
                return nil
            }
            if let immediate {
                continuation.resume(returning: immediate)
            }
        }
    }
}
