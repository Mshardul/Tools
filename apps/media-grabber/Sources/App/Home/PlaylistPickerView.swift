import GrabberKit
import SwiftUI

struct PlaylistPickerView: View {
    @Binding var model: PlaylistPickerModel
    let onCancel: () -> Void
    let onAdd: () async -> Void

    @Environment(\.theme) private var theme
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            header
            if model.showPlaylistBanner {
                banner
            }
            tools
            list
            footer
        }
        .padding(Spacing.s5)
        .frame(minWidth: 620, idealWidth: 720, maxWidth: 820, minHeight: 520, maxHeight: 680)
        .background(theme.palette.panelSolid)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text("Choose videos to download")
                .font(theme.displayFont(20, .semibold))
                .foregroundStyle(theme.palette.headline)
            Text(subtitle)
                .font(theme.bodyFont(12, .regular))
                .foregroundStyle(theme.palette.dim)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var banner: some View {
        Text("This playlist is already in your queue.")
            .font(theme.bodyFont(12, .semibold))
            .foregroundStyle(theme.palette.warn)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.panelHi, in: RoundedRectangle(cornerRadius: theme.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: theme.controlRadius)
                    .stroke(theme.palette.warn.opacity(0.4), lineWidth: theme.hairlineWidth)
            )
    }

    private var tools: some View {
        HStack(spacing: Spacing.s2) {
            toolButton("Select all") { model.selectAllFiltered() }
            toolButton("Select none") { model.selectNoneFiltered() }
            Spacer()
            filterField
        }
    }

    private var filterField: some View {
        TextField("", text: $model.filter)
            .textFieldStyle(.plain)
            .font(theme.bodyFont(12, .regular))
            .foregroundStyle(theme.palette.text)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .frame(width: 220)
            .background(theme.palette.panel, in: RoundedRectangle(cornerRadius: theme.controlRadius))
            .overlay(alignment: .leading) {
                if model.filter.isEmpty {
                    Text("filter…")
                        .font(theme.bodyFont(12, .regular))
                        .foregroundStyle(theme.palette.faint)
                        .padding(.leading, Spacing.s3)
                        .allowsHitTesting(false)
                }
            }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.s2) {
                ForEach(model.filteredEntries, id: \.playlistIndex) { entry in
                    PlaylistPickerRow(
                        entry: entry,
                        isChecked: model.checked.contains(entry.playlistIndex),
                        warning: model.warnings[entry.playlistIndex],
                        toggle: { toggle(entry.playlistIndex) }
                    )
                }
            }
            .padding(Spacing.s2)
        }
        .background(theme.palette.panel, in: RoundedRectangle(cornerRadius: theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cardRadius)
                .stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth)
        )
    }

    private var footer: some View {
        HStack(spacing: Spacing.s3) {
            Text(model.footerLine)
                .font(theme.bodyFont(12, .regular))
                .foregroundStyle(theme.palette.dim)
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(PlaylistPickerButtonStyle())
            Button("Add \(model.selectedCount)") {
                submitSelection()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(PlaylistPickerButtonStyle(isPrimary: true))
            .disabled(model.selectedCount == 0 || isAdding)
            .opacity(model.selectedCount == 0 || isAdding ? 0.45 : 1)
        }
    }

    private var subtitle: String {
        var parts = [model.dump.title, sourceHost]
        if let uploader = model.dump.uploader, !uploader.isEmpty {
            parts.append("by \(uploader)")
        }
        parts.append("\(model.dump.entries.count) items")
        return parts.joined(separator: " · ")
    }

    private var sourceHost: String {
        let trimmed = model.dump.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = URL(string: trimmed)?.host ?? trimmed
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func toolButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(PlaylistPickerButtonStyle())
    }

    private func toggle(_ playlistIndex: Int) {
        if model.checked.contains(playlistIndex) {
            model.checked.remove(playlistIndex)
        } else {
            model.checked.insert(playlistIndex)
        }
    }

    private func submitSelection() {
        guard model.selectedCount > 0, !isAdding else { return }
        isAdding = true
        Task {
            await onAdd()
            isAdding = false
        }
    }
}

private struct PlaylistPickerRow: View {
    let entry: PlaylistEntry
    let isChecked: Bool
    let warning: PlaylistRowWarning?
    let toggle: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.s3) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isChecked ? theme.palette.accent : theme.palette.faint)
                thumbnail
                Text(entry.title)
                    .font(theme.bodyFont(13, .medium))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Spacing.s3)
                Text(duration)
                    .font(theme.monoFont(11, .regular))
                    .foregroundStyle(theme.palette.dim)
                if let warning {
                    Text(label(for: warning))
                        .font(theme.monoFont(10, .medium))
                        .foregroundStyle(theme.palette.warn)
                }
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .background(theme.palette.panelHi.opacity(isChecked ? 1 : 0.45), in: rowShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let raw = entry.thumbnailURL, let url = URL(string: raw) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
            .frame(width: 52, height: 30)
            .clipShape(thumbnailShape)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: theme.controlRadius)
            .fill(theme.palette.panel)
            .frame(width: 52, height: 30)
            .overlay(thumbnailShape.stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth))
    }

    private var thumbnailShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.controlRadius)
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.controlRadius)
    }

    private var duration: String {
        guard let seconds = entry.durationSeconds else { return "—" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return "\(hours):\(padded(minutes)):\(padded(remainingSeconds))"
        }
        return "\(minutes):\(padded(remainingSeconds))"
    }

    private var accessibilityLabel: String {
        [entry.title, duration, warning.map(label(for:))]
            .compactMap(\.self)
            .joined(separator: ", ")
    }

    private func label(for warning: PlaylistRowWarning) -> String {
        switch warning {
        case .inQueue: "In queue"
        case .alreadySaved: "Already saved"
        }
    }

    private func padded(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}

private struct PlaylistPickerButtonStyle: ButtonStyle {
    var isPrimary = false
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.bodyFont(12, .semibold))
            .foregroundStyle(isPrimary ? theme.palette.onAccent : theme.palette.text)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .background(fill, in: shape)
            .overlay(shape.stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }

    private var fill: some ShapeStyle {
        isPrimary ? AnyShapeStyle(theme.palette.accent) : AnyShapeStyle(theme.palette.panel)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.controlRadius)
    }
}
