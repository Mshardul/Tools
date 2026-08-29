import Foundation

public struct ProcessLaunch: Sendable {
    public var executableURL: URL
    public var arguments: [String]
    // nil inherits the parent env; non-nil is merged onto it, caller keys winning.
    public var environment: [String: String]?
    public var currentDirectoryURL: URL?

    public init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
    }
}

public enum ProcessLine: Sendable {
    case stdout(String)
    case stderr(String)
}

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let wasCancelled: Bool

    public init(exitCode: Int32, wasCancelled: Bool) {
        self.exitCode = exitCode
        self.wasCancelled = wasCancelled
    }
}

public struct ProcessExecution: Sendable {
    public let lines: AsyncStream<ProcessLine>
    private let resultProvider: @Sendable () async -> ProcessResult

    init(
        lines: AsyncStream<ProcessLine>,
        result: @escaping @Sendable () async -> ProcessResult
    ) {
        self.lines = lines
        resultProvider = result
    }

    // Cancelling the awaiting Task sends SIGTERM; result then has wasCancelled == true.
    public func result() async -> ProcessResult {
        await resultProvider()
    }
}

public protocol ProcessRunning: Sendable {
    func run(_ launch: ProcessLaunch) -> ProcessExecution
}

public struct ProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ launch: ProcessLaunch) -> ProcessExecution {
        let state = RunState()
        let (stream, continuation) = AsyncStream<ProcessLine>.makeStream()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let process = Self.makeProcess(launch, stdout: stdoutPipe, stderr: stderrPipe)

        let exitContinuation = ExitBox()

        do {
            try process.run()
        } catch {
            continuation.yield(
                .stderr("launch failed: \(error.localizedDescription)")
            )
            continuation.finish()
            exitContinuation.resume(
                ProcessResult(exitCode: 127, wasCancelled: false)
            )
            return ProcessExecution(lines: stream) {
                await exitContinuation.value()
            }
        }

        // Stream finishes only once BOTH readers hit EOF, so nothing is dropped.
        let pending = ReaderLatch(count: 2) { continuation.finish() }
        readInBackground(stdoutPipe.fileHandleForReading, latch: pending) {
            continuation.yield(.stdout($0))
        }
        readInBackground(stderrPipe.fileHandleForReading, latch: pending) {
            continuation.yield(.stderr($0))
        }
        startWaiter(for: process, state: state, publish: exitContinuation)

        let resultProvider: @Sendable () async -> ProcessResult = {
            await withTaskCancellationHandler {
                await exitContinuation.value()
            } onCancel: {
                state.markCancelled()
                if process.isRunning {
                    process.terminate()
                }
            }
        }
        return ProcessExecution(lines: stream, result: resultProvider)
    }

    private static func makeProcess(
        _ launch: ProcessLaunch,
        stdout: Pipe,
        stderr: Pipe
    ) -> Process {
        let process = Process()
        process.executableURL = launch.executableURL
        process.arguments = launch.arguments
        process.standardOutput = stdout
        process.standardError = stderr
        if let currentDirectoryURL = launch.currentDirectoryURL {
            process.currentDirectoryURL = currentDirectoryURL
        }
        if let overrides = launch.environment {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in overrides {
                merged[key] = value
            }
            process.environment = merged
        } else {
            process.environment = ProcessInfo.processInfo.environment
        }
        return process
    }

    private func startWaiter(
        for process: Process,
        state: RunState,
        publish exitContinuation: ExitBox
    ) {
        let waiter = Thread {
            process.waitUntilExit()
            exitContinuation.resume(
                ProcessResult(
                    exitCode: process.terminationStatus,
                    wasCancelled: state.wasCancelled
                )
            )
        }
        waiter.stackSize = 1 << 20
        waiter.start()
    }

    private func readInBackground(
        _ handle: FileHandle,
        latch: ReaderLatch,
        emit: @escaping @Sendable (String) -> Void
    ) {
        let splitter = LineSplitter(emit: emit)
        let thread = Thread {
            let descriptor = handle.fileDescriptor
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = chunk.withUnsafeMutableBytes { buffer in
                    read(descriptor, buffer.baseAddress, buffer.count)
                }
                if count > 0 {
                    splitter.feed(Data(chunk[0 ..< count]))
                } else {
                    break
                }
            }
            splitter.flush()
            latch.signal()
        }
        thread.stackSize = 1 << 20
        thread.start()
    }
}

private final class ReaderLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private let onZero: @Sendable () -> Void

    init(count: Int, onZero: @escaping @Sendable () -> Void) {
        remaining = count
        self.onZero = onZero
    }

    func signal() {
        lock.lock()
        remaining -= 1
        let done = remaining == 0
        lock.unlock()
        if done {
            onZero()
        }
    }
}

private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var wasCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func markCancelled() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
    }
}

// One producer, many awaiters.
private final class ExitBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: ProcessResult?
    private var waiters: [CheckedContinuation<ProcessResult, Never>] = []

    func resume(_ value: ProcessResult) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        for waiter in pending {
            waiter.resume(returning: value)
        }
    }

    func value() async -> ProcessResult {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}

private final class LineSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let emit: @Sendable (String) -> Void

    init(emit: @escaping @Sendable (String) -> Void) {
        self.emit = emit
    }

    private func decode(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8)
            ?? String(bytes: data, encoding: .isoLatin1)
            ?? ""
    }

    func feed(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex ..< newlineIndex)
            buffer.removeSubrange(buffer.startIndex ... newlineIndex)
            lines.append(decode(lineData))
        }
        lock.unlock()
        for line in lines {
            emit(line)
        }
    }

    func flush() {
        lock.lock()
        guard !buffer.isEmpty else { lock.unlock(); return }
        let lineData = buffer
        buffer.removeAll()
        lock.unlock()
        emit(decode(lineData))
    }
}
