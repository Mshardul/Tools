import Foundation
import Observation

struct ToastItem: Identifiable, Sendable {
    let id: UUID
    let text: String
    let actionTitle: String?
    let action: (@Sendable () async -> Void)?

    init(
        id: UUID = UUID(),
        text: String,
        actionTitle: String?,
        action: (@Sendable () async -> Void)?
    ) {
        self.id = id
        self.text = text
        self.actionTitle = actionTitle
        self.action = action
    }
}

@MainActor
@Observable
final class ToastCenter {
    private(set) var items: [ToastItem] = []
    private let autoDismissDelay: Duration
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    init(autoDismissDelay: Duration = .seconds(4)) {
        self.autoDismissDelay = autoDismissDelay
    }

    func enqueue(_ item: ToastItem) {
        items.append(item)
        let id = item.id
        dismissTasks[id] = Task { [weak self, autoDismissDelay] in
            try? await Task.sleep(for: autoDismissDelay)
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }

    func dismiss(_ id: UUID) {
        items.removeAll { $0.id == id }
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
    }
}
