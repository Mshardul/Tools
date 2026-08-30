import Foundation

public enum ColumnID: String, Codable, Sendable, CaseIterable {
    case title, status, progress, speed, eta, type, quality, size
    case site, addedAt, finishedAt, duration, destination, attempt, clientUsed
    case actions

    public static let defaultVisible: [ColumnID] = [
        .title, .status, .progress, .speed, .eta, .type, .quality, .size
    ]

    public static let defaultOrder: [ColumnID] = [
        .title, .status, .progress, .speed, .eta, .type, .quality, .size,
        .site, .addedAt, .finishedAt, .duration, .destination, .attempt, .clientUsed,
        .actions
    ]
}

public enum SortDirection: String, Codable, Sendable {
    case ascending, descending
}

public struct ColumnConfig: Codable, Sendable, Equatable {
    public var visibleColumns: [ColumnID]
    public var columnOrder: [ColumnID]
    public var sortColumn: ColumnID?
    public var sortDirection: SortDirection?
    public var columnFilters: [ColumnID: [String]]

    public init(
        visibleColumns: [ColumnID] = ColumnID.defaultVisible + [.actions],
        columnOrder: [ColumnID] = ColumnID.defaultOrder,
        sortColumn: ColumnID? = nil,
        sortDirection: SortDirection? = nil,
        columnFilters: [ColumnID: [String]] = [:]
    ) {
        self.visibleColumns = visibleColumns
        self.columnOrder = columnOrder
        self.sortColumn = sortColumn
        self.sortDirection = sortDirection
        self.columnFilters = columnFilters
        enforceInvariants()
    }

    public static let `default` = ColumnConfig()

    private enum CodingKeys: String, CodingKey {
        case visibleColumns, columnOrder, sortColumn, sortDirection, columnFilters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let visible = try container.decodeIfPresent([String].self, forKey: .visibleColumns) ?? []
        let order = try container.decodeIfPresent([String].self, forKey: .columnOrder) ?? []
        let filtersRaw = try container.decodeIfPresent(
            [String: [String]].self, forKey: .columnFilters
        ) ?? [:]
        visibleColumns = visible.compactMap(ColumnID.init)
        columnOrder = order.compactMap(ColumnID.init)
        sortColumn = try container.decodeIfPresent(String.self, forKey: .sortColumn)
            .flatMap(ColumnID.init)
        sortDirection = try container.decodeIfPresent(SortDirection.self, forKey: .sortDirection)
        columnFilters = Dictionary(uniqueKeysWithValues: filtersRaw.compactMap { key, value in
            ColumnID(rawValue: key).map { ($0, value) }
        })
        enforceInvariants()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visibleColumns.map(\.rawValue), forKey: .visibleColumns)
        try container.encode(columnOrder.map(\.rawValue), forKey: .columnOrder)
        try container.encodeIfPresent(sortColumn?.rawValue, forKey: .sortColumn)
        try container.encodeIfPresent(sortDirection, forKey: .sortDirection)
        let filtersRaw = Dictionary(uniqueKeysWithValues: columnFilters.map { (
            $0.key.rawValue,
            $0.value
        ) })
        try container.encode(filtersRaw, forKey: .columnFilters)
    }

    // Actions is pinned last + always visible; Title is always visible.
    public mutating func enforceInvariants() {
        columnOrder.removeAll { $0 == .actions }
        columnOrder.append(.actions)
        for required in [ColumnID.title, .actions] where !visibleColumns.contains(required) {
            visibleColumns.append(required)
        }
        visibleColumns.removeAll { $0 == .actions }
        visibleColumns.append(.actions)
        appendMissingKnownColumns()
        dropUnknownColumns()
    }

    private mutating func appendMissingKnownColumns() {
        for column in ColumnID.defaultOrder where !columnOrder.contains(column) {
            let insertAt = max(0, columnOrder.count - 1)
            columnOrder.insert(column, at: insertAt)
        }
    }

    private mutating func dropUnknownColumns() {
        let known = Set(ColumnID.allCases)
        visibleColumns = visibleColumns.filter { known.contains($0) }
        columnOrder = columnOrder.filter { known.contains($0) }
        columnFilters = columnFilters.filter { known.contains($0.key) }
    }

    public func orderedVisibleColumns() -> [ColumnID] {
        columnOrder.filter { visibleColumns.contains($0) }
    }

    public mutating func cycleSort(on column: ColumnID) {
        if sortColumn == column {
            switch sortDirection {
            case .ascending:
                sortDirection = .descending
            case .descending:
                sortColumn = nil
                sortDirection = nil
            case nil:
                sortDirection = .ascending
            }
        } else {
            sortColumn = column
            sortDirection = .ascending
        }
    }

    public mutating func setColumnVisible(_ column: ColumnID, visible: Bool) {
        guard column != .actions else { return }
        if visible {
            if !visibleColumns.contains(column) {
                visibleColumns.insert(column, at: max(0, visibleColumns.count - 1))
            }
        } else if column != .title {
            visibleColumns.removeAll { $0 == column }
        }
        enforceInvariants()
    }

    public mutating func moveColumn(from source: ColumnID, to destination: ColumnID) {
        guard source != .actions, destination != .actions, source != destination else { return }
        guard let fromIndex = columnOrder.firstIndex(of: source),
              let toIndex = columnOrder.firstIndex(of: destination)
        else { return }
        columnOrder.remove(at: fromIndex)
        let adjusted = toIndex > fromIndex ? toIndex - 1 : toIndex
        let insertAt = min(adjusted, max(0, columnOrder.count - 1))
        columnOrder.insert(source, at: insertAt)
        enforceInvariants()
    }
}
