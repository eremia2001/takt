import SwiftUI
import TaktCore

/// Bereich „Projekte“: aktive Projekte (per Ziehen sortierbar) mit heutiger Zeit,
/// darunter das einklappbare Archiv.
struct ProjectsView: View {
    @Environment(TaktStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    @State private var selection: Project.ID?
    @State private var editorDraft: ProjectDraft?
    @State private var isArchiveExpanded = false

    private var theme: DesignTheme { DesignTheme(scheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("Aktiv")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(store.projects.count)")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.tertiary)
                Spacer()
                OutlinePillButton(title: "Projekt", theme: theme) {
                    editorDraft = ProjectDraft(project: nil)
                }
                .help("Neues Projekt anlegen")
            }
            .padding(.horizontal, 28)

            list
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editorDraft) { draft in
            ProjectEditor(draft: draft)
        }
    }

    // MARK: Liste

    private var list: some View {
        List(selection: $selection) {
            Section {
                ForEach(Array(store.projects.enumerated()), id: \.element.id) { index, project in
                    ProjectRow(project: project, isFirst: index == 0, theme: theme) {
                        ProjectTodayTotal(project: project, theme: theme)
                    }
                    .tag(project.id)
                    .modifier(PlainRow())
                }
                .onMove { source, destination in
                    store.reorder(fromOffsets: source, toOffset: destination)
                }
            }

            if !store.archivedProjects.isEmpty {
                Section {
                    if isArchiveExpanded {
                        ForEach(Array(store.archivedProjects.enumerated()), id: \.element.id) { index, project in
                            ProjectRow(project: project, isFirst: index == 0, theme: theme) {
                                Button("Wiederherstellen") { store.unarchive(project) }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .tag(project.id)
                            .modifier(PlainRow())
                        }
                    }
                } header: {
                    archiveHeader
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        // Der Inset-Stil rückt um 16 pt ein, die Zeilen um weitere 10 pt → Inhalt bei 28 pt.
        .padding(.horizontal, 2)
        .contextMenu(forSelectionType: Project.ID.self) { ids in
            if let project = project(for: ids) {
                Button("Bearbeiten …") { edit(project) }
                if project.isArchived {
                    Button("Wiederherstellen") { store.unarchive(project) }
                } else {
                    Button("Archivieren") { store.archive(project) }
                }
            }
        } primaryAction: { ids in
            if let project = project(for: ids) { edit(project) }
        }
        .overlay {
            if store.projects.isEmpty && store.archivedProjects.isEmpty {
                Text("Noch keine Projekte")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var archiveHeader: some View {
        Button {
            withAnimation { isArchiveExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isArchiveExpanded ? 90 : 0))
                Text("Archiviert (\(store.archivedProjects.count))")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(theme.tertiary)
            .padding(.top, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Aktionen

    private func project(for ids: Set<Project.ID>) -> Project? {
        guard let id = ids.first else { return nil }
        return store.project(id: id)
    }

    private func edit(_ project: Project) {
        editorDraft = ProjectDraft(project: project)
    }
}

// MARK: - Zeile

/// Listenzeile ohne Systemabstände und -trenner; die Zeile zeichnet ihre Haarlinie selbst.
private struct PlainRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
            .listRowSeparator(.hidden)
    }
}

private struct ProjectRow<Accessory: View>: View {
    let project: Project
    let isFirst: Bool
    let theme: DesignTheme
    @ViewBuilder var accessory: () -> Accessory

    @Environment(TaktStore.self) private var store

    private var isRunning: Bool { store.running?.project.id == project.id }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Capsule()
                .fill(Color(hex: project.colorHex).opacity(project.isArchived ? 0.45 : 1))
                .frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(project.isArchived ? .secondary : .primary)
                        .lineLimit(1)
                    if isRunning {
                        Text("läuft")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: project.colorHex))
                    }
                    if project.playlistURI != nil {
                        Image(systemName: "music.note")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.tertiary)
                            .help("Mit Spotify-Playlist")
                    }
                }
                Text(project.isBusiness ? "Business" : "Privat")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            accessory()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle().fill(theme.hairline).frame(height: 1).padding(.leading, 17)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Heutige Zeit des Projekts; läuft es, minütlich aktualisiert.
private struct ProjectTodayTotal: View {
    let project: Project
    let theme: DesignTheme

    @Environment(TaktStore.self) private var store

    var body: some View {
        if let entry = store.running?.entry, entry.projectId == project.id {
            TimelineView(.periodic(from: entry.startedAt, by: 60)) { context in
                label(store.todayTotal(projectId: project.id, at: context.date))
            }
        } else {
            label(store.todayTotal(projectId: project.id, at: .now))
        }
    }

    private func label(_ total: TimeInterval) -> some View {
        Text(DurationFormat.hourMinute(total))
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(total >= 60 ? AnyShapeStyle(.primary) : AnyShapeStyle(theme.tertiary))
            .frame(width: 44, alignment: .trailing)
            .help("Heute")
            .accessibilityLabel("Heute \(DurationFormat.hourMinute(total))")
    }
}
