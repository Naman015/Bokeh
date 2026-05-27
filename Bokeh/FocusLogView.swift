import SwiftUI
import UIKit

// MARK: - Focus Log

struct FocusLogView: View {
    @ObservedObject var logManager: LogManager
    var lastAddedId: UUID? = nil
    var openLogId: UUID? = nil
    var onClearOpenLogId: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText: String = ""
    @State private var selected: ClearLog?
    @State private var selectedLocationTag: String? = nil
    @State private var sparkleOpacity: Double = 0.6

    private var locationTags: [String] {
        var seen = Set<String>()
        return logManager.logs
            .compactMap { $0.location?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .sorted()
    }

    private var filtered: [ClearLog] {
        var items = logManager.logs
        if let tag = selectedLocationTag {
            items = items.filter { $0.location?.trimmingCharacters(in: .whitespacesAndNewlines) == tag }
        }
        return SmartSearchEngine.search(
            items: items,
            query: searchText,
            labelKeyPath: \.label,
            locationKeyPath: \.location
        )
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                if logManager.isLoading {
                    ProgressView()
                        .tint(Color.theme.bokehTeal)
                } else if filtered.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle("Focus Log")
            .navigationBarTitleDisplayMode(horizontalSizeClass == .regular ? .large : .inline)
            .searchable(text: $searchText, prompt: "Ask 'Where are my keys?'")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: AppLayoutConstants.minTouchTarget, height: AppLayoutConstants.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("Close")
                    .accessibilityHint("Closes the Focus Log")
                }
                if !logManager.logs.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear All", role: .destructive) {
                            selected = nil
                            withAnimation { logManager.clearAll() }
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
            }
        }
        .onAppear {
            if let id = openLogId {
                if let log = logManager.logs.first(where: { $0.id == id }) {
                    selected = log
                }
                onClearOpenLogId?()
            }
        }
        .sheet(item: $selected) { log in
            DetailSheet(log: log, logManager: logManager, onDelete: {
                logManager.remove(log)
                selected = nil
            })
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            if isSearching {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .foregroundStyle(Color.theme.bokehTeal.opacity(0.5))
                Text("Hmm, nothing matching that.")
                    .bokehFont(.headline, weight: .semibold)
                    .foregroundStyle(.primary)
                Text("Try asking \"Where are my keys?\" or\nsearch by location name.")
                    .bokehFont(.subheadline, weight: .regular)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.theme.bokehTealSubtle)
                        .frame(width: 100, height: 100)
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 40, weight: .light, design: .rounded))
                        .foregroundStyle(Color.theme.bokehTeal.opacity(0.7))
                    Image(systemName: "sparkle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.theme.bokehAmber)
                        .offset(x: 30, y: -30)
                        .opacity(sparkleOpacity)
                }
                .padding(.bottom, 4)

                Text("Your Focus Log starts here.")
                    .bokehFont(.headline, weight: .semibold)
                    .foregroundStyle(Color.theme.bokehTitleColor)
                Text("Point your camera at something you want to clear.\nWe'll help you tidy up one thing at a time.")
                    .bokehFont(.subheadline, weight: .regular)
                    .foregroundStyle(Color.theme.bokehBodyColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: { dismiss() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("Start Clearing")
                            .bokehFont(.subheadline, weight: .semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.theme.bokehTeal, in: Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    sparkleOpacity = 1.0
                }
            }
        }
    }

    private var groupedByDay: [(key: String, items: [ClearLog])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { log in
            calendar.startOfDay(for: log.timestamp)
        }
        return grouped.sorted { $0.key > $1.key }.map { (key: dayLabel(for: $0.key), items: $0.value) }
    }

    private func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private var grid: some View {
        let minCellWidth = AppLayoutConstants.focusLogCellMinWidth(horizontalSizeClass: horizontalSizeClass)
        let cellHeight = AppLayoutConstants.focusLogCellHeight(horizontalSizeClass: horizontalSizeClass)
        let padding = AppLayoutConstants.horizontalPadding(horizontalSizeClass: horizontalSizeClass)
        return ScrollView {
            VStack(spacing: 16) {
                if !locationTags.isEmpty {
                    locationTagsSection
                }
                LazyVStack(spacing: 24) {
                    ForEach(groupedByDay, id: \.key) { section in
                        Section {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: minCellWidth), spacing: 16)], spacing: 16) {
                                ForEach(section.items) { log in
                                    FocusLogCell(log: log, logManager: logManager, isNew: log.id == lastAddedId, cellHeight: cellHeight) {
                                        selected = log
                                    }
                                }
                            }
                        } header: {
                            Text(section.key)
                                .bokehFont(.caption, weight: .semibold)
                                .foregroundStyle(Color.theme.bokehCaption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(.horizontal, padding)
            .padding(.vertical, 16)
        }
    }

    private var locationTagsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: { selectedLocationTag = nil }) {
                    Text("All")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(selectedLocationTag == nil ? .white : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selectedLocationTag == nil ? Color.theme.bokehTeal : Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(ScaleButtonStyle(minScale: 0.98))
                .accessibilityLabel("Show all locations")
                .accessibilityAddTraits(selectedLocationTag == nil ? .isSelected : [])
                ForEach(locationTags, id: \.self) { tag in
                    Button(action: { selectedLocationTag = tag }) {
                        Text(tag)
                            .font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(selectedLocationTag == tag ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedLocationTag == tag ? Color.theme.bokehTeal : Color(uiColor: .tertiarySystemFill), in: Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle(minScale: 0.98))
                    .accessibilityLabel(tag)
                    .accessibilityHint("Filter by \(tag)")
                    .accessibilityAddTraits(selectedLocationTag == tag ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct FocusLogCell: View {
    let log: ClearLog
    @ObservedObject var logManager: LogManager
    let isNew: Bool
    var cellHeight: CGFloat = 180
    var onTap: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var image: UIImage?

    private var cornerRadius: CGFloat {
        AppLayoutConstants.cardCornerRadius(horizontalSizeClass: horizontalSizeClass)
    }

    private var accessibilityLabelText: String {
        if let loc = log.location, !loc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(log.label), cleared. Located in \(loc)."
        } else {
            return "\(log.label), cleared."
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Image area
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))

                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(12)
                            .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }

                    if isNew {
                        VStack {
                            HStack {
                                Spacer()
                                Text("NEW")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.theme.bokehTeal, in: Capsule())
                                    .padding(8)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: cellHeight * 0.58)

                // Item name, location, timestamp
                VStack(alignment: .leading, spacing: 4) {
                    Text(log.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let loc = log.location, !loc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 9))
                            Text(loc)
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        if log.duration > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "stopwatch")
                                    .font(.system(size: 9))
                                Text(formatCellDuration(log.duration))
                                    .font(.caption2)
                            }
                            .foregroundStyle(Color.theme.bokehCaption)
                        }
                        Text(log.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(Color.theme.bokehCaption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double tap to view details")
        }
        .buttonStyle(ScaleButtonStyle())
        .frame(minWidth: AppLayoutConstants.minTouchTarget, minHeight: AppLayoutConstants.minTouchTarget)
        .frame(minHeight: cellHeight)
        .task { image = logManager.loadImage(for: log) }
    }

    private func formatCellDuration(_ d: TimeInterval) -> String {
        let s = Int(d)
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m \(s % 60)s"
    }
}

private struct DetailSheet: View {
    let log: ClearLog
    @ObservedObject var logManager: LogManager
    var onDelete: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var draftLabel: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let image = logManager.loadImage(for: log) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(16)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .black.opacity(0.18), radius: 14, y: 10)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Item name")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Name", text: $draftLabel)
                                .font(.headline)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .onSubmit {
                                    let trimmed = draftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty, trimmed != log.label else { return }
                                    logManager.update(id: log.id, label: trimmed)
                                }
                        }
                        if let loc = log.location, !loc.isEmpty {
                            Text("Location: \(loc)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("Cleared \(log.timestamp.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 24)

                    Button(role: .destructive, action: onDelete) {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                            Text("Delete")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppLayoutConstants.minTouchTarget)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("Delete this entry")
                    .accessibilityHint("Removes this item from the Focus Log")
                }
                .frame(maxWidth: horizontalSizeClass == .regular ? AppLayoutConstants.sheetMaxWidth : .infinity)
                .frame(maxWidth: .infinity)
                .padding(horizontalSizeClass == .regular ? 24 : 16)
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(horizontalSizeClass == .regular ? .large : .inline)
            .onAppear {
                draftLabel = log.label
            }
        }
    }
}
