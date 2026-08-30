import Foundation

public final class LockedBox<Value>: @unchecked Sendable {
    private var value: Value
    private let lock: os_unfair_lock_t

    public init(_ value: Value) {
        self.value = value
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    public func read<T>(_ body: (Value) -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return body(value)
    }

    @discardableResult
    public func mutate<T>(_ body: (inout Value) -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return body(&value)
    }
}
