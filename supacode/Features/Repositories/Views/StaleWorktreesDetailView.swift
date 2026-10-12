import AppKit
import ComposableArchitecture
import SupacodeSettingsShared
import SwiftUI

struct StaleWorktreesDetailView: View {
  @Bindable var store: StoreOf<RepositoriesFeature>
  @State private var collapsedRepositoryIDs: Set<Repository.ID> = []
  @State private var selectedStaleWorktreeIDs: Set<Worktree.ID> = []

  var body: some View {
    let groups = store.state.staleWorktreesByRepository()
    let groupIDs = Set(groups.map(\.repository.id))
    let staleRowIDs: [Worktree.ID] = groups.flatMap { $0.rows.map(\.id) }
    let staleWorktreeIDs = Set(staleRowIDs)
    let selectedPairs = selectedTargets(groups: groups)
    let archiveTargets = selectedPairs.map {
      RepositoriesFeature.ArchiveWorktreeTarget(worktreeID: $0.worktreeID, repositoryID: $0.repositoryID)
    }
    let deleteTargets = selectedPairs
    let confirmAlert = store.state.confirmWorktreeAlert
    if groups.isEmpty {
      ContentUnavailableView(
        "Stale Worktrees",
        systemImage: "clock.badge.xmark",
        description: Text("Worktrees with nothing on them, or untouched for a while, show up here.")
      )
    } else {
      List(selection: $selectedStaleWorktreeIDs) {
        ForEach(Array(groups.enumerated()), id: \.element.repository.id) { index, group in
          Section {
            if !collapsedRepositoryIDs.contains(group.repository.id) {
              ForEach(group.rows) { row in
                StaleWorktreeRowView(
                  row: row,
                  customTitle: store.state.sidebarItems[id: row.id]?.customTitle,
                  customTint: store.state.sidebarItems[id: row.id]?.customTint,
                  onArchive: {
                    store.send(.requestArchiveWorktree(row.id, group.repository.id))
                  },
                  onDelete: {
                    store.send(
                      .requestDeleteSidebarItems([
                        RepositoriesFeature.DeleteWorktreeTarget(
                          worktreeID: row.id,
                          repositoryID: group.repository.id
                        )
                      ])
                    )
                  }
                )
                .tag(row.id)
                .typeSelectEquivalent("")
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
              }
            }
          } header: {
            StaleWorktreeSectionHeader(
              name: Repository.sidebarDisplayName(
                custom: store.state.sidebar.customTitle(for: group.repository),
                fallback: group.repository.name
              ),
              worktreeCount: group.rows.count,
              isCollapsed: collapsedRepositoryIDs.contains(group.repository.id),
              showsTopSeparator: index > 0,
              onToggle: { toggleSection(group.repository.id) }
            )
          }
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
      .onChange(of: groupIDs) { _, newValue in
        collapsedRepositoryIDs = collapsedRepositoryIDs.intersection(newValue)
      }
      .onChange(of: staleWorktreeIDs) { _, newValue in
        selectedStaleWorktreeIDs = selectedStaleWorktreeIDs.intersection(newValue)
      }
      .animation(.easeOut(duration: 0.2), value: staleRowIDs)
      .focusedAction(
        \.deleteWorktreeAction,
        enabled: !deleteTargets.isEmpty,
        token: deleteTargets
      ) {
        store.send(.requestDeleteSidebarItems(deleteTargets))
      }
      .focusedSceneAction(
        \.confirmWorktreeAction,
        enabled: confirmAlert != nil,
        token: confirmAlert
      ) {
        if let alert = confirmAlert {
          store.send(.alert(.presented(alert)))
        }
      }
      .toolbar {
        let deleteShortcut = KeyboardShortcut(.delete, modifiers: [.command, .shift]).display
        Button("Archive Selected", systemImage: "archivebox") {
          guard !archiveTargets.isEmpty else { return }
          store.send(.requestArchiveWorktrees(archiveTargets))
        }
        .help("Archive the selected worktrees")
        .disabled(archiveTargets.isEmpty)
        Button("Delete Selected", systemImage: "trash", role: .destructive) {
          guard !deleteTargets.isEmpty else { return }
          store.send(.requestDeleteSidebarItems(deleteTargets))
        }
        .help("Delete Selected (\(deleteShortcut))")
        .disabled(deleteTargets.isEmpty)
      }
    }
  }

  private func selectedTargets(
    groups: [(repository: Repository, rows: [RepositoriesFeature.State.StaleWorktreeRow])]
  ) -> [RepositoriesFeature.DeleteWorktreeTarget] {
    var targets: [RepositoriesFeature.DeleteWorktreeTarget] = []
    for group in groups {
      for row in group.rows where selectedStaleWorktreeIDs.contains(row.id) {
        targets.append(
          RepositoriesFeature.DeleteWorktreeTarget(worktreeID: row.id, repositoryID: group.repository.id)
        )
      }
    }
    return targets
  }

  private func toggleSection(_ repositoryID: Repository.ID) {
    withAnimation(.easeOut(duration: 0.2)) {
      if collapsedRepositoryIDs.contains(repositoryID) {
        collapsedRepositoryIDs.remove(repositoryID)
      } else {
        collapsedRepositoryIDs.insert(repositoryID)
      }
    }
  }
}

private struct StaleWorktreeRowView: View {
  let row: RepositoriesFeature.State.StaleWorktreeRow
  let customTitle: String?
  let customTint: RepositoryColor?
  let onArchive: () -> Void
  let onDelete: () -> Void
  // The system paints selected rows with white-on-blue chrome; the custom tint must yield so the
  // selected row stays readable (matches `ArchivedWorktreeRowView`).
  @Environment(\.backgroundProminence) private var backgroundProminence

  var body: some View {
    let deleteShortcut = KeyboardShortcut(.delete, modifiers: [.command, .shift]).display
    let bodyFontAscender = NSFont.preferredFont(forTextStyle: .body).ascender
    let displayName =
      SidebarDisplayName.resolved(custom: customTitle, fallback: row.worktree.name)
      ?? row.worktree.name
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: "clock.badge.xmark")
          .appFont(.caption)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
          .frame(width: 16, height: 16)
          .alignmentGuide(.firstTextBaseline) { _ in
            bodyFontAscender
          }
        let titleText = Text(displayName)
          .appFont(.body)
          .lineLimit(1)
        if let customTint, backgroundProminence != .increased {
          titleText.foregroundStyle(customTint.color)
        } else {
          titleText
        }
        Spacer(minLength: 8)
        HStack(spacing: 8) {
          Button {
            onArchive()
          } label: {
            Image(systemName: "archivebox")
              .accessibilityLabel("Archive worktree")
          }
          .buttonStyle(.plain)
          .help("Archive Worktree")
          Button(role: .destructive) {
            onDelete()
          } label: {
            Image(systemName: "trash")
              .accessibilityLabel("Delete worktree")
          }
          .buttonStyle(.plain)
          .help("Delete Worktree (\(deleteShortcut))")
        }
      }
      HStack(spacing: 6) {
        Text(row.reason.title)
          .foregroundStyle(.secondary)
        if let lastFocusedAt = row.lastFocusedAt {
          Text("Last opened \(lastFocusedAt.formatted(.relative(presentation: .named)))")
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        if let ahead = row.ahead {
          Label("+\(ahead)", systemImage: "arrow.up")
            .labelStyle(.titleAndIcon)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .help("\(ahead) commit\(ahead == 1 ? "" : "s") ahead of the base branch")
        }
      }
      .appFont(.caption)
      .lineLimit(1)
      .frame(minHeight: 14)
      .padding(.leading, 24)
    }
    .frame(height: 50, alignment: .center)
  }
}

private struct StaleWorktreeSectionHeader: View {
  let name: String
  let worktreeCount: Int
  let isCollapsed: Bool
  let showsTopSeparator: Bool
  let onToggle: () -> Void

  var body: some View {
    Button {
      onToggle()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "chevron.right")
          .appFont(.caption2)
          .rotationEffect(.degrees(isCollapsed ? 0 : 90))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        Text(name)
          .appFont(.headline)
          .foregroundStyle(.primary)
          .lineLimit(1)
        Text("(\(worktreeCount))")
          .appFont(.headline)
          .foregroundStyle(.secondary)
        Spacer()
      }
      .padding(.top, 6)
      .contentShape(.rect)
    }
    .overlay(alignment: .top) {
      if showsTopSeparator {
        Rectangle()
          .fill(.secondary)
          .frame(height: 1)
          .frame(maxWidth: .infinity)
          .accessibilityHidden(true)
      }
    }
    .buttonStyle(.plain)
    .help(isCollapsed ? "Expand repository section" : "Collapse repository section")
    .textCase(nil)
  }
}
