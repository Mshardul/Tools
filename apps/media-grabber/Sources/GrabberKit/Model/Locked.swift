import Foundation

// os_unfair_lock box for shared mutable state touched from async code (Mutex needs macOS 15).
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock: os_unfair_lock_t

    init(_ value: Value) {
        self.value = value
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    func read<T>(_ body: (Value) -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return body(value)
    }

    @discardableResult
    func mutate<T>(_ body: (inout Value) -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return body(&value)
    }
}
