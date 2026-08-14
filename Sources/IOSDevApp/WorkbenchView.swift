import AppKit
import IOSDevCore
import SwiftUI
import UniformTypeIdentifiers

private enum Studio {
  static let backdrop = Color(red: 0.965, green: 0.968, blue: 0.974)
  static let surface = Color.white
  static let raised = Color(red: 0.955, green: 0.96, blue: 0.968)
  static let separator = Color.black.opacity(0.055)
  static let secondary = Color(nsColor: .secondaryLabelColor)
  static let tertiary = Color(nsColor: .tertiaryLabelColor)
  static let accent = Color(red: 0.04, green: 0.39, blue: 0.95)
  static let accentSoft = Color(red: 0.91, green: 0.95, blue: 1)
  static let success = Color(red: 0.32, green: 0.70, blue: 0.38)
  static let warning = Color.orange
  static let panelRadius: CGFloat = 14
}

private extension String {
  var nonempty: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}

public struct WorkbenchView: View {
  @EnvironmentObject var model: AppModel

  public init() {}

  public var body: some View {
    GeometryReader { viewport in
      VStack(spacing: 0) {
        let compact = viewport.size.height < 820
        LysToolbar()
          .layoutPriority(2)
        Divider().overlay(Studio.separator)
        HStack(spacing: 0) {
          NavigationRail()
          Divider().overlay(Studio.separator)
          VStack(spacing: 0) {
            content(viewportWidth: viewport.size.width)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .clipped()
              .layoutPriority(0)
            EvidenceWorkspace()
              .frame(
                minHeight: model.isEvidenceWorkspaceOpen ? (compact ? 132 : 180) : 52,
                idealHeight: model.isEvidenceWorkspaceOpen ? (compact ? 150 : 240) : 52,
                maxHeight: model.isEvidenceWorkspaceOpen ? (compact ? 158 : 240) : 52)
              .layoutPriority(2)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .layoutPriority(0)
        Divider().overlay(Studio.separator)
        TaskActionBar()
          .frame(height: compact ? 54 : 62)
          .layoutPriority(2)
      }
      .frame(width: viewport.size.width, height: viewport.size.height, alignment: .top)
      .clipped()
    }
    .background(Studio.backdrop)
    .foregroundStyle(Color(nsColor: .labelColor))
    .tint(Studio.accent)
    .alert(
      "Lys",
      isPresented: Binding(
        get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })
    ) {
      Button("OK") { model.notice = nil }
    } message: {
      Text(model.notice ?? "")
    }
  }

  @ViewBuilder private func content(viewportWidth: CGFloat) -> some View {
    switch model.section {
    case .agent:
      let narrow = viewportWidth < 1400
      let agentPanelWidth: CGFloat = narrow ? 340 : 380
      HStack(spacing: 12) {
        AgentPanel().frame(width: agentPanelWidth * 1.05)
        AppStage()
          .frame(maxWidth: .infinity)
      }
      .padding(.top, 21)
      .padding(.leading, 23)
      .padding(.trailing, 24)
      .padding(.bottom, 12)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .code:
      CodeWorkspace()
    case .git:
      DeployWorkspace()
    case .changes:
      GitWorkspace()
    case .settings:
      SettingsWorkspace()
    }
  }
}

private struct TerminalDrawer: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Button(action: model.toggleTerminal) {
          HStack(spacing: 8) {
            Image(systemName: "terminal")
              .font(.system(size: 12, weight: .medium))
            Text("Terminal")
              .font(.system(size: 11.5, weight: .semibold))
            Text("⌘J")
              .font(.system(size: 9.5, weight: .medium).monospaced())
              .foregroundStyle(Studio.tertiary)
            if let latest = model.terminalEntries.last {
              Circle().fill(stateColor(latest.state)).frame(width: 7, height: 7)
              Text(latestSummary(latest))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Studio.secondary)
                .lineLimit(1)
            } else {
              Text("Commands and output appear here")
                .font(.system(size: 10))
                .foregroundStyle(Studio.secondary)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Spacer()
        if !model.terminalEntries.isEmpty {
          Button("Copy Latest", action: copyLatest)
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
          Button("Clear", action: model.clearTerminal)
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .disabled(model.terminalEntries.contains(where: { $0.state == .running }))
        }
        Button(action: model.toggleTerminal) {
          Image(systemName: model.isTerminalExpanded ? "chevron.down" : "chevron.up")
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.isTerminalExpanded ? "Collapse terminal" : "Expand terminal")
      }
      .padding(.leading, 104).padding(.trailing, 18)
      .frame(height: 36)
      .background(Studio.surface)

      if model.isTerminalExpanded {
        Divider().overlay(Color.white.opacity(0.1))
        terminalTranscript
          .frame(height: 190)
          .transition(.opacity)
      }
    }
  }

  private var terminalTranscript: some View {
    TerminalTranscriptView(entries: model.terminalEntries)
  }

  private func latestSummary(_ entry: TerminalEntry) -> String {
    switch entry.state {
    case .running: "Running"
    case .succeeded: "Last command passed"
    case .failed: "Last command failed"
    case .cancelled: "Last command cancelled"
    }
  }

  private func stateColor(_ state: TerminalEntry.State) -> Color {
    switch state {
    case .running: Studio.accent
    case .succeeded: Studio.success
    case .failed: .red
    case .cancelled: Studio.secondary
    }
  }

  private func copyLatest() {
    guard let entry = model.terminalEntries.last else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(
      "\(entry.workingDirectory) % \(entry.command)\n\(entry.output)", forType: .string)
  }
}

private struct LysToolbar: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    HStack(spacing: 0) {
      LysLogoView(width: 60, height: 42)
        .padding(.leading, 22)
        .frame(width: 100, alignment: .leading)

      Divider().frame(height: 28).overlay(Studio.separator)
        .padding(.horizontal, 17.5)

      Menu {
        Button("Open Repository…") { model.chooseRepository() }
        if !model.containers.isEmpty {
          Divider()
          ForEach(model.containers, id: \.path) { container in
            Button(container.lastPathComponent) { model.selectContainer(container) }
          }
        }
        if model.needsExpoPreparation {
          Divider()
          Button("Prepare Expo iOS Project…", systemImage: "hammer") {
            model.prepareExpoProject()
          }
        }
      } label: {
        ToolbarControl(
          symbol: "cube", title: model.repository?.lastPathComponent ?? "Open Project",
          width: 126)
      }
      .menuStyle(.borderlessButton)
      .tint(Color(nsColor: .labelColor))
      .frame(width: 126, height: 40)
      .background(Studio.surface)
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(Studio.separator, lineWidth: 1)
      }
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .padding(.trailing, 21)

      Menu {
        if model.branchName == "—" || model.branchName.isEmpty {
          Text("No branch detected")
        } else {
          Text(model.branchName)
        }
        if model.isGitRepository {
          Divider()
          Button("Open Changes", systemImage: "doc.text.magnifyingglass") { model.section = .changes }
        }
      } label: {
        ToolbarControl(symbol: "arrow.triangle.branch", title: model.branchName, width: 117)
      }
      .menuStyle(.borderlessButton)
      .tint(Color(nsColor: .labelColor))
      .frame(width: 117, height: 40)
      .background(Studio.surface)
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(Studio.separator, lineWidth: 1)
      }
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .padding(.trailing, 22)

      Menu {
        if !model.destinations.isEmpty {
          ForEach(model.destinations) { destination in
            Button("\(destination.name) · \(runtimeName(destination.runtime))") {
              model.selectDestination(destination.udid)
            }
          }
          Divider()
        } else {
          Text("No simulators found")
        }
        Button("Refresh Simulators", systemImage: "arrow.clockwise") {
          model.refreshSimulators()
        }
        Button("Simulator Settings…", systemImage: "gearshape") { model.section = .settings }
      } label: {
        ToolbarControl(
          symbol: "iphone",
          title: model.selectedDestination.map {
            "\($0.name) · \(runtimeName($0.runtime))"
          }
            ?? "Select Simulator", width: 232)
      }
      .menuStyle(.borderlessButton)
      .tint(Color(nsColor: .labelColor))
      .frame(width: 232, height: 40)
      .background(Studio.surface)
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(Studio.separator, lineWidth: 1)
      }
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

      Spacer(minLength: 12)

      HStack(spacing: 7) {
        Circle().fill(statusColor).frame(width: 8, height: 8)
        Text(model.status).font(.system(size: 12, weight: .medium)).lineLimit(1)
        if model.isBusy { ProgressView().controlSize(.small).scaleEffect(0.72) }
      }
      .padding(.horizontal, 10)
      .frame(width: 125, height: 40)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Status: \(model.status)")

      Button(action: model.run) {
        Label("Run", systemImage: "play.fill")
          .font(.system(size: 12, weight: .semibold))
          .frame(width: 92, height: 40)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(Color.primary)
      .background(Studio.surface)
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(Studio.separator, lineWidth: 1)
      }
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .disabled(!model.canRun)

      ToolbarMoreButton()
      .padding(.leading, 16)
      .padding(.trailing, 24)
    }
    .frame(height: 72)
    .background(Studio.surface)
  }

  private var statusColor: Color {
    if model.status.contains("failed") || model.status.contains("blocked") { return Studio.warning }
    if model.isBusy { return Studio.accent }
    if model.repository == nil { return Studio.tertiary }
    return model.status == "Running" ? Studio.success : Studio.secondary
  }
}

private struct ToolbarControl: View {
  let symbol: String
  let title: String
  let width: CGFloat

  var body: some View {
    ZStack(alignment: .leading) {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Studio.surface)
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Studio.separator, lineWidth: 1)
        }
      HStack(spacing: 8) {
        Image(systemName: symbol).font(.system(size: 13, weight: .medium))
        Text(title).lineLimit(1)
        Spacer(minLength: 0)
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(Studio.secondary)
      }
      .font(.system(size: 12, weight: .medium))
      .padding(.horizontal, 12)
    }
    .frame(width: width, height: 40)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .contentShape(Rectangle())
    .shadow(color: .black.opacity(0.014), radius: 4, y: 1)
  }
}

private struct ToolbarMoreButton: View {
  @EnvironmentObject var model: AppModel
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Studio.surface)
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .stroke(Studio.separator, lineWidth: 1)
          }
        Image(systemName: "ellipsis")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Color.primary)
      }
      .frame(width: 52, height: 40)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: 2) {
        Button("Build", action: model.build)
          .disabled(!model.canBuild)
        Button("Stop", action: model.stop)
          .disabled(!model.isBusy)
        if model.isExpoRepository {
          Divider()
          Toggle("Start Expo development server", isOn: $model.startDevServerOnRun)
        }
      }
      .padding(10)
      .frame(width: 220, alignment: .leading)
    }
    .help("More run actions")
  }
}

private struct NavigationRail: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    let primarySections: [PrimarySection] = [.agent, .code, .git]
    VStack(alignment: .leading, spacing: 6) {
      ForEach(primarySections) { section in
        railButton(section)
      }

      Spacer(minLength: 10)
      railButton(.settings)
    }
    .padding(.top, 26)
    .padding(.bottom, 20)
    .frame(minWidth: 156, maxWidth: 156, maxHeight: .infinity, alignment: .topLeading)
    .background(Studio.surface)
  }

  private func railButton(_ section: PrimarySection) -> some View {
    let isSelected = model.section == section
    return Button {
      model.section = section
    } label: {
      HStack(spacing: 8) {
        Image(systemName: section.symbol)
          .symbolVariant(isSelected ? .fill : .none)
          .font(.system(size: 17, weight: .regular))
          .frame(width: 24, height: 30)
        Text(section.rawValue)
          .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
          .fixedSize(horizontal: true, vertical: false)
        Spacer(minLength: 0)
      }
      .foregroundStyle(isSelected ? Studio.accent : Studio.secondary)
      .padding(.horizontal, 8)
      .frame(width: 124, height: 42)
      .background(isSelected ? Studio.accentSoft : .clear)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.leading, 15)
    .accessibilityLabel(section.rawValue)
  }
}

private struct AgentPanel: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Text("Agent")
          .font(.system(size: 15, weight: .semibold))
        Spacer()
        Button(action: model.clearAgentActivity) {
          HStack(spacing: 6) {
            Text("Clear")
            Image(systemName: "trash")
          }
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Studio.secondary)
          .frame(minWidth: 58, minHeight: 40, alignment: .trailing)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sessionItems.isEmpty || model.isBusy || model.pendingAgentPermission != nil)
        .help("Clear messages and agent actions from this session")
        .accessibilityLabel("Clear agent session activity")
        if model.canStopAgent {
          Button(action: model.stopAgent) {
            Image(systemName: "stop.circle")
              .font(.system(size: 15, weight: .medium))
              .frame(width: 40, height: 40)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.red)
          .help("Stop the agent while preserving the running app and development server")
          .accessibilityLabel("Stop agent")
        }
      }
      .padding(.horizontal, 20)
      .frame(height: 56)

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            if sessionItems.isEmpty {
              VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                  .font(.system(size: 20, weight: .light))
                  .foregroundStyle(Studio.tertiary)
                Text(emptySessionTitle)
                  .font(.system(size: 11.5, weight: .semibold))
                Text(emptySessionDetail)
                  .font(.system(size: 10.5))
                  .foregroundStyle(Studio.secondary)
                  .multilineTextAlignment(.center)
                  .fixedSize(horizontal: false, vertical: true)
              }
              .frame(maxWidth: .infinity)
              .padding(.horizontal, 24)
              .padding(.top, 42)
            } else {
              ForEach(sessionItems) { item in
                AgentSessionItem(item: item)
                  .id(item.id)
              }
            }
          }
          .background(alignment: .leading) {
            if sessionItems.count > 1 {
              Rectangle()
                .fill(Studio.separator)
                .frame(width: 1)
                .padding(.leading, 29)
                .padding(.vertical, 24)
                .accessibilityHidden(true)
            }
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 18)
        }
        .scrollIndicators(.automatic)
        .onAppear { scrollToLatest(using: proxy) }
        .onChange(of: sessionScrollSignal) { _, _ in scrollToLatest(using: proxy) }
      }

      if let permission = model.pendingAgentPermission {
        Divider().overlay(Studio.separator)
        AgentPermissionCard(permission: permission)
          .padding(.horizontal, 16)
          .padding(.vertical, 14)
      }

      VStack(alignment: .leading, spacing: 6) {
        VStack(spacing: 0) {
          HStack(alignment: .bottom, spacing: 8) {
            ZStack(alignment: .topLeading) {
              if model.taskPrompt.isEmpty {
                Text(
                  model.hasAgentSession
                    ? "Ask Lys to change something or test the app…"
                    : "Ask the agent to change something or test the app…"
                )
                .font(.system(size: 12))
                .foregroundStyle(Studio.secondary)
                .padding(.horizontal, 4).padding(.vertical, 8)
                .allowsHitTesting(false)
              }
              AgentComposerEditor(text: $model.taskPrompt, onSubmit: model.sendAgentPrompt)
                .frame(minHeight: 38, maxHeight: 74)
                .accessibilityLabel("Agent message")
            }
            Button(action: model.sendAgentPrompt) {
              Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(model.canSendAgentPrompt ? Studio.accent : Studio.tertiary.opacity(0.55))
                .clipShape(Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canSendAgentPrompt)
            .keyboardShortcut(.return, modifiers: [.command])
            .help(model.agentComposerBlocker ?? "Send message (Command–Return)")
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .frame(minHeight: 64)

          Divider().overlay(Studio.separator.opacity(0.58))

          AgentConfigurationBar()
            .padding(.horizontal, 10)
            .frame(height: 46)
        }
        .background(Studio.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Studio.separator, lineWidth: 1))

        if let blocker = model.agentComposerBlocker {
          Text(blocker)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(Studio.warning)
            .lineLimit(2)
            .padding(.horizontal, 2)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 14)
      .padding(.bottom, 16)
    }
    .background(Studio.surface)
    .clipShape(RoundedRectangle(cornerRadius: Studio.panelRadius, style: .continuous))
    .shadow(color: .black.opacity(0.022), radius: 14, y: 4)
  }

  private var sessionItems: [TimelineItem] {
    model.timeline.filter { $0.category != .system }
  }

  private var sessionScrollSignal: String {
    guard let latest = sessionItems.last else { return "empty" }
    return "\(latest.id.uuidString):\(latest.detail.count):\(latest.state)"
  }

  private func scrollToLatest(using proxy: ScrollViewProxy) {
    guard let latestID = sessionItems.last?.id else { return }
    DispatchQueue.main.async {
      proxy.scrollTo(latestID, anchor: .bottom)
    }
  }

  private var emptySessionTitle: String {
    model.repository == nil ? "Open a repository to begin" : "Describe a task to begin"
  }

  private var emptySessionDetail: String {
    model.repository == nil
      ? "Session messages and agent actions will appear here."
      : "Your messages, agent replies, and tool actions stay together here."
  }
}

private struct TaskSummaryCard: View {
  let summary: TaskCompletionSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 8) {
        Image(systemName: summary.passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
          .foregroundStyle(summary.passed ? Studio.success : Studio.warning)
        Text(summary.title).font(.system(size: 12, weight: .semibold))
      }
      summaryLine("Done", summary.done)
      summaryLine("Worked", summary.worked)
      summaryLine("Still lacking", summary.lacking)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background((summary.passed ? Studio.success : Studio.warning).opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Test summary. \(summary.done) \(summary.worked) \(summary.lacking)")
  }

  private func summaryLine(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label.uppercased())
        .font(.system(size: 8.5, weight: .bold))
        .foregroundStyle(Studio.secondary)
      Text(value).font(.system(size: 10.5)).fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct PlanActivityRow: View {
  let index: Int
  let item: TaskPlanItem
  let detail: String
  let duration: String?
  let activeMarkComplete: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 13) {
      PlanStateMark(state: item.state, activeMarkComplete: activeMarkComplete)
        .frame(width: 18, height: 18)
      VStack(alignment: .leading, spacing: 3) {
        Text(item.title)
          .font(.system(size: 11.5, weight: item.state == .active ? .semibold : .medium))
          .lineLimit(2)
        Text(detail)
          .font(.system(size: 10))
          .foregroundStyle(Studio.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
      if item.state == .active {
        Circle()
          .trim(from: 0.08, to: 0.84)
          .stroke(Studio.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
          .frame(width: 15, height: 15)
          .rotationEffect(.degrees(-35))
      } else if let duration {
        Text(duration)
          .font(.system(size: 10).monospacedDigit())
          .foregroundStyle(Studio.secondary)
      }
    }
    .padding(.vertical, activeMarkComplete ? 10 : 8)
  }
}

private struct JourneyProgressSection: View {
  let journey: JourneyRecord

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Divider().overlay(Studio.separator)
      HStack(spacing: 8) {
        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(statusColor)
        Text("App journey").font(.system(size: 12, weight: .semibold))
        Spacer()
        Text(progressLabel)
          .font(.system(size: 10.5, weight: .medium).monospacedDigit())
          .foregroundStyle(statusColor)
      }
      Text(journey.goal)
        .font(.system(size: 11))
        .foregroundStyle(Studio.secondary)
        .lineLimit(2)
      if journey.steps.isEmpty {
        HStack(spacing: 8) {
          ProgressView().controlSize(.mini)
          Text(
            journey.status == .ready
              ? "Reading the current interface and choosing semantic actions."
              : "Attaching to the selected running app."
          )
          .font(.system(size: 10.5))
          .foregroundStyle(Studio.secondary)
        }
      } else {
        VStack(spacing: 8) {
          ForEach(journey.steps) { result in
            HStack(alignment: .top, spacing: 9) {
              JourneyStepMark(status: result.status)
              VStack(alignment: .leading, spacing: 2) {
                Text(result.step.title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                if !result.detail.isEmpty {
                  Text(result.detail).font(.system(size: 9.5)).foregroundStyle(Studio.secondary)
                    .lineLimit(2)
                }
              }
              Spacer(minLength: 0)
            }
          }
        }
      }
      if let fingerprint = journey.currentFingerprint {
        Text("Screen \(String(fingerprint.digest.prefix(10)))")
          .font(.system(size: 9).monospaced())
          .foregroundStyle(Studio.tertiary)
          .help("Current automatically observed App Graph state")
      }
    }
  }

  private var completedCount: Int {
    journey.steps.filter { $0.status == .passed }.count
  }
  private var progressLabel: String {
    if journey.steps.isEmpty { return journey.status.rawValue.replacingOccurrences(of: "CurrentApp", with: "") }
    return "\(completedCount)/\(journey.steps.count) · \(journey.status.rawValue)"
  }
  private var statusColor: Color {
    switch journey.status {
    case .passed: Studio.success
    case .failed, .cancelled: Studio.warning
    case .preparing, .ready, .running: Studio.accent
    }
  }
}

private struct JourneyStepMark: View {
  let status: JourneyStepStatus

  var body: some View {
    Group {
      switch status {
      case .waiting:
        Circle().stroke(Studio.tertiary, lineWidth: 1).frame(width: 11, height: 11)
      case .running:
        ProgressView().controlSize(.mini).frame(width: 11, height: 11)
      case .passed:
        Image(systemName: "checkmark.circle.fill").foregroundStyle(Studio.success)
      case .failed:
        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Studio.warning)
      }
    }
    .font(.system(size: 12, weight: .semibold))
    .padding(.top, 1)
  }
}

private struct AgentConfigurationBar: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    HStack(spacing: 0) {
      AgentModelSelector()
        .frame(maxWidth: .infinity, alignment: .leading)
      Divider()
        .frame(height: 26)
        .padding(.horizontal, 10)
      Text("Reasoning")
        .font(.system(size: 10.5))
        .foregroundStyle(Studio.secondary)
        .fixedSize()
      AgentEffortSelector()
        .fixedSize(horizontal: true, vertical: false)
    }
    .frame(height: 44)
    .accessibilityElement(children: .contain)
  }
}

private struct AgentModelSelector: View {
  @EnvironmentObject var model: AppModel
  @State private var isPresented = false
  @State private var search = ""
  @State private var browsedAdapterID = ""

  var body: some View {
    Button {
      browsedAdapterID = resolvedAdapterID
      search = ""
      isPresented = true
    } label: {
      HStack(spacing: 7) {
        AgentMark(id: selectedAdapter?.id ?? "", size: 16)
          .foregroundStyle(selectedAdapter?.executable == nil ? Studio.tertiary : Color.primary)
        Text(model.agentModelOption == nil ? "Choose model" : model.agentModelLabel)
          .font(.system(size: 11.5, weight: .medium))
          .foregroundStyle(model.agentModelOption == nil ? Studio.secondary : Color.primary)
          .lineLimit(1)
          .truncationMode(.middle)
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(Studio.secondary)
      }
      .padding(.horizontal, 3)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: 40)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      modelBrowser
    }
    .help("Choose an available agent and model")
    .accessibilityLabel("Model: \(model.agentModelLabel)")
  }

  private var modelBrowser: some View {
    HStack(spacing: 0) {
      providerRail
      Divider().overlay(Studio.separator)
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 9) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Studio.secondary)
          TextField("Search models…", text: $search)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .disabled(browsedAdapter?.executable == nil)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        Divider().overlay(Studio.separator)
        modelList
      }
    }
    .frame(width: 410, height: 390)
    .background(Studio.surface)
    .onAppear {
      browsedAdapterID = resolvedAdapterID
    }
  }

  private var providerRail: some View {
    VStack(spacing: 7) {
      ForEach(model.adapters) { adapter in
        Button {
          browsedAdapterID = adapter.id
          search = ""
          if adapter.executable != nil && adapter.id != model.selectedAdapterID {
            model.selectAgentAdapter(adapter.id)
          }
        } label: {
          ZStack(alignment: .bottomTrailing) {
            AgentMark(id: adapter.id, size: 22)
              .foregroundStyle(providerColor(adapter))
              .frame(width: 38, height: 38)
              .background(browsedAdapterID == adapter.id ? Studio.accentSoft : .clear)
              .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Circle()
              .fill(adapter.executable == nil ? Studio.tertiary : Studio.success)
              .frame(width: 7, height: 7)
              .overlay(Circle().stroke(Studio.surface, lineWidth: 1.5))
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.hasAgentSession && adapter.id != model.selectedAdapterID)
        .help(providerHelp(adapter))
        .accessibilityLabel(providerHelp(adapter))
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 12)
    .frame(width: 60)
    .background(Studio.raised.opacity(0.58))
  }

  @ViewBuilder private var modelList: some View {
    if let adapter = browsedAdapter {
      if adapter.executable == nil {
        modelUnavailable(adapter)
      } else if filteredModels.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: search.isEmpty ? "cpu" : "magnifyingglass")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(Studio.tertiary)
          Text(search.isEmpty ? "No models reported" : "No matching models")
            .font(.system(size: 12, weight: .semibold))
          Text(
            search.isEmpty
              ? "\(adapter.displayName) has not exposed a model list yet."
              : "Try a different model name."
          )
          .font(.system(size: 10.5))
          .foregroundStyle(Studio.secondary)
          .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let option = model.agentModelOption {
        ScrollView {
          LazyVStack(spacing: 4) {
            ForEach(filteredModels) { item in
              modelRow(item, option: option, adapter: adapter)
            }
          }
          .padding(10)
        }
        .scrollIndicators(.automatic)
      }
    } else {
      VStack(spacing: 8) {
        Image(systemName: "sparkles")
          .font(.system(size: 22, weight: .light))
          .foregroundStyle(Studio.tertiary)
        Text("No agents detected")
          .font(.system(size: 12, weight: .semibold))
        Text("Install or configure an ACP-compatible agent to choose a model.")
          .font(.system(size: 10.5))
          .foregroundStyle(Studio.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 230)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func modelRow(
    _ item: ACPConfigOptionValue, option: ACPConfigOption, adapter: DetectedAdapter
  ) -> some View {
    let selected = option.currentValue?.stringValue == item.value
    return Button {
      model.setAgentConfigOption(option, value: item)
      isPresented = false
    } label: {
      HStack(spacing: 11) {
        AgentMark(id: adapter.id, size: 17)
          .foregroundStyle(Studio.secondary)
          .frame(width: 20)
        Text(item.name)
          .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
          .foregroundStyle(Color.primary)
          .lineLimit(1)
        Spacer(minLength: 8)
        if selected {
          Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Studio.accent)
        }
      }
      .padding(.horizontal, 12)
      .frame(height: 44)
      .background(selected ? Studio.accentSoft : .clear)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!model.canChangeAgentConfigOption(option) || (model.hasAgentSession && model.isBusy))
    .help(item.description ?? "Use \(item.name)")
  }

  private func modelUnavailable(_ adapter: DetectedAdapter) -> some View {
    VStack(spacing: 9) {
      AgentMark(id: adapter.id, size: 25)
        .foregroundStyle(Studio.tertiary)
      Text("\(adapter.displayName) unavailable")
        .font(.system(size: 12.5, weight: .semibold))
      Text(adapter.limitation ?? "The ACP adapter is not installed or is not available on PATH.")
        .font(.system(size: 10.5))
        .foregroundStyle(Studio.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 240)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var selectedAdapter: DetectedAdapter? {
    model.adapters.first { $0.id == model.selectedAdapterID }
  }

  private var browsedAdapter: DetectedAdapter? {
    model.adapters.first { $0.id == resolvedAdapterID }
  }

  private var resolvedAdapterID: String {
    if model.adapters.contains(where: { $0.id == browsedAdapterID }) {
      return browsedAdapterID
    }
    if model.adapters.contains(where: { $0.id == model.selectedAdapterID }) {
      return model.selectedAdapterID
    }
    return model.adapters.first(where: { $0.executable != nil })?.id
      ?? model.adapters.first?.id ?? ""
  }

  private var filteredModels: [ACPConfigOptionValue] {
    guard resolvedAdapterID == model.selectedAdapterID,
      let values = model.agentModelOption?.options
    else { return [] }
    let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else { return values }
    return values.filter {
      $0.name.localizedCaseInsensitiveContains(term)
        || $0.value.localizedCaseInsensitiveContains(term)
        || ($0.description?.localizedCaseInsensitiveContains(term) ?? false)
    }
  }

  private func providerColor(_ adapter: DetectedAdapter) -> Color {
    if adapter.executable == nil { return Studio.tertiary }
    return browsedAdapterID == adapter.id ? Studio.accent : Studio.secondary
  }

  private func providerHelp(_ adapter: DetectedAdapter) -> String {
    if adapter.executable != nil { return "\(adapter.displayName) — available" }
    return "\(adapter.displayName) — unavailable. \(adapter.limitation ?? "ACP adapter not installed.")"
  }
}

private struct AgentEffortSelector: View {
  @EnvironmentObject var model: AppModel
  @State private var isPresented = false

  var body: some View {
    if let option = model.agentReasoningOption {
      Button {
        isPresented.toggle()
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "chart.bar.fill")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Studio.secondary)
          Text(model.agentReasoningLabel)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Color.primary)
          Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Studio.secondary)
        }
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .frame(height: 40)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .popover(isPresented: $isPresented, arrowEdge: .bottom) {
        VStack(spacing: 2) {
          ForEach(option.options) { item in
            Button {
              model.setAgentConfigOption(option, value: item)
              isPresented = false
            } label: {
              HStack(spacing: 12) {
                Text(item.name)
                  .font(.system(size: 11.5, weight: .medium))
                Spacer(minLength: 12)
                if option.currentValue?.stringValue == item.value {
                  Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Studio.accent)
                }
              }
              .padding(.horizontal, 10)
              .frame(width: 164, height: 34)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
        .padding(6)
        .background(Studio.surface)
      }
      .disabled(!model.canChangeAgentConfigOption(option) || (model.hasAgentSession && model.isBusy))
      .help(option.description ?? "Choose reasoning effort")
      .accessibilityLabel("Reasoning effort: \(model.agentReasoningLabel)")
    } else {
      Text("Effort unavailable")
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(Studio.tertiary)
        .padding(.leading, 8)
        .frame(height: 40)
        .help("The selected agent has not reported a reasoning effort control.")
    }
  }
}

private struct ExpoSetupCallout: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "hammer")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Studio.accent)
        .frame(width: 24, height: 24)
      VStack(alignment: .leading, spacing: 5) {
        Text("Expo needs an iOS project")
          .font(.system(size: 12, weight: .semibold))
        Text(
          "No .xcworkspace or .xcodeproj was found. Generate it here, then Lys will discover the scheme automatically."
        )
        .font(.system(size: 10.5)).foregroundStyle(Studio.secondary)
        .fixedSize(horizontal: false, vertical: true)
        Button("Prepare iOS Project…", action: model.prepareExpoProject)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(model.isBusy)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(Studio.accentSoft)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

private struct AppStage: View {
  @EnvironmentObject var model: AppModel
  @State private var previewZoom: CGFloat = 0.9
  @State private var landscape = false

  var body: some View {
    GeometryReader { geometry in
      let compact = geometry.size.height < 560
      let emptyState = model.currentScreenshotImage == nil
      let previewViewportWidth = max(0, geometry.size.width - 58)
      let widthFittedDeviceHeight = landscape
        ? max(300, previewViewportWidth - 44)
        : max(300, (previewViewportWidth - 44) / 0.505)
      let fittedDeviceHeight = min(
        650,
        max(360, min(geometry.size.height - (compact ? 180 : 100), widthFittedDeviceHeight)))
      let emptyDeviceHeight = min(
        700,
        max(420, min(geometry.size.height - (compact ? 78 : 92), widthFittedDeviceHeight)))
      let deviceHeight = compact
        ? max(300, min(geometry.size.height - 78, widthFittedDeviceHeight))
        : (emptyState ? emptyDeviceHeight : fittedDeviceHeight)

      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Menu {
            if model.schemes.isEmpty {
              Text("No app schemes discovered")
            } else {
              ForEach(model.schemes, id: \.self) { scheme in
                Button(scheme) { model.selectScheme(scheme) }
              }
            }
          } label: {
            HStack(spacing: 7) {
              Image(systemName: "app.badge")
              Text(model.selectedScheme.isEmpty ? "App" : model.selectedScheme)
              Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 11, weight: .semibold))
          }
          .menuStyle(.borderlessButton)
          if model.isExpoRepository {
            Button {
              model.startDevServerOnRun.toggle()
            } label: {
              HStack(alignment: .center, spacing: 8) {
                Image(
                  systemName: model.startDevServerOnRun
                    ? "bolt.horizontal.circle.fill" : "bolt.slash.circle"
                )
                .font(.system(size: 12, weight: .medium))
                .frame(width: 18, height: 18)
                Text(model.startDevServerOnRun ? "Metro on Run" : "Metro off")
                  .font(.system(size: 10, weight: .medium))
                  .lineLimit(2)
                  .multilineTextAlignment(.leading)
                  .fixedSize(horizontal: false, vertical: true)
              }
              .foregroundStyle(model.startDevServerOnRun ? Studio.success : Studio.secondary)
            }
            .buttonStyle(.plain)
            .help("Choose whether Run starts the Expo development server")
          }
          Spacer()
          orientationControls
          Divider().frame(height: 20).padding(.horizontal, 8)
          HStack(spacing: 2) {
            Button(action: model.refreshApp) {
              Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(
              model.selectedTarget == nil || model.isBusy ? Studio.tertiary : Studio.secondary)
            .disabled(model.selectedTarget == nil || model.isBusy)
            .accessibilityLabel("Refresh app")
            .help("Relaunch the installed app and capture a fresh screenshot")

            Button(action: model.stop) {
              Image(systemName: "stop.fill")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.isBusy ? Studio.warning : Studio.tertiary)
            .disabled(!model.isBusy)
            .accessibilityLabel("Stop current operation")
            .help("Stop the current operation")
          }
          Menu {
            Button(
              "Capture Screenshot", systemImage: "camera", action: model.captureCurrentScreenshot
            )
            .disabled(model.selectedTarget == nil)
          } label: {
            Image(systemName: "ellipsis")
              .frame(width: 32, height: 32)
              .contentShape(Rectangle())
          }
          .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 20)
        .frame(height: compact ? 38 : 44)

        HStack(spacing: 0) {
          ScrollView([.horizontal, .vertical]) {
            DevicePreview(height: deviceHeight * previewZoom, landscape: landscape)
              .padding(.horizontal, 22)
              .padding(.vertical, 8)
              .frame(
                minWidth: max(0, previewViewportWidth - 44),
                minHeight: max(0, geometry.size.height - (compact ? 78 : 98)), alignment: .center)
          }
          .frame(
            minWidth: previewViewportWidth, maxWidth: previewViewportWidth,
            maxHeight: .infinity)
          .scrollIndicators(.automatic)
          .background(Studio.backdrop)
          .clipped()
          InteractionPalette()
            .frame(width: 58)
            .frame(maxHeight: .infinity)
            .background(Studio.backdrop)
        }
        .background(Studio.backdrop)

        HStack(spacing: 0) {
          appearanceControls
          Divider().frame(height: 22).padding(.horizontal, 10)
          zoomControls
          Spacer(minLength: 10)
          if !compact {
            previewInteractionStatus
          }
        }
        .padding(.horizontal, 14)
        .frame(height: compact ? 40 : 48)
      }
    }
    .background(Studio.surface)
    .clipShape(RoundedRectangle(cornerRadius: Studio.panelRadius, style: .continuous))
    .shadow(color: .black.opacity(0.018), radius: 14, y: 4)
  }

  private var orientationControls: some View {
    HStack(spacing: 2) {
      orientationButton("Portrait", selected: !landscape) { landscape = false }
      orientationButton("Landscape", selected: landscape) { landscape = true }
    }
    .fixedSize()
  }

  private func orientationButton(
    _ title: String, selected: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(selected ? Color.primary : Studio.secondary)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(selected ? Studio.accentSoft : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var appearanceControls: some View {
    HStack(spacing: 2) {
      Image(systemName: "sun.max").foregroundStyle(Studio.secondary).frame(width: 30)
      appearanceButton(.light, title: "Light")
      appearanceButton(.dark, title: "Dark")
    }
    .fixedSize()
  }

  private var zoomControls: some View {
    HStack(spacing: 3) {
      Button {
        adjustZoom(by: -0.1)
      } label: {
        Image(systemName: "minus.magnifyingglass")
          .frame(width: 32, height: 32)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .keyboardShortcut("-", modifiers: .command)
      .help("Zoom out")
      Menu {
        Button("Fit to window") { previewZoom = 1 }
        Divider()
        ForEach([75, 90, 100, 110, 125, 140], id: \.self) { percent in
          Button("\(percent)%") { previewZoom = CGFloat(percent) / 100 }
        }
      } label: {
        Text(previewZoom == 1 ? "Fit · 100%" : "\(Int((previewZoom * 100).rounded()))%")
          .font(.system(size: 10.5, weight: .medium).monospacedDigit())
          .foregroundStyle(Color.primary)
          .frame(minWidth: 66, minHeight: 32)
          .contentShape(Rectangle())
      }
      .menuStyle(.borderlessButton)
      .accessibilityLabel("App preview zoom")
      Button {
        adjustZoom(by: 0.1)
      } label: {
        Image(systemName: "plus.magnifyingglass")
          .frame(width: 32, height: 32)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .keyboardShortcut("+", modifiers: .command)
      .help("Zoom in")
    }
    .fixedSize()
  }

  private var previewInteractionStatus: some View {
    SimulatorInteractionStatus(
      session: model.simulatorLiveSession, fallbackState: model.previewInteractionState,
      fallbackLatencyMS: model.previewLatencyMS)
  }

  private func adjustZoom(by amount: CGFloat) {
    previewZoom = min(max(previewZoom + amount, 0.65), 1.5)
  }

  private func appearanceButton(_ appearance: SimulatorAppearance, title: String) -> some View {
    Button {
      model.updateAppearance(appearance)
    } label: {
      Text(title).font(.system(size: 11, weight: .medium)).frame(width: 56, height: 30)
        .background(model.selectedAppearance == appearance ? Studio.accentSoft : .clear)
        .foregroundStyle(model.selectedAppearance == appearance ? Studio.accent : Color.primary)
        .clipShape(Capsule())
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(model.selectedDestination == nil)
  }
}

private struct SimulatorInteractionStatus: View {
  @ObservedObject var session: SimulatorLiveSession
  let fallbackState: PreviewInteractionState
  let fallbackLatencyMS: Int?

  var body: some View {
    HStack(spacing: 6) {
      if session.phase == .connecting
        || (!session.isStreaming
          && (fallbackState == .warming || fallbackState == .sending))
      {
        ProgressView().controlSize(.mini)
      } else {
        Circle()
          .fill(session.isStreaming ? Studio.success : fallbackColor)
          .frame(width: 7, height: 7)
      }
      Text(session.phase == .idle ? fallbackState.label : session.phase.label)
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(Studio.secondary)
      if session.isStreaming {
        Text("\(session.measuredFPS) fps")
          .font(.system(size: 9.5).monospacedDigit())
          .foregroundStyle(Studio.tertiary)
      } else if let fallbackLatencyMS {
        Text("\(fallbackLatencyMS) ms")
          .font(.system(size: 9.5).monospacedDigit())
          .foregroundStyle(Studio.tertiary)
      }
    }
    .fixedSize()
    .help("Continuous CoreSimulator framebuffer with direct HID input")
  }

  private var fallbackColor: Color {
    fallbackState == .ready ? Studio.success : Studio.secondary.opacity(0.6)
  }
}

private struct DevicePreview: View {
  @EnvironmentObject var model: AppModel
  let height: CGFloat
  var landscape = false

  private var scale: CGFloat { height / 650 }
  private var width: CGFloat { height * 0.505 }

  var body: some View {
    ZStack {
      deviceBody
        .frame(width: width, height: height)
        .rotationEffect(.degrees(landscape ? 90 : 0))
    }
    .frame(width: landscape ? height : width, height: landscape ? width : height)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      model.currentScreenshot == nil ? "No app screenshot" : "Latest app screenshot")
  }

  @ViewBuilder private var deviceBody: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 52 * scale, style: .continuous)
        .fill(Color(red: 0.08, green: 0.085, blue: 0.095))
        .shadow(color: .black.opacity(0.22), radius: 18, y: 9)
      RoundedRectangle(cornerRadius: 47 * scale, style: .continuous)
        .stroke(Color.white.opacity(0.32), lineWidth: max(1, 2 * scale)).padding(4 * scale)
      if let title = model.appOperation.title, let detail = model.appOperation.detail {
        deviceOperation(title: title, detail: detail)
      } else if let image = model.currentScreenshotImage {
        ZStack {
          Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: 43 * scale, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 43 * scale, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1))
          GeometryReader { screen in
            Color.clear
              .contentShape(Rectangle())
              .gesture(
                SpatialTapGesture().onEnded { value in
                  guard screen.size.width > 0, screen.size.height > 0 else { return }
                  model.tapPreview(
                    normalizedX: value.location.x / screen.size.width,
                    normalizedY: value.location.y / screen.size.height)
                })
              .highPriorityGesture(
                DragGesture(minimumDistance: 14).onEnded { value in
                  guard screen.size.width > 0, screen.size.height > 0 else { return }
                  let moved = abs(value.translation.width) + abs(value.translation.height)
                  guard moved >= 14 else { return }
                  model.swipePreview(
                    startX: value.startLocation.x / screen.size.width,
                    startY: value.startLocation.y / screen.size.height,
                    endX: value.location.x / screen.size.width,
                    endY: value.location.y / screen.size.height)
                })
          }
          .help(previewInteractionHelp)
          SimulatorLiveSurface(
            session: model.simulatorLiveSession,
            onTap: { point in
              model.tapPreview(normalizedX: Double(point.x), normalizedY: Double(point.y))
            },
            onSwipe: { start, end in
              model.swipePreview(
                startX: Double(start.x), startY: Double(start.y),
                endX: Double(end.x), endY: Double(end.y))
            }
          )
            .help(
              "Live CoreSimulator display. Click, drag, scroll, and type directly in the app."
            )
          if let tap = model.previewTapFeedback {
            GeometryReader { screen in
              ZStack {
                Circle()
                  .fill(Color.white.opacity(0.28))
                  .frame(width: max(18, 24 * scale), height: max(18, 24 * scale))
                Circle()
                  .stroke(Color.white, lineWidth: max(1.5, 2 * scale))
                  .frame(width: max(12, 16 * scale), height: max(12, 16 * scale))
              }
              .position(
                x: CGFloat(tap.x) * screen.size.width,
                y: CGFloat(tap.y) * screen.size.height)
            }
            .allowsHitTesting(false)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 43 * scale, style: .continuous))
        .padding(8 * scale)
      } else {
        VStack(spacing: 14) {
          Image(systemName: "iphone")
            .font(.system(size: 34, weight: .light))
          Text(model.repository == nil ? "Open a project" : "No launch evidence")
            .font(.system(size: 15, weight: .semibold))
          Text(deviceMessage)
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.58))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 190)
          if model.canRun {
            Button("Build & Run", action: model.run)
              .buttonStyle(.borderedProminent)
              .controlSize(.small)
          } else if model.needsExpoPreparation {
            Button("Prepare Expo for iOS", action: model.prepareExpoProject)
              .buttonStyle(.borderedProminent)
              .controlSize(.small)
          }
        }
        .foregroundStyle(.white)
      }
      Capsule().fill(Color.black).frame(width: 94 * scale, height: 26 * scale).frame(
        maxHeight: .infinity, alignment: .top
      )
      .padding(.top, 15 * scale)
    }
  }

  private func deviceOperation(title: String, detail: String) -> some View {
    VStack(spacing: 14) {
      ProgressView()
        .controlSize(.regular)
        .tint(.white)
        .environment(\.colorScheme, .dark)
      Text(title)
        .font(.system(size: 15, weight: .semibold))
      Text(detail)
        .font(.system(size: 11))
        .foregroundStyle(Color.white.opacity(0.62))
        .multilineTextAlignment(.center)
        .frame(maxWidth: 205)
      if model.appOperation == .building {
        Text(model.selectedScheme)
          .font(.system(size: 9.5, weight: .semibold).monospaced())
          .foregroundStyle(Color.white.opacity(0.56))
      }
    }
    .foregroundStyle(.white)
    .padding(22)
  }

  private var previewInteractionHelp: String {
    "Interact with the continuously streamed Simulator display. Manual gestures stay separate from deterministic agent verification evidence."
  }

  private var deviceMessage: String {
    if model.repository == nil { return "Choose a Git repository from the toolbar to begin." }
    if model.preflight?.isFullXcode != true {
      return "Select full Xcode to discover Simulator destinations."
    }
    if model.needsExpoPreparation {
      return "Generate the native iOS workspace once; Lys will detect it automatically."
    }
    if model.selectedDestination == nil { return "Choose a Simulator from the toolbar." }
    if model.selectedContainer == nil {
      return "No Xcode workspace or project was found in this folder."
    }
    if model.selectedScheme.isEmpty { return "Choose an app scheme from the App menu." }
    return "Run the selected scheme to capture current app evidence."
  }
}

private struct InteractionPalette: View {
  @EnvironmentObject var model: AppModel
  @State private var showInspector = false
  @State private var showScreenshot = false
  @State private var showAllHierarchyNodes = false

  var body: some View {
    VStack(spacing: 6) {
      paletteButton("cursorarrow", help: "Inspect accessibility hierarchy") {
        model.captureHierarchy()
        showInspector = true
      }
      .disabled(!automationAvailable)
      .popover(isPresented: $showInspector, arrowEdge: .trailing) { hierarchyInspector }

      paletteButton("hand.tap", help: "Tap the selected accessibility element") {
        model.tapSelectedElement()
      }
      .disabled(!hasDeterministicSelection)

      paletteButton("camera", help: "Capture current Simulator screenshot") {
        showScreenshot = true
        model.captureCurrentScreenshot()
      }
      .disabled(model.selectedTarget == nil)
      .popover(isPresented: $showScreenshot, arrowEdge: .trailing) {
        CapturedScreenshotView()
      }

      paletteButton("viewfinder", help: "Assert that the selected element is present") {
        model.assertSelectedElement()
      }
      .disabled(!hasDeterministicSelection)

      Menu {
        Button("Capture Screenshot", systemImage: "camera") {
          showScreenshot = true
          model.captureCurrentScreenshot()
        }
        .disabled(model.selectedTarget == nil)
        Button("Inspect hierarchy", systemImage: "list.bullet.rectangle") {
          model.captureHierarchy()
          showInspector = true
        }
        if model.wdaStatus.availability == .setupRequired {
          Divider()
          Button("Set up semantic automation", systemImage: "lock.open", action: model.setupWebDriverAgent)
            .disabled(model.isBusy)
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Studio.secondary)
          .frame(width: 32, height: 32)
      }
      .menuStyle(.borderlessButton)
      .help("More preview tools")
    }
    .padding(5)
    .background(Studio.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .shadow(color: .black.opacity(0.035), radius: 10, y: 4)
  }

  private var automationAvailable: Bool {
    model.isSemanticAutomationReady && model.selectedTarget != nil
      && model.selectedDestination != nil
  }

  private var hasDeterministicSelection: Bool {
    guard automationAvailable, let element = model.selectedElement else { return false }
    if !(element.identifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
      return true
    }
    guard let label = element.label, !label.isEmpty else { return false }
    return model.meaningfulHierarchyElements.filter {
      $0.label == label && $0.type == element.type
    }.count == 1
  }

  private func paletteButton(
    _ symbol: String, help: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 16, weight: .regular)).frame(
        width: 34, height: 42
      )
      .background(.clear)
      .foregroundStyle(Studio.accent)
      .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }

  private var hierarchyInspector: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Accessibility hierarchy").font(.system(size: 13, weight: .semibold))
          Text(
            "\(model.meaningfulHierarchyElements.count) useful · \(model.hierarchyElements.count) total"
          )
          .font(.system(size: 10)).foregroundStyle(Studio.secondary)
        }
        Spacer()
        Button("Refresh", action: model.captureHierarchy).buttonStyle(.borderless)
      }
      .padding(14)
      Divider()
      Picker("Hierarchy nodes", selection: $showAllHierarchyNodes) {
        Text("Useful").tag(false)
        Text("All nodes").tag(true)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(.horizontal, 12).padding(.vertical, 10)
      Divider()
      if model.hierarchyElements.isEmpty {
        ProgressView("Reading WebDriverAgent…").controlSize(.small)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if displayedHierarchyElements.isEmpty {
        ContentUnavailableView {
          Label("No useful accessibility elements", systemImage: "accessibility")
        } description: {
          Text(
            "Add accessibility labels or identifiers to interactive controls. Raw container nodes remain available under All nodes."
          )
        }
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(displayedHierarchyElements) { element in
              Button {
                model.selectedElement = element
                showInspector = false
              } label: {
                HStack(spacing: 10) {
                  Image(systemName: element.hittable ? "cursorarrow.click" : "circle.dashed")
                    .foregroundStyle(element.hittable ? Studio.accent : Studio.tertiary)
                    .frame(width: 18)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(elementTitle(element))
                      .font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(elementDetail(element))
                      .font(.system(size: 9).monospaced()).foregroundStyle(Studio.secondary)
                      .lineLimit(1)
                  }
                  Spacer()
                }
                .padding(.horizontal, 12).frame(height: 48)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              Divider()
            }
          }
        }
      }
    }
    .frame(width: 330, height: 420)
    .background(Studio.surface)
  }

  private var displayedHierarchyElements: [UIElement] {
    showAllHierarchyNodes ? model.hierarchyElements : model.meaningfulHierarchyElements
  }

  private func elementTitle(_ element: UIElement) -> String {
    for candidate in [element.label, element.identifier, element.value] {
      if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return candidate
      }
    }
    return element.type
  }

  private func elementDetail(_ element: UIElement) -> String {
    let identifier = element.identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
    return [element.type, identifier].compactMap { value in
      guard let value, !value.isEmpty else { return nil }
      return value
    }.joined(separator: " · ")
  }
}

private struct CapturedScreenshotView: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Latest screenshot")
            .font(.system(size: 13, weight: .semibold))
          Text("Stable Simulator capture")
            .font(.system(size: 10))
            .foregroundStyle(Studio.secondary)
        }
        Spacer()
        if let path = model.currentScreenshot?.lastPathComponent {
          Text(path)
            .font(.system(size: 9).monospaced())
            .foregroundStyle(Studio.tertiary)
            .lineLimit(1)
        }
      }
      if let image = model.currentScreenshotImage {
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
          .frame(width: 280, height: 460)
          .background(Studio.raised)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      } else {
        VStack(spacing: 10) {
          ProgressView()
          Text("Capturing the Simulator frame…")
            .font(.system(size: 11))
            .foregroundStyle(Studio.secondary)
        }
        .frame(width: 280, height: 460)
        .background(Studio.raised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
      ArtifactActionBar(
        paths: model.currentScreenshot.map { [$0.path] } ?? [],
        previewImage: model.currentScreenshotImage,
        compact: true)
    }
    .padding(16)
    .frame(width: 312)
    .background(Studio.surface)
  }
}

private struct VerificationPanel: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        VStack(spacing: 0) {
          HStack {
            Text("Progress")
              .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("Generation \(model.generation)")
              .font(.system(size: 10).monospacedDigit())
              .foregroundStyle(Studio.secondary)
          }
          .padding(.horizontal, 20)
          .frame(height: 54)
          Divider().overlay(Studio.separator)
          VStack(spacing: 0) {
            ForEach(progressRows, id: \.title) { row in
              VerificationRow(check: row)
              if row.title != progressRows.last?.title {
                Divider().overlay(Studio.separator)
              }
            }
          }
        }
        .background(Studio.surface)
        .clipShape(RoundedRectangle(cornerRadius: Studio.panelRadius, style: .continuous))
    .shadow(color: .black.opacity(0.022), radius: 12, y: 4)

        environmentCard
        recentRunsCard
      }
      .padding(.bottom, 2)
    }
    .scrollIndicators(.automatic)
  }

  private var environmentCard: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Environment")
          .font(.system(size: 12, weight: .semibold))
        Text(environmentDetail)
          .font(.system(size: 10.5))
          .foregroundStyle(Studio.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 6)
      Label("In-app", systemImage: "rectangle.inset.filled.and.person.filled")
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(Studio.success)
        .help("The selected Simulator stays embedded in Lys")
    }
    .padding(.horizontal, 18)
    .frame(height: 64)
    .background(Studio.surface)
    .clipShape(RoundedRectangle(cornerRadius: Studio.panelRadius, style: .continuous))
    .shadow(color: .black.opacity(0.018), radius: 11, y: 4)
  }

  private var recentRunsCard: some View {
    VStack(spacing: 0) {
        HStack {
          Text("Recent Runs")
            .font(.system(size: 12, weight: .semibold))
          Spacer()
          Button("View all") {
            model.evidenceWorkspaceTab = .logs
            model.isEvidenceWorkspaceOpen = true
          }
          .buttonStyle(.plain)
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(Studio.accent)
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        Divider().overlay(Studio.separator)
        if recentRuns.isEmpty {
          Text("No completed runs in this workspace.")
            .font(.system(size: 10.5))
            .foregroundStyle(Studio.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        } else {
          ForEach(recentRuns, id: \.id) { item in
            HStack(spacing: 9) {
              Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Studio.success)
              Text(item.title)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
              Spacer(minLength: 6)
              Text(item.time)
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(Studio.secondary)
            }
            .padding(.horizontal, 18)
            .frame(height: 32)
          }
        }
      }
      .background(Studio.surface)
      .clipShape(RoundedRectangle(cornerRadius: Studio.panelRadius, style: .continuous))
      .shadow(color: .black.opacity(0.022), radius: 12, y: 4)
  }

  private var progressRows: [VerificationCheck] {
    [
      check("Build", kind: .build, waiting: "Waiting for a fresh build"),
      check("Launch", kind: .launch, waiting: "Waiting for app launch"),
      testingCheck,
      validateCheck,
      .init(title: "Deploy", detail: "Waiting for validation", status: .waiting),
    ]
  }

  private var testingCheck: VerificationCheck {
    if let evidence = model.evidence.reversed().first(where: {
      $0.kind == .uiAssertion || $0.kind == .test
    }), evidence.taskGeneration == model.generation {
      return .init(
        title: "Testing", detail: evidence.diagnosticSummary,
        status: evidence.status == .passed ? .passed : evidence.status == .failed ? .failed : .blocked)
    }
    return .init(
      title: "Testing",
      detail: model.requiresUIVerification
        ? (model.isSemanticAutomationReady ? "Waiting for UI tests" : "UI automation setup required")
        : "Waiting for tests",
      status: model.requiresUIVerification && !model.isSemanticAutomationReady ? .blocked : .waiting)
  }

  private var validateCheck: VerificationCheck {
    switch model.verificationReport?.status {
    case .verified:
      return .init(title: "Validate", detail: "All evidence is current", status: .passed)
    case .failed:
      return .init(title: "Validate", detail: "Verification failed", status: .failed)
    case .blocked:
      return .init(title: "Validate", detail: "Waiting for compatibility setup", status: .blocked)
    case .partiallyVerified:
      return .init(title: "Validate", detail: "Waiting for tests", status: .waiting)
    case nil:
      return .init(title: "Validate", detail: "Waiting for tests", status: .waiting)
    }
  }

  private func check(_ title: String, kind: EvidenceKind, waiting: String) -> VerificationCheck {
    guard let evidence = model.evidence.reversed().first(where: { $0.kind == kind }) else {
      return .init(
        title: title, detail: waiting,
        status: kind == .uiAssertion && !model.requiresUIVerification
          ? .optional
          : (kind == .uiAssertion && !model.isSemanticAutomationReady ? .blocked : .waiting))
    }
    let current = evidence.taskGeneration == model.generation
    if !current {
      return .init(
        title: title, detail: "Stale · generation \(evidence.taskGeneration)", status: .waiting)
    }
    switch evidence.status {
    case .passed: return .init(title: title, detail: evidence.diagnosticSummary, status: .passed)
    case .failed: return .init(title: title, detail: evidence.diagnosticSummary, status: .failed)
    case .blocked: return .init(title: title, detail: evidence.diagnosticSummary, status: .blocked)
    case .informational:
      return .init(title: title, detail: evidence.diagnosticSummary, status: .waiting)
    }
  }

  private var environmentDetail: String {
    let device = model.selectedDestination?.name ?? "No Simulator selected"
    let runtime = model.selectedDestination.map { runtimeName($0.runtime) }
      ?? "Choose a destination"
    return "\(device) · \(runtime)"
  }

  private var recentRuns: [TimelineItem] {
    model.timeline.filter { $0.state == .complete }.suffix(3).reversed()
  }
}

private struct VerificationCheck {
  enum Status { case passed, failed, waiting, blocked, optional, active }
  var title: String
  var detail: String
  var status: Status
}

private struct VerificationRow: View {
  let check: VerificationCheck
  var body: some View {
    HStack(spacing: 17) {
      VerificationGlyph(status: check.status, size: 22)
      VStack(alignment: .leading, spacing: 4) {
        Text(check.title).font(.system(size: 13, weight: .semibold))
        Text(check.detail).font(.system(size: 11)).foregroundStyle(Studio.secondary).lineLimit(2)
      }
      Spacer()
      if !statusText.isEmpty {
        Text(statusText).font(.system(size: 10, weight: .medium)).foregroundStyle(statusColor)
      }
    }
    .padding(.horizontal, 20)
    .frame(height: 65)
  }
  private var statusText: String {
    switch check.status {
    case .passed: "Fresh"
    case .failed: "Failed"
    case .waiting: "Waiting"
    case .blocked: "Blocked"
    case .optional: ""
    case .active: "3 / 8"
    }
  }
  private var statusColor: Color {
    switch check.status {
    case .passed: Studio.success
    case .failed: .red
    case .waiting: Studio.secondary
    case .blocked: Studio.warning
    case .optional: Studio.secondary
    case .active: Studio.accent
    }
  }
}

private struct VerificationGlyph: View {
  let status: VerificationCheck.Status
  var size: CGFloat = 22
  var body: some View {
    ZStack {
      if status == .active {
        Circle().stroke(Studio.accent, lineWidth: 2).frame(width: size, height: size)
      } else {
        Circle().fill(fill).frame(width: size, height: size)
        Image(systemName: symbol).font(.system(size: size * 0.48, weight: .bold)).foregroundStyle(
          foreground)
      }
    }
    .accessibilityLabel(label)
  }
  private var fill: Color {
    switch status {
    case .passed: Studio.success
    case .failed: .red
    case .waiting: Studio.accentSoft
    case .blocked: Color.orange.opacity(0.17)
    case .optional: Studio.raised
    case .active: .clear
    }
  }
  private var foreground: Color {
    switch status {
    case .passed, .failed: .white
    case .waiting: Studio.accent
    case .blocked: Studio.warning
    case .optional: Studio.secondary
    case .active: Studio.accent
    }
  }
  private var symbol: String {
    switch status {
    case .passed: "checkmark"
    case .failed: "xmark"
    case .waiting: "clock"
    case .blocked: "lock"
    case .optional: "minus"
    case .active: "circle"
    }
  }
  private var label: String {
    switch status {
    case .passed: "Passed"
    case .failed: "Failed"
    case .waiting: "Waiting"
    case .blocked: "Blocked"
    case .optional: "Optional"
    case .active: "Running"
    }
  }
}

private struct EvidenceRow: View {
  let evidence: Evidence
  let onOpen: () -> Void

  var body: some View {
    Button(action: onOpen) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Studio.raised)
            .frame(width: 48, height: 42)
          Image(systemName: symbol).font(.system(size: 17, weight: .regular))
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.system(size: 12, weight: .semibold))
          Text(detail)
            .font(.system(size: 10).monospacedDigit()).foregroundStyle(Studio.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 6)
        VerificationGlyph(status: status, size: 18)
        Image(systemName: "chevron.right")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(Studio.tertiary)
      }
      .padding(.horizontal, 18)
      .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
    }
    .buttonStyle(.plain)
    .contentShape(Rectangle())
    .help("Open \(title.lowercased()) artifacts")
    .accessibilityLabel("Open \(title.lowercased()) artifacts")
  }

  private var detail: String {
    let timestamp = evidence.createdAt.formatted(date: .omitted, time: .shortened)
    let count = evidence.artifactPaths.count
    if count == 0 { return "\(timestamp) · details" }
    return "\(timestamp) · \(count) \(count == 1 ? "file" : "files") · inspect"
  }
  private var title: String {
    switch evidence.kind {
    case .build: "Build log"
    case .test: "Test result"
    case .launch: "Launch record"
    case .uiAction: "UI action"
    case .uiAssertion: "UI assertion"
    case .screenshot: "Screenshot"
    case .runtimeLog: "App log"
    case .diff: "Change set"
    }
  }
  private var symbol: String {
    switch evidence.kind {
    case .build: "terminal"
    case .test: "checklist"
    case .launch: "play.rectangle"
    case .uiAction, .uiAssertion: "viewfinder"
    case .screenshot: "iphone"
    case .runtimeLog: "list.bullet.rectangle"
    case .diff: "doc.text.magnifyingglass"
    }
  }
  private var status: VerificationCheck.Status {
    switch evidence.status {
    case .passed: .passed
    case .failed: .failed
    case .blocked: .blocked
    case .informational: .waiting
    }
  }
}

private struct EvidenceArtifactInspector: View {
  let evidence: Evidence

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 14, weight: .semibold))
          Text("Generation \(evidence.taskGeneration) · \(statusLabel)")
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(Studio.secondary)
        }
        Spacer(minLength: 8)
        Image(systemName: symbol)
          .foregroundStyle(Studio.accent)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if let previewImage {
            Image(nsImage: previewImage)
              .resizable()
              .scaledToFit()
              .frame(maxWidth: .infinity, maxHeight: 300)
              .background(Studio.raised)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          }

          if evidence.artifactPaths.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
              Label("No file attached", systemImage: "doc.questionmark")
                .font(.system(size: 11, weight: .semibold))
              Text("This record contains diagnostics only.")
                .font(.system(size: 10))
                .foregroundStyle(Studio.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Studio.raised)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          } else {
            VStack(alignment: .leading, spacing: 7) {
              Text("Attached files")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Studio.secondary)
              ForEach(evidence.artifactPaths, id: \.self) { path in
                VStack(alignment: .leading, spacing: 2) {
                  Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                  Text(path)
                    .font(.system(size: 9).monospaced())
                    .foregroundStyle(Studio.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                }
              }
            }
          }

          if !evidence.diagnosticSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 5) {
              Text("Record detail")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Studio.secondary)
              Text(evidence.diagnosticSummary)
                .font(.system(size: 10))
                .foregroundStyle(Studio.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
      .frame(minHeight: 80, maxHeight: 420)

      ArtifactActionBar(paths: evidence.artifactPaths, previewImage: previewImage)
    }
    .padding(16)
    .frame(width: 360)
    .background(Studio.surface)
  }

  private var previewImage: NSImage? {
    evidence.artifactPaths.compactMap { path -> NSImage? in
      let url = URL(fileURLWithPath: path)
      guard ["png", "jpg", "jpeg", "tif", "tiff"].contains(url.pathExtension.lowercased()) else {
        return nil
      }
      return NSImage(contentsOf: url)
    }.first
  }

  private var title: String {
    switch evidence.kind {
    case .build: "Build log"
    case .test: "Test result"
    case .launch: "Launch record"
    case .uiAction: "UI action"
    case .uiAssertion: "UI assertion"
    case .screenshot: "Screenshot"
    case .runtimeLog: "App log"
    case .diff: "Change set"
    }
  }

  private var symbol: String {
    switch evidence.kind {
    case .build: "terminal"
    case .test: "checklist"
    case .launch: "play.rectangle"
    case .uiAction, .uiAssertion: "viewfinder"
    case .screenshot: "iphone"
    case .runtimeLog: "list.bullet.rectangle"
    case .diff: "doc.text.magnifyingglass"
    }
  }

  private var statusLabel: String {
    switch evidence.status {
    case .passed: "passed"
    case .failed: "failed"
    case .blocked: "blocked"
    case .informational: "informational"
    }
  }
}

private struct ArtifactActionBar: View {
  let paths: [String]
  let previewImage: NSImage?
  var compact = false
  @State private var feedback: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        if previewImage != nil {
          actionButton("Copy Image", symbol: "doc.on.clipboard", enabled: true) {
            copyImage()
          }
        }
        actionButton("Copy Path", symbol: "link", enabled: !paths.isEmpty) {
          copyPaths()
        }
        actionButton("Reveal", symbol: "folder", enabled: hasExistingArtifact) {
          revealArtifacts()
        }
        if !compact {
          actionButton("Open", symbol: "arrow.up.right.square", enabled: hasExistingArtifact) {
            openArtifact()
          }
        }
      }
      if let feedback {
        Text(feedback)
          .font(.system(size: 9.5))
          .foregroundStyle(Studio.secondary)
          .lineLimit(1)
      }
    }
  }

  private var artifactURLs: [URL] { paths.map { URL(fileURLWithPath: $0) } }
  private var existingArtifactURLs: [URL] {
    artifactURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
  }
  private var hasExistingArtifact: Bool { !existingArtifactURLs.isEmpty }

  private func actionButton(
    _ title: String, symbol: String, enabled: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: symbol)
        .font(.system(size: compact ? 9.5 : 10))
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .disabled(!enabled)
  }

  private func copyImage() {
    guard let previewImage, let tiff = previewImage.tiffRepresentation else {
      feedback = "Image is not available"
      return
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setData(tiff, forType: .tiff)
    if let representation = NSBitmapImageRep(data: tiff),
      let png = representation.representation(using: .png, properties: [:])
    {
      NSPasteboard.general.setData(png, forType: NSPasteboard.PasteboardType("public.png"))
    }
    feedback = "Image copied"
  }

  private func copyPaths() {
    guard !paths.isEmpty else {
      feedback = "No artifact path available"
      return
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    feedback = paths.count == 1 ? "Path copied" : "Paths copied"
  }

  private func revealArtifacts() {
    guard !existingArtifactURLs.isEmpty else {
      feedback = "The artifact is no longer on disk"
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting(existingArtifactURLs)
    feedback = "Revealed in Finder"
  }

  private func openArtifact() {
    guard let url = existingArtifactURLs.first else {
      feedback = "The artifact is no longer on disk"
      return
    }
    NSWorkspace.shared.open(url)
    feedback = "Opened \(url.lastPathComponent)"
  }
}

private struct EvidenceWorkspace: View {
  @EnvironmentObject var model: AppModel
  @State private var selectedEvidence: Evidence?

  var body: some View {
    VStack(spacing: 0) {
      workspaceHeader
      if model.isEvidenceWorkspaceOpen {
        Divider().overlay(Studio.separator)
        tabContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(Studio.surface)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .shadow(color: .black.opacity(0.018), radius: 11, y: 4)
    .padding(.leading, 24)
    .padding(.trailing, 24)
    .padding(.top, 8)
    .padding(.bottom, 4)
  }

  private var workspaceHeader: some View {
    HStack(spacing: 0) {
      ForEach(EvidenceWorkspaceTab.allCases) { tab in
        tabButton(tab)
      }
      Spacer(minLength: 12)
      if model.evidenceWorkspaceTab == .terminal {
        HStack(spacing: 16) {
          Button("Copy Latest", action: copyLatest)
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .disabled(model.terminalEntries.isEmpty)
          Button("Clear", action: model.clearTerminal)
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .disabled(model.terminalEntries.isEmpty || model.terminalEntries.contains(where: { $0.state == .running }))
        }
      }
      HStack(spacing: 4) {
        Image(systemName: "command")
          .font(.system(size: 9, weight: .medium))
        Text("J")
          .font(.system(size: 9.5, weight: .medium).monospaced())
      }
      .foregroundStyle(Studio.tertiary)
      .padding(.leading, 14)
      .help("Toggle bottom workspace (Command–J)")
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Command J toggles the bottom workspace")

      Button(action: model.toggleEvidenceWorkspace) {
        Image(systemName: model.isEvidenceWorkspaceOpen ? "chevron.down" : "chevron.right")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(Studio.secondary)
          .frame(width: 32, height: 32)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        model.isEvidenceWorkspaceOpen ? "Collapse bottom workspace" : "Expand bottom workspace")
      .help(
        model.isEvidenceWorkspaceOpen
          ? "Collapse bottom workspace (Command–J)"
          : "Expand bottom workspace (Command–J)")
    }
    .padding(.horizontal, 16)
    .frame(height: 40)
  }

  @ViewBuilder private var tabContent: some View {
    switch model.evidenceWorkspaceTab {
    case .terminal:
      if model.terminalEntries.isEmpty {
        workspaceMessage(symbol: "terminal", title: "Terminal is ready", detail: "Build and agent commands will stream here.")
      } else {
        TerminalTranscriptView(entries: model.terminalEntries)
      }
    case .logs:
      if model.timeline.isEmpty {
        workspaceMessage(
          symbol: "list.bullet.rectangle", title: "No logs yet",
          detail: "Run an operation to record a timeline.")
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(model.timeline.suffix(8)) { item in
              HStack(alignment: .top, spacing: 12) {
                LogStateMark(state: item.state)
                Text(item.time)
                  .font(.system(size: 9.5).monospacedDigit())
                  .foregroundStyle(Studio.secondary)
                  .frame(width: 44, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                  Text(item.title).font(.system(size: 11, weight: .medium))
                  if !item.detail.isEmpty {
                    Text(item.detail)
                      .font(.system(size: 10))
                      .foregroundStyle(Studio.secondary)
                      .lineLimit(1)
                  }
                }
                Spacer(minLength: 0)
              }
              .padding(.horizontal, 18)
              .frame(minHeight: 36)
              if item.id != model.timeline.suffix(8).last?.id {
                Divider().overlay(Studio.separator)
              }
            }
          }
        }
      }
    case .evidence:
      evidenceContent
    }
  }

  private var evidenceContent: some View {
    HStack(spacing: 0) {
      ScrollView(.horizontal) {
        HStack(spacing: 12) {
          ForEach(Array(model.verificationEvidence.reversed().prefix(4))) { evidence in
            Button { selectedEvidence = evidence } label: {
              EvidenceThumbnail(evidence: evidence)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(item: $selectedEvidence, arrowEdge: .top) { selected in
              EvidenceArtifactInspector(evidence: selected)
            }
          }
          Button {
            model.captureCurrentScreenshot()
          } label: {
            VStack(spacing: 6) {
              Image(systemName: "plus")
                .font(.system(size: 17, weight: .light))
              Text("Add")
                .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(model.selectedTarget == nil ? Studio.tertiary : Studio.secondary)
            .frame(width: 92, height: 104)
            .overlay {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Studio.separator, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(model.selectedTarget == nil)
          .help("Capture a current Simulator screenshot")
        }
        .padding(.horizontal, 18)
      }
      .scrollIndicators(.hidden)
      Divider().padding(.vertical, 12)
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Logs").font(.system(size: 11, weight: .semibold))
          Spacer()
          Button("View full log") { model.evidenceWorkspaceTab = .logs }
            .buttonStyle(.plain)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(Studio.accent)
        }
        HStack(spacing: 6) {
          Circle().fill(model.terminalEntries.contains(where: { $0.state == .failed }) ? .red : Studio.success)
            .frame(width: 6, height: 6)
          Text(model.terminalEntries.contains(where: { $0.state == .failed }) ? "A command failed" : "All available logs captured")
            .font(.system(size: 10))
            .foregroundStyle(Studio.secondary)
        }
        Text(logSummary)
          .font(.system(size: 10).monospacedDigit())
          .foregroundStyle(Studio.secondary)
          .lineLimit(3)
      }
      .padding(.horizontal, 18)
      .frame(width: 250)
    }
  }

  private func tabButton(_ tab: EvidenceWorkspaceTab) -> some View {
    Button {
      model.evidenceWorkspaceTab = tab
      model.isEvidenceWorkspaceOpen = true
    } label: {
      HStack(spacing: 4) {
        Text(tab.rawValue)
        if let count = tabCount(tab) {
          Text("\(count)")
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .foregroundStyle(Studio.secondary)
            .padding(.horizontal, 3)
            .frame(height: 15)
            .background(Studio.raised)
            .clipShape(Capsule())
        }
      }
      .font(.system(size: 10.5, weight: model.evidenceWorkspaceTab == tab ? .semibold : .medium))
      .foregroundStyle(model.evidenceWorkspaceTab == tab ? Color.primary : Studio.secondary)
      .frame(width: tabWidth(tab), height: 40)
      .contentShape(Rectangle())
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(model.evidenceWorkspaceTab == tab ? Color.primary : .clear)
          .frame(
            width: model.evidenceWorkspaceTab == tab ? tabWidth(tab) - 10 : 0,
            height: 2)
        }
    }
    .buttonStyle(.plain)
    .contentShape(Rectangle())
    .accessibilityLabel("Show \(tab.rawValue)")
    .accessibilityValue(model.evidenceWorkspaceTab == tab ? "Selected" : "")
  }

  private func tabCount(_ tab: EvidenceWorkspaceTab) -> Int? {
    switch tab {
    case .terminal: nil
    case .logs: model.timeline.count > 0 ? model.timeline.count : nil
    case .evidence: model.verificationEvidence.count > 0 ? model.verificationEvidence.count : nil
    }
  }

  private func tabWidth(_ tab: EvidenceWorkspaceTab) -> CGFloat {
    switch tab {
    case .terminal: 56
    case .logs: 64
    case .evidence: 74
    }
  }

  private func workspaceMessage(symbol: String, title: String, detail: String) -> some View {
    VStack(spacing: 5) {
      Image(systemName: symbol)
        .font(.system(size: 18, weight: .light))
        .foregroundStyle(Studio.tertiary)
      Text(title).font(.system(size: 11, weight: .semibold))
      Text(detail).font(.system(size: 10)).foregroundStyle(Studio.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var logSummary: String {
    let count = model.timeline.count
    return "\(count) recorded event\(count == 1 ? "" : "s") · generation \(model.generation)"
  }

  private func copyLatest() {
    guard let entry = model.terminalEntries.last else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(
      "\(entry.workingDirectory) % \(entry.command)\n\(entry.output)", forType: .string)
  }

}

private struct EvidenceThumbnail: View {
  let evidence: Evidence

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Studio.raised)
        if let image = previewImage {
          Image(nsImage: image).resizable().scaledToFill()
        } else {
          Image(systemName: symbol)
            .font(.system(size: 19, weight: .light))
            .foregroundStyle(Studio.secondary)
        }
      }
      .frame(width: 92, height: 104)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      Text(title)
        .font(.system(size: 9.5, weight: .medium))
        .lineLimit(1)
        .frame(width: 92, alignment: .center)
    }
    .foregroundStyle(Color.primary)
  }

  private var previewImage: NSImage? {
    evidence.artifactPaths.compactMap { path in
      NSImage(contentsOf: URL(fileURLWithPath: path))
    }.first
  }

  private var title: String {
    switch evidence.kind {
    case .build: "Build"
    case .test: "Tests"
    case .launch: "Launch"
    case .uiAction: "UI action"
    case .uiAssertion: "Assertion"
    case .screenshot: "Screenshot"
    case .runtimeLog: "App log"
    case .diff: "Changes"
    }
  }

  private var symbol: String {
    switch evidence.kind {
    case .build: "terminal"
    case .test: "checklist"
    case .launch: "play.rectangle"
    case .uiAction, .uiAssertion: "viewfinder"
    case .screenshot: "iphone"
    case .runtimeLog: "list.bullet.rectangle"
    case .diff: "doc.text.magnifyingglass"
    }
  }
}

private struct LogStateMark: View {
  let state: TimelineItem.State

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 7, height: 7)
      .padding(.top, 4)
  }

  private var color: Color {
    switch state {
    case .complete: Studio.success
    case .active: Studio.accent
    case .waiting: Studio.tertiary
    case .warning: Studio.warning
    }
  }
}

private struct TaskActionBar: View {
  @EnvironmentObject var model: AppModel
  var body: some View {
    taskReviewBar
  }

  private var taskReviewBar: some View {
    HStack(spacing: 16) {
      Spacer().frame(width: 156)
      Button(action: showChanges) {
        HStack(spacing: 10) {
          Image(systemName: statusSymbol)
            .foregroundStyle(statusColor)
          Text(statusTitle)
          .font(.system(size: 12, weight: .semibold)).monospacedDigit()
          if canShowChanges {
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
              .foregroundStyle(Studio.secondary)
          }
        }
      }
      .buttonStyle(.plain)
      .disabled(!canShowChanges)
      Spacer()
      HStack(spacing: 10) {
        if model.activeWorktree != nil {
          Button("Discard Task", action: model.discardTask)
            .buttonStyle(.bordered)
            .controlSize(.regular)
          Button(action: reviewAction) {
            HStack(spacing: 16) {
              Text(model.proposedChanges.isEmpty ? "Review Changes" : "Apply Changes")
              Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(height: 38)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .foregroundStyle(.white)
          .background(Studio.accent)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
      }
      Spacer().frame(width: 4)
    }
    .padding(.horizontal, 20)
    .frame(maxHeight: .infinity)
    .background(Studio.surface)
  }
  private func reviewAction() {
    if model.proposedChanges.isEmpty {
      model.reviewChanges()
      model.section = .changes
    } else {
      model.applyAll()
    }
  }
  private func showChanges() {
    if model.activeWorktree != nil, model.proposedChanges.isEmpty { model.reviewChanges() }
    model.section = .changes
  }

  private var canShowChanges: Bool {
    model.activeWorktree != nil || !model.repositoryChanges.isEmpty
  }

  private var statusTitle: String {
    if model.activeWorktree != nil {
      return "\(model.proposedChanges.count) \(model.proposedChanges.count == 1 ? "file" : "files") changed"
    }
    if model.repository == nil { return "No project" }
    if !model.isGitRepository { return "Repository status unavailable" }
    if model.repositoryChanges.isEmpty { return "Working tree clean" }
    return "\(model.repositoryChanges.count) uncommitted \(model.repositoryChanges.count == 1 ? "file" : "files")"
  }

  private var statusSymbol: String {
    if model.activeWorktree != nil { return "shippingbox.fill" }
    if !model.repositoryChanges.isEmpty { return "exclamationmark.circle" }
    return model.repository == nil ? "folder" : "checkmark.circle"
  }

  private var statusColor: Color {
    if model.activeWorktree != nil { return Studio.accent }
    if !model.repositoryChanges.isEmpty { return Studio.warning }
    return model.repository == nil ? Studio.secondary : Studio.success
  }
}

private enum DeployListTab: String, CaseIterable, Identifiable {
  case releases = "Releases"
  case builds = "Builds"
  var id: String { rawValue }
}

private enum DeployDetailTab: String, CaseIterable, Identifiable {
  case overview = "Overview"
  case whatsNew = "What's New"
  case screenshots = "Screenshots"
  case testers = "Testers"
  case feedback = "Feedback"
  case buildDetails = "Build Details"
  var id: String { rawValue }
}

private struct DeployWorkspace: View {
  @EnvironmentObject var model: AppModel
  @State private var listTab: DeployListTab = .releases
  @State private var detailTab: DeployDetailTab = .overview
  @State private var showsAppStoreConnection = false
  @State private var testerEditorGroupID: String?
  @State private var screenshotRemoval: ScreenshotRemoval?
  @State private var feedbackScreenshot: AppStoreFeedback?
  @State private var showsBuildUpload = false
  @State private var showsReleaseUpdate = false
  @State private var showsTestFlightDistribution = false
  @State private var pendingDistributionAfterUpload = false
  @State private var collapsedTesterGroupIDs: Set<String> = []
  @State private var confirmsManualRelease = false

  var body: some View {
    GeometryReader { geometry in
      if geometry.size.width < 1180 {
        ScrollView {
          VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
              releaseColumn
                .frame(width: 224, height: 650)
              detailColumn
                .frame(maxWidth: .infinity, minHeight: 650, maxHeight: 650)
            }
            insightsColumn
              .frame(height: 440)
          }
          .padding(16)
          .frame(width: geometry.size.width, alignment: .top)
        }
        .scrollIndicators(.automatic)
      } else {
        HStack(alignment: .top, spacing: 14) {
          releaseColumn
            .frame(width: 272)
          detailColumn
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          insightsColumn
            .frame(width: 304)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 16)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Studio.backdrop)
    .sheet(isPresented: $showsAppStoreConnection) {
      AppStoreConnectionSheet()
        .environmentObject(model)
    }
    .sheet(
      isPresented: Binding(
        get: { testerEditorGroupID != nil },
        set: { if !$0 { testerEditorGroupID = nil } })
    ) {
      if let testerEditorGroupID {
        AppStoreTesterEditorSheet(groupID: testerEditorGroupID)
          .environmentObject(model)
      }
    }
    .sheet(item: $feedbackScreenshot) { feedback in
      FeedbackScreenshotViewer(feedback: feedback)
    }
    .sheet(isPresented: $showsBuildUpload) {
      AppStoreUploadSheet {
        pendingDistributionAfterUpload = true
      }
        .environmentObject(model)
    }
    .sheet(isPresented: $showsTestFlightDistribution) {
      AppStoreBuildDistributionSheet()
        .environmentObject(model)
    }
    .sheet(isPresented: $showsReleaseUpdate) {
      AppStoreReleaseSheet()
        .environmentObject(model)
    }
    .alert(
      "App does not match this repository",
      isPresented: Binding(
        get: { model.appStoreSelectionWarning != nil },
        set: { if !$0 { model.appStoreSelectionWarning = nil } })
    ) {
      Button("OK") { model.appStoreSelectionWarning = nil }
    } message: {
      Text(model.appStoreSelectionWarning ?? "The project-matched app remains selected.")
    }
    .alert(item: $screenshotRemoval) { removal in
      Alert(
        title: Text("Remove screenshot?"),
        message: Text("\(removal.fileName) will be deleted from App Store Connect. This cannot be undone."),
        primaryButton: .destructive(Text("Remove")) {
          Task { await model.removeAppStoreScreenshot(removal.id) }
        },
        secondaryButton: .cancel())
    }
    .alert("Release this version now?", isPresented: $confirmsManualRelease) {
      Button("Cancel", role: .cancel) {}
      Button("Release to Customers") {
        Task { await model.releaseApprovedAppStoreVersion() }
      }
    } message: {
      Text(
        "Version \(model.selectedAppStoreVersion?.versionString ?? "") is approved and will become available to customers."
      )
    }
    .task(id: deploymentContextKey) {
      guard model.appStoreConnectionPhase == .connected else { return }
      await model.refreshAppStoreDeploymentData()
    }
    .onChange(of: showsBuildUpload) { _, isPresented in
      guard !isPresented, pendingDistributionAfterUpload else { return }
      pendingDistributionAfterUpload = false
      model.appStoreReleasePhase = .idle
      model.appStoreReleaseError = nil
      showsTestFlightDistribution = true
    }
  }

  private var deploymentContextKey: String {
    [
      model.appStoreConnection?.id.uuidString ?? "disconnected",
      model.selectedContainer?.path ?? "no-container", model.selectedScheme,
    ].joined(separator: "|")
  }

  private var releaseColumn: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Deploy")
        .font(.system(size: 19, weight: .bold))
      Text("Distribute your app with TestFlight.")
        .font(.system(size: 11))
        .foregroundStyle(Studio.secondary)
        .padding(.top, 7)

      if model.appStoreConnectionPhase != .connected {
        Button {
          showsAppStoreConnection = true
        } label: {
        HStack(spacing: 8) {
          connectionIndicator
          VStack(alignment: .leading, spacing: 2) {
            Text(model.appStoreConnection?.label ?? "App Store Connect")
              .font(.system(size: 10.5, weight: .semibold))
              .foregroundStyle(Color.primary)
            Text(connectionSubtitle)
              .font(.system(size: 9.5))
              .foregroundStyle(Studio.secondary)
              .lineLimit(1)
          }
          Spacer(minLength: 6)
          Image(systemName: model.appStoreConnection == nil ? "plus" : "ellipsis")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Studio.accent)
        }
        .padding(.horizontal, 11)
        .frame(height: 44)
        .background(Studio.raised)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
      }
        .buttonStyle(.plain)
        .accessibilityLabel("Connect App Store Connect")
        .padding(.top, 16)
      }

      if model.appStoreConnectionPhase == .connected {
        AppStoreAppPicker()
          .environmentObject(model)
          .padding(.top, 16)
          .disabled(model.appStoreUploadPhase.isRunning)
      }

      HStack(spacing: 2) {
        ForEach(DeployListTab.allCases) { tab in
          Button {
            listTab = tab
          } label: {
            Text(tab.rawValue)
              .font(.system(size: 10.5, weight: listTab == tab ? .semibold : .medium))
              .foregroundStyle(listTab == tab ? Color.primary : Studio.secondary)
              .frame(maxWidth: .infinity, minHeight: 34)
              .background(listTab == tab ? Studio.surface : .clear)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
          .accessibilityLabel("Show deploy \(tab.rawValue.lowercased())")
        }
      }
      .padding(2)
      .background(Studio.raised)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .padding(.top, model.selectedAppStoreApp == nil ? 22 : 12)

      DeploySurface { deployListContent }
      .frame(maxHeight: .infinity)
      .padding(.top, 14)
    }
  }

  @ViewBuilder private var deployListContent: some View {
    switch model.appStoreConnectionPhase {
    case .disconnected:
      DeployEmptyState(
        symbol: "lock.shield", title: "Connect to Apple",
        detail: "Import a team API key to load real apps and TestFlight data.",
        actionTitle: "Connect", action: { showsAppStoreConnection = true })
    case .connecting, .refreshing:
      VStack(spacing: 10) {
        ProgressView().controlSize(.small)
        Text(model.appStoreConnectionPhase == .connecting ? "Connecting…" : "Syncing apps…")
          .font(.system(size: 11, weight: .semibold))
        Text("Lys is authenticating directly with App Store Connect.")
          .font(.system(size: 10))
          .foregroundStyle(Studio.secondary)
          .multilineTextAlignment(.center)
      }
      .padding(22)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed:
      DeployEmptyState(
        symbol: "exclamationmark.triangle", title: "Connection needs attention",
        detail: model.appStoreConnectionError ?? "App Store Connect could not be reached.",
        actionTitle: model.appStoreConnection == nil ? "Reconnect" : "Manage",
        action: { showsAppStoreConnection = true })
    case .connected:
      if (model.appStoreDeploymentPhase == .discoveringTarget
        || model.appStoreDeploymentPhase == .loading) && model.selectedAppStoreApp == nil
      {
        VStack(spacing: 10) {
          ProgressView().controlSize(.small)
          Text(model.appStoreDeploymentPhase == .discoveringTarget
            ? "Matching Release target…" : "Loading Apple data…")
            .font(.system(size: 11, weight: .semibold))
          Text("Reading the Release bundle ID and matching it to an accessible app.")
            .font(.system(size: 10))
            .foregroundStyle(Studio.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.selectedAppStoreApp == nil {
        appStoreAppSelection
      } else if listTab == .builds {
        appStoreBuildList
      } else {
        appStoreReleaseList
      }
    }
  }

  private var appStoreAppSelection: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 5) {
        Text("Choose an app")
          .font(.system(size: 11.5, weight: .semibold))
        Text(model.appStoreDeploymentError ?? "Select the App Store record for this project.")
          .font(.system(size: 9.5))
          .foregroundStyle(Studio.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(14)
      Divider().overlay(Studio.separator)
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(model.appStoreApps) { app in
            Button { model.selectAppStoreApp(app.id) } label: {
              HStack(spacing: 9) {
                Image(systemName: "app")
                  .font(.system(size: 12))
                  .foregroundStyle(Studio.accent)
                  .frame(width: 26, height: 26)
                  .background(Studio.accentSoft)
                  .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                  Text(app.name).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                  Text(app.bundleID)
                    .font(.system(size: 8.5).monospaced())
                    .foregroundStyle(Studio.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                  .font(.system(size: 8, weight: .semibold))
                  .foregroundStyle(Studio.tertiary)
              }
              .padding(.horizontal, 12)
              .frame(minHeight: 46)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if app.id != model.appStoreApps.last?.id { Divider().overlay(Studio.separator) }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder private var appStoreReleaseList: some View {
    if let error = model.appStoreSectionErrors[.versions] {
      DeployEmptyState(
        symbol: "exclamationmark.triangle", title: "Releases unavailable", detail: error,
        actionTitle: "Retry", action: {
          Task { await model.refreshAppStoreDeploymentData(discoverTarget: false) }
        })
    } else if model.appStoreVersions.isEmpty && model.appStoreDeploymentPhase == .loading {
      ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if model.appStoreVersions.isEmpty {
      DeployEmptyState(
        symbol: "shippingbox", title: "No App Store versions",
        detail: "Apple returned no iOS App Store versions for this app.")
    } else {
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(model.appStoreVersions) { version in
            Button { model.selectAppStoreVersion(version.id) } label: {
              deployListRow(
                title: "Version \(version.versionString)",
                detail: friendlyAppStoreState(version.state),
                selected: model.appStoreSelectedVersionID == version.id,
                symbol: version.state == "READY_FOR_DISTRIBUTION" ? "checkmark.seal.fill" : "shippingbox")
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  @ViewBuilder private var appStoreBuildList: some View {
    if let error = model.appStoreSectionErrors[.builds] {
      DeployEmptyState(
        symbol: "exclamationmark.triangle", title: "Builds unavailable", detail: error,
        actionTitle: "Retry", action: {
          Task { await model.refreshAppStoreDeploymentData(discoverTarget: false) }
        })
    } else if model.appStoreBuilds.isEmpty && model.appStoreDeploymentPhase == .loading {
      ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if model.appStoreBuilds.isEmpty {
      DeployEmptyState(
        symbol: "hammer", title: "No uploaded builds",
        detail: "Apple returned no TestFlight builds for this app.")
    } else {
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(model.appStoreBuilds) { build in
            Button { model.selectAppStoreBuild(build.id) } label: {
              deployListRow(
                title: build.marketingVersion.map { "\($0) (\(build.version))" }
                  ?? "Build \(build.version)",
                detail: friendlyBuildState(build.processingState),
                selected: model.appStoreSelectedBuildID == build.id,
                symbol: build.processingState == "VALID" ? "checkmark.circle.fill" : "hammer")
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private func deployListRow(
    title: String, detail: String, selected: Bool, symbol: String
  ) -> some View {
    HStack(spacing: 9) {
      Image(systemName: symbol)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(selected ? Studio.accent : Studio.secondary)
        .frame(width: 24, height: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
        Text(detail).font(.system(size: 9)).foregroundStyle(Studio.secondary).lineLimit(1)
      }
      Spacer(minLength: 4)
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 48)
    .background(selected ? Studio.accentSoft.opacity(0.75) : Color.clear)
    .contentShape(Rectangle())
  }

  @ViewBuilder private var connectionIndicator: some View {
    switch model.appStoreConnectionPhase {
    case .connecting, .refreshing:
      ProgressView().controlSize(.mini).frame(width: 12, height: 12)
    case .connected:
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 12))
        .foregroundStyle(Studio.success)
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 11))
        .foregroundStyle(Studio.warning)
    case .disconnected:
      Image(systemName: "link")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Studio.accent)
    }
  }

  private var connectionSubtitle: String {
    switch model.appStoreConnectionPhase {
    case .disconnected: "Not connected"
    case .connecting: "Testing credentials"
    case .refreshing: "Refreshing live data"
    case .connected:
      "Connected · \(model.appStoreApps.count) app\(model.appStoreApps.count == 1 ? "" : "s")"
    case .failed: "Connection failed"
    }
  }

  private var detailColumn: some View {
    DeploySurface {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 5) {
            Text(deployDetailTitle)
              .font(.system(size: 20, weight: .bold))
              .lineLimit(1)
              .truncationMode(.tail)
            Text(deployDetailSubtitle)
              .font(.system(size: 10.5))
              .foregroundStyle(Studio.secondary)
          }
          Spacer(minLength: 8)
          if model.selectedAppStoreApp != nil {
            if listTab == .builds, model.selectedAppStoreBuild?.processingState == "VALID" {
              Button {
                model.appStoreReleasePhase = .idle
                model.appStoreReleaseError = nil
                showsTestFlightDistribution = true
              } label: {
                Label("Send to Testers", systemImage: "person.2.badge.plus")
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.small)
              .disabled(model.appStoreReleasePhase.isRunning)
            }
            if model.selectedAppStoreVersion?.state == "PENDING_DEVELOPER_RELEASE" {
              Button {
                confirmsManualRelease = true
              } label: {
                Label("Release Now", systemImage: "shippingbox.fill")
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.small)
              .disabled(model.isAppStoreMutationInProgress)
            }
            Button {
              model.appStoreReleasePhase = .idle
              model.appStoreReleaseError = nil
              showsReleaseUpdate = true
            } label: {
              Label("Release Update", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(
              model.appStoreDeploymentPhase == .loading || model.appStoreUploadPhase.isRunning
                || model.appStoreReleasePhase.isRunning)
            Button {
              showsBuildUpload = true
              if !model.appStoreUploadPhase.isRunning {
                Task { await model.prepareAppStoreUpload() }
              }
            } label: {
              if model.appStoreUploadPhase.isRunning {
                HStack(spacing: 6) {
                  ProgressView().controlSize(.mini)
                  Text(uploadButtonTitle)
                }
              } else {
                Label("Upload Build", systemImage: "arrow.up.circle.fill")
              }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.appStoreDeploymentPhase == .loading)
            Button {
              Task { await model.refreshAppStoreDeploymentData(discoverTarget: false) }
            } label: {
              if model.appStoreDeploymentPhase == .loading {
                ProgressView().controlSize(.mini)
              } else {
                Label("Sync", systemImage: "arrow.clockwise")
              }
            }
            .controlSize(.small)
            .disabled(
              model.appStoreDeploymentPhase == .loading || model.appStoreUploadPhase.isRunning)
          }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)

        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(DeployDetailTab.allCases) { tab in
              Button {
                detailTab = tab
              } label: {
                Text(tab.rawValue)
                  .font(.system(size: 10.5, weight: detailTab == tab ? .semibold : .medium))
                  .foregroundStyle(detailTab == tab ? Color.primary : Studio.secondary)
                  .padding(.horizontal, 10)
                  .frame(height: 42)
                  .overlay(alignment: .bottom) {
                    Rectangle()
                      .fill(detailTab == tab ? Color.primary : .clear)
                      .frame(height: 1)
                  }
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .contentShape(Rectangle())
              .accessibilityLabel("Show deploy \(tab.rawValue.lowercased())")
            }
          }
          .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 13)

        Divider().overlay(Studio.separator)
        detailContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private var uploadButtonTitle: String {
    switch model.appStoreUploadPhase {
    case .preflighting: "Checking…"
    case .archiving: "Archiving…"
    case .inspecting: "Verifying…"
    case .uploading: "Uploading…"
    case .processing: "Processing…"
    default: "Upload Build"
    }
  }

  private var deployDetailTitle: String {
    if let version = model.selectedAppStoreVersion {
      return "\(model.selectedAppStoreApp?.name ?? "App") \(version.versionString)"
    }
    if let app = model.selectedAppStoreApp { return app.name }
    if model.appStoreConnectionPhase == .disconnected { return "Connect App Store Connect" }
    if model.appStoreConnectionPhase == .failed { return "Connection needs attention" }
    return "No release selected"
  }

  private var deployDetailSubtitle: String {
    if let version = model.selectedAppStoreVersion {
      return "iOS · \(friendlyAppStoreState(version.state))"
    }
    if let app = model.selectedAppStoreApp {
      return "\(app.bundleID) · No App Store version selected"
    }
    if model.appStoreConnectionPhase == .disconnected {
      return "Connect a Team API key to load apps, releases, builds, testers, and feedback."
    }
    if model.appStoreConnectionPhase == .failed {
      return model.appStoreConnectionError ?? "App Store Connect could not be reached."
    }
    return model.appStoreDeploymentError ?? "Choose an accessible app to load deployment data."
  }

  @ViewBuilder private var detailContent: some View {
    switch detailTab {
    case .overview:
      if model.appStoreConnectionPhase == .disconnected {
        DeployEmptyState(
          symbol: "lock.shield", title: "Connect to Apple",
          detail: "Import a Team API key to request live deployment data.",
          actionTitle: "Connect", action: { showsAppStoreConnection = true })
      } else if model.selectedAppStoreApp == nil {
        DeployEmptyState(
          symbol: "app.badge", title: "Choose an app",
          detail: "Select the App Store app for this project to load live deployment data.")
      } else {
        ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .top, spacing: 14) {
            deploySection(title: "App Preview") {
              appPreview
            }
            deploySection(title: "Release Information") {
              releaseInformation
            }
            .frame(width: 250)
          }
          .padding(18)

          Divider().overlay(Studio.separator)
          deployTextSection(
            title: "Processing",
            detail: selectedBuildSummary)
          Divider().overlay(Studio.separator)
          deployTextSection(
            title: "What's New",
            detail: primaryWhatsNew ?? "Apple returned no release notes for this version.")
          Divider().overlay(Studio.separator)
          screenshotSection
        }
      }
      }
    case .whatsNew:
      appStoreWhatsNewContent
    case .screenshots:
      appStoreScreenshotsContent
    case .testers:
      appStoreTestersContent
    case .feedback:
      appStoreFeedbackContent
    case .buildDetails:
      appStoreBuildDetailsContent
    }
  }

  @ViewBuilder private var appStoreWhatsNewContent: some View {
    if model.selectedAppStoreVersion == nil {
      DeployEmptyState(
        symbol: "text.alignleft", title: "Choose a release",
        detail: "Select an App Store version to load its localized release notes.")
    } else if model.appStoreLocalizations.isEmpty {
      DeployEmptyState(
        symbol: "text.alignleft", title: "No release notes",
        detail: model.appStoreSectionErrors[.screenshots]
          ?? "Apple returned no localized What's New text for this version.")
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(model.appStoreLocalizations) { localization in
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text(localization.locale)
                  .font(.system(size: 11, weight: .semibold).monospaced())
                Spacer()
                if localization.locale == model.selectedAppStoreApp?.primaryLocale {
                  Text("Primary")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Studio.accent)
                }
              }
              Text(localization.whatsNew?.nonempty ?? "No What's New text")
                .font(.system(size: 10.5))
                .foregroundStyle(localization.whatsNew?.nonempty == nil ? Studio.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            Divider().overlay(Studio.separator)
          }
        }
      }
    }
  }

  @ViewBuilder private var appStoreScreenshotsContent: some View {
    if model.selectedAppStoreVersion == nil {
      DeployEmptyState(
        symbol: "photo.on.rectangle", title: "Choose a release",
        detail: "Select an App Store version to load its remote screenshot sets.")
    } else if let error = model.appStoreSectionErrors[.screenshots],
      model.appStoreScreenshotSets.isEmpty
    {
      DeployEmptyState(
        symbol: "exclamationmark.triangle", title: "Screenshots unavailable", detail: error,
        actionTitle: "Retry", action: { Task { await model.loadSelectedAppStoreVersionDetails() } })
    } else if model.appStoreScreenshotSets.isEmpty {
      DeployEmptyState(
        symbol: "photo.on.rectangle", title: "No remote screenshots",
        detail: "Apple returned no screenshot sets for this App Store version.")
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 22) {
          if let error = model.appStoreMutationError {
            Label(error, systemImage: "exclamationmark.triangle")
              .font(.system(size: 9.5))
              .foregroundStyle(Studio.warning)
          }
          ForEach(model.appStoreScreenshotSets) { set in
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Text(set.locale).font(.system(size: 11, weight: .semibold).monospaced())
                Text(friendlyScreenshotType(set.displayType))
                  .font(.system(size: 9.5))
                  .foregroundStyle(Studio.secondary)
                Spacer()
                Text("\(set.screenshots.count)")
                  .font(.system(size: 9.5).monospacedDigit())
                  .foregroundStyle(Studio.secondary)
                Button {
                  chooseScreenshot { url in
                    Task { await model.addAppStoreScreenshot(fileURL: url, toSet: set.id) }
                  }
                } label: {
                  Label("Add", systemImage: "plus")
                }
                .controlSize(.small)
                .disabled(model.isAppStoreMutationInProgress)
              }
              LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 12)],
                spacing: 12
              ) {
                ForEach(set.screenshots) { screenshot in
                  VStack(alignment: .leading, spacing: 6) {
                    AsyncImage(url: screenshot.downloadURL) { phase in
                      switch phase {
                      case .success(let image):
                        image.resizable().scaledToFit()
                      case .failure:
                        Image(systemName: "photo.badge.exclamationmark")
                          .font(.system(size: 22, weight: .light))
                          .foregroundStyle(Studio.tertiary)
                      default:
                        ProgressView().controlSize(.small)
                      }
                    }
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260)
                    .background(Studio.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(screenshot.fileName)
                      .font(.system(size: 9))
                      .foregroundStyle(Studio.secondary)
                      .lineLimit(1)
                      .truncationMode(.middle)
                    HStack(spacing: 8) {
                      Button {
                        chooseScreenshot { url in
                          Task {
                            await model.replaceAppStoreScreenshot(
                              screenshot.id, with: url, inSet: set.id)
                          }
                        }
                      } label: {
                        Image(systemName: "pencil")
                          .frame(width: 24, height: 20)
                      }
                      .controlSize(.mini)
                      .help("Replace screenshot")
                      .accessibilityLabel("Replace \(screenshot.fileName)")
                      Button(role: .destructive) {
                        screenshotRemoval = .init(id: screenshot.id, fileName: screenshot.fileName)
                      } label: {
                        Image(systemName: "trash")
                          .frame(width: 24, height: 20)
                      }
                      .controlSize(.mini)
                      .help("Remove from App Store Connect")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(model.isAppStoreMutationInProgress)
                  }
                }
              }
            }
          }
        }
        .padding(20)
      }
    }
  }

  @ViewBuilder private var appStoreTestersContent: some View {
    if let error = model.appStoreSectionErrors[.testers] {
      DeployEmptyState(
        symbol: "exclamationmark.triangle", title: "Tester access unavailable", detail: error,
        actionTitle: "Retry", action: {
          Task { await model.refreshAppStoreDeploymentData(discoverTarget: false) }
        })
    } else if model.appStoreBetaGroups.isEmpty {
      DeployEmptyState(
        symbol: "person.2", title: "No tester groups",
        detail: "Apple returned no internal or external TestFlight groups for this app.")
    } else {
      VStack(spacing: 0) {
        testerAnalyticsToolbar
        Divider().overlay(Studio.separator)
        if let analyticsError = model.appStoreSectionErrors[.testerAnalytics] {
          HStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
              .foregroundStyle(Studio.warning)
            Text("Tester analytics unavailable")
              .font(.system(size: 9.5, weight: .semibold))
            Text(analyticsError)
              .font(.system(size: 9))
              .foregroundStyle(Studio.secondary)
              .lineLimit(1)
              .help(analyticsError)
            Spacer(minLength: 8)
            Button("Retry") {
              Task { await model.refreshAppStoreTesterAnalytics() }
            }
            .controlSize(.mini)
          }
          .padding(.horizontal, 20)
          .frame(minHeight: 36)
          .background(Studio.warning.opacity(0.06))
          Divider().overlay(Studio.separator)
        }
        GeometryReader { geometry in
          let metricWidth: CGFloat = geometry.size.width < 620 ? 52 : 68
          let showsDevice = geometry.size.width >= 760
          ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
              testerAnalyticsColumnHeader(
                metricWidth: metricWidth, showsDevice: showsDevice)
              ForEach(model.appStoreBetaGroups) { group in
                let isCollapsed = collapsedTesterGroupIDs.contains(group.id)
                VStack(spacing: 0) {
                  testerGroupHeader(group, isCollapsed: isCollapsed)
                  if !isCollapsed {
                    if group.testers.isEmpty {
                      Text("No individual testers in this group")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Studio.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 58)
                        .padding(.bottom, 14)
                    } else {
                      ForEach(group.testers) { tester in
                        testerAnalyticsRow(
                          tester, metricWidth: metricWidth, showsDevice: showsDevice)
                        if tester.id != group.testers.last?.id {
                          Divider().overlay(Studio.separator).padding(.leading, 58)
                        }
                      }
                    }
                  }
                }
                Divider().overlay(Studio.separator)
              }
            }
            .frame(maxWidth: .infinity)
          }
        }
      }
    }
  }

  private var testerAnalyticsToolbar: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Tester activity")
          .font(.system(size: 10.5, weight: .semibold))
        Text("Sessions, crashes, and feedback reported by TestFlight")
          .font(.system(size: 8.5))
          .foregroundStyle(Studio.secondary)
      }
      Spacer(minLength: 12)
      if model.isAppStoreTesterAnalyticsLoading {
        ProgressView().controlSize(.mini)
          .help("Loading tester analytics")
      }
      Picker("Activity period", selection: $model.appStoreTesterUsagePeriod) {
        Text("7d").tag(AppStoreTesterUsagePeriod.sevenDays)
        Text("30d").tag(AppStoreTesterUsagePeriod.thirtyDays)
        Text("90d").tag(AppStoreTesterUsagePeriod.ninetyDays)
        Text("1y").tag(AppStoreTesterUsagePeriod.oneYear)
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(width: 184)
      .disabled(model.isAppStoreTesterAnalyticsLoading)
      .onChange(of: model.appStoreTesterUsagePeriod) { _, _ in
        Task { await model.refreshAppStoreTesterAnalytics() }
      }
    }
    .padding(.horizontal, 20)
    .frame(minHeight: 54)
  }

  private func testerAnalyticsColumnHeader(
    metricWidth: CGFloat, showsDevice: Bool
  ) -> some View {
    HStack(spacing: 12) {
      Text("TESTER")
        .frame(maxWidth: .infinity, alignment: .leading)
      Text("SESSIONS").frame(width: metricWidth, alignment: .trailing)
      Text("CRASHES").frame(width: metricWidth, alignment: .trailing)
      Text("FEEDBACK").frame(width: metricWidth, alignment: .trailing)
      if showsDevice {
        Text("DEVICE").frame(width: 140, alignment: .leading)
      }
    }
    .font(.system(size: 7.5, weight: .semibold))
    .foregroundStyle(Studio.secondary)
    .padding(.horizontal, 20)
    .frame(height: 30)
    .background(Studio.raised.opacity(0.35))
  }

  private func testerGroupHeader(
    _ group: AppStoreBetaGroup, isCollapsed: Bool
  ) -> some View {
    HStack(spacing: 10) {
      Button {
        withAnimation(.easeOut(duration: 0.16)) {
          if isCollapsed {
            collapsedTesterGroupIDs.remove(group.id)
          } else {
            collapsedTesterGroupIDs.insert(group.id)
          }
        }
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Studio.secondary)
            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            .frame(width: 10)
          Image(systemName: group.isInternal ? "person.2.fill" : "globe")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(group.isInternal ? Studio.accent : Studio.secondary)
            .frame(width: 28, height: 28)
            .background(group.isInternal ? Studio.accentSoft : Studio.raised)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
          VStack(alignment: .leading, spacing: 3) {
          Text(group.name)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
          HStack(spacing: 5) {
            Text(group.isInternal ? "Internal" : "External")
            if let count = group.testerCount {
              Text("· \(count) tester\(count == 1 ? "" : "s")")
            }
          }
          .font(.system(size: 9.5))
          .foregroundStyle(Studio.secondary)
        }
          Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)
      .accessibilityLabel("\(isCollapsed ? "Expand" : "Collapse") \(group.name)")
      Spacer(minLength: 8)
      Button("Manage…") { testerEditorGroupID = group.id }
        .buttonStyle(.plain)
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(Studio.accent)
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(Studio.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
        .contentShape(Rectangle())
        .help("Add or remove testers in \(group.name)")
        .accessibilityLabel("Manage \(group.name) testers")
    }
    .padding(.horizontal, 20)
    .frame(minHeight: 56)
    .background(Studio.raised.opacity(0.55))
  }

  private func testerAnalyticsRow(
    _ tester: AppStoreBetaTester, metricWidth: CGFloat, showsDevice: Bool
  ) -> some View {
    let usage = model.appStoreTesterUsages[tester.id]
    return HStack(spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: "person.crop.circle")
          .font(.system(size: 14))
          .foregroundStyle(Studio.secondary)
          .frame(width: 26)
        VStack(alignment: .leading, spacing: 2) {
          Text(tester.email)
            .font(.system(size: 10.5, weight: .medium))
            .lineLimit(1)
            .textSelection(.enabled)
          HStack(spacing: 5) {
            if let name = tester.name { Text(name) }
            Text(friendlyValue(tester.state))
          }
          .font(.system(size: 8.5))
          .foregroundStyle(Studio.secondary)
          .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      testerMetricCell(usage?.sessionCount, width: metricWidth)
      testerMetricCell(usage?.crashCount, width: metricWidth, warnsWhenPositive: true)
      testerMetricCell(usage?.feedbackCount, width: metricWidth)
      if showsDevice {
        testerDeviceCell(tester.devices)
          .frame(width: 140, alignment: .leading)
      }
    }
    .padding(.horizontal, 20)
    .frame(minHeight: 54)
  }

  private func testerMetricCell(
    _ value: Int?, width: CGFloat, warnsWhenPositive: Bool = false
  ) -> some View {
    let foreground: Color =
      if warnsWhenPositive && (value ?? 0) > 0 {
        Studio.warning
      } else if value == nil {
        Studio.tertiary
      } else {
        .primary
      }
    return Text(value.map(String.init) ?? "—")
      .font(.system(size: 10, weight: value == nil ? .regular : .medium))
      .monospacedDigit()
      .foregroundStyle(foreground)
      .frame(width: width, alignment: .trailing)
      .contentTransition(.numericText())
  }

  @ViewBuilder private func testerDeviceCell(_ devices: [AppStoreTesterDevice]) -> some View {
    if let device = devices.first {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(device.model?.nonempty ?? friendlyTesterPlatform(device.platform))
            .font(.system(size: 9.5, weight: .medium))
            .lineLimit(1)
          if devices.count > 1 {
            Text("+\(devices.count - 1)")
              .font(.system(size: 7.5, weight: .semibold))
              .foregroundStyle(Studio.secondary)
          }
        }
        Text(
          device.osVersion.map { "\(friendlyTesterPlatform(device.platform)) \($0)" }
            ?? friendlyTesterPlatform(device.platform)
        )
          .font(.system(size: 8.5))
          .foregroundStyle(Studio.secondary)
          .lineLimit(1)
      }
      .help(
        devices.map { device in
          [
            device.model?.nonempty,
            device.osVersion.map { "\(friendlyTesterPlatform(device.platform)) \($0)" },
            device.appBuildVersion.map { "Build \($0)" },
          ].compactMap { $0 }.joined(separator: " · ")
        }.joined(separator: "\n"))
    } else {
      Text("—")
        .font(.system(size: 10))
        .foregroundStyle(Studio.tertiary)
    }
  }

  private func friendlyTesterPlatform(_ value: String?) -> String {
    switch value?.uppercased() {
    case "IOS": "iOS"
    case "MAC_OS": "macOS"
    case "TV_OS": "tvOS"
    case "WATCH_OS": "watchOS"
    case "VISION_OS": "visionOS"
    default: friendlyValue(value)
    }
  }

  @ViewBuilder private var appStoreFeedbackContent: some View {
    if let error = model.appStoreSectionErrors[.feedback], model.appStoreFeedback.isEmpty {
      DeployEmptyState(
        symbol: "exclamationmark.triangle", title: "Feedback unavailable", detail: error,
        actionTitle: "Retry", action: {
          Task { await model.refreshAppStoreDeploymentData(discoverTarget: false) }
        })
    } else if model.appStoreFeedback.isEmpty {
      DeployEmptyState(
        symbol: "bubble.left.and.bubble.right", title: "No TestFlight feedback",
        detail: "Apple returned no screenshot or crash feedback for this app.")
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 10) {
          ForEach(model.appStoreFeedback) { feedback in
            feedbackRow(feedback)
          }
        }
        .padding(16)
      }
    }
  }

  @ViewBuilder private var appStoreBuildDetailsContent: some View {
    if let build = model.selectedAppStoreBuild {
      ScrollView {
        VStack(spacing: 0) {
          DeployInfoRow(label: "Version", value: build.marketingVersion ?? "Not reported")
          DeployInfoRow(label: "Build", value: build.version)
          DeployInfoRow(label: "Processing", value: friendlyBuildState(build.processingState))
          DeployInfoRow(label: "Audience", value: friendlyValue(build.audienceType))
          DeployInfoRow(label: "Minimum OS", value: build.minimumOSVersion ?? "Not reported")
          DeployInfoRow(
            label: "Uploaded",
            value: build.uploadedDate?.formatted(date: .abbreviated, time: .shortened)
              ?? "Not reported")
          DeployInfoRow(
            label: "Expires",
            value: build.expirationDate?.formatted(date: .abbreviated, time: .shortened)
              ?? "Not reported")
          DeployInfoRow(
            label: "Encryption",
            value: build.usesNonExemptEncryption.map { $0 ? "Non-exempt" : "Exempt" }
              ?? "Not reported")
        }
        .padding(24)
      }
    } else {
      DeployEmptyState(
        symbol: "hammer", title: "Choose a build",
        detail: "Select a TestFlight build from the Builds list to inspect it.")
    }
  }

  private var insightsColumn: some View {
    VStack(spacing: 14) {
      DeploySurface {
        VStack(alignment: .leading, spacing: 0) {
          HStack {
            Text("Testers").font(.system(size: 12, weight: .semibold))
            Spacer()
            if !model.appStoreBetaGroups.isEmpty {
              Text("\(model.appStoreBetaGroups.count) groups")
                .font(.system(size: 9.5))
                .foregroundStyle(Studio.secondary)
            }
          }
          .padding(.horizontal, 20)
          .frame(height: 54)
          Divider().overlay(Studio.separator)
          if model.appStoreBetaGroups.isEmpty {
            DeployEmptyState(
              symbol: "person.2", title: "No testers",
              detail: model.appStoreConnectionPhase == .disconnected
                ? "Connect App Store Connect to load TestFlight groups."
                : (model.appStoreSectionErrors[.testers]
                  ?? "Apple returned no TestFlight groups."))
          } else {
            ScrollView {
              LazyVStack(spacing: 0) {
                ForEach(Array(model.appStoreBetaGroups.prefix(6))) { group in
                  betaGroupRow(group, compact: true)
                }
              }
            }
          }
        }
      }
      .frame(maxHeight: .infinity)

      DeploySurface {
        VStack(alignment: .leading, spacing: 0) {
          Text("Recent Feedback")
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 20)
            .frame(height: 54)
          Divider().overlay(Studio.separator)
          if model.appStoreFeedback.isEmpty {
            DeployEmptyState(
              symbol: "bubble.left", title: "No feedback yet",
              detail: model.appStoreConnectionPhase == .disconnected
                ? "Connect App Store Connect to load tester feedback."
                : (model.appStoreSectionErrors[.feedback]
                  ?? "Apple returned no TestFlight feedback."))
          } else {
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(Array(model.appStoreFeedback.prefix(5))) { feedback in
                  feedbackRow(feedback, compact: true)
                }
              }
              .padding(10)
            }
          }
        }
      }
      .frame(maxHeight: .infinity)
    }
  }

  private var appPreview: some View {
    HStack(spacing: 15) {
      Group {
        if let iconURL = model.appStoreBuildIcon?.downloadURL {
          AsyncImage(url: iconURL) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            case .failure: appPreviewPlaceholder
            default: ProgressView().controlSize(.small)
            }
          }
        } else {
          appPreviewPlaceholder
        }
      }
      .frame(width: 82, height: 82)
      .background(Studio.raised)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

      VStack(alignment: .leading, spacing: 5) {
        Text(model.selectedAppStoreApp?.name ?? "No app selected")
          .font(.system(size: 16, weight: .bold))
          .lineLimit(1)
        Text(model.selectedAppStoreApp?.bundleID ?? "Choose an accessible App Store app.")
          .font(.system(size: 10.5))
          .foregroundStyle(Studio.secondary)
          .monospaced(model.selectedAppStoreApp != nil)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var appPreviewPlaceholder: some View {
    Image(systemName: model.selectedAppStoreApp == nil ? "app.dashed" : "app.badge.checkmark")
      .font(.system(size: 27, weight: .light))
      .foregroundStyle(model.selectedAppStoreApp == nil ? Studio.tertiary : Studio.accent)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var releaseInformation: some View {
    VStack(spacing: 0) {
      DeployInfoRow(
        label: "Version", value: model.selectedAppStoreVersion?.versionString ?? "Not selected")
      DeployInfoRow(
        label: "Status",
        value: model.selectedAppStoreVersion.map { friendlyAppStoreState($0.state) }
          ?? "Not available")
      DeployInfoRow(
        label: "Release",
        value: friendlyValue(model.selectedAppStoreVersion?.releaseType))
      DeployInfoRow(
        label: "Build",
        value: buildForSelectedVersion?.version ?? model.selectedAppStoreBuild?.version ?? "Not attached")
    }
  }

  private var buildInformation: some View {
    VStack(spacing: 0) {
      DeployInfoRow(label: "Platform", value: "iOS")
      DeployInfoRow(label: "Scheme", value: model.selectedScheme.isEmpty ? "Not selected" : model.selectedScheme)
      DeployInfoRow(label: "Destination", value: model.selectedDestination?.name ?? "Not selected")
      DeployInfoRow(label: "Bundle ID", value: model.selectedTarget?.bundleID ?? "Not available")
    }
  }

  private var screenshotSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Screenshots").font(.system(size: 11.5, weight: .semibold))
      Text(screenshotSummary)
        .font(.system(size: 10.5))
        .foregroundStyle(Studio.secondary)
    }
    .padding(18)
  }

  private func deploySection<Content: View>(
    title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(title).font(.system(size: 11.5, weight: .semibold))
      content()
      Spacer(minLength: 0)
    }
    .padding(16)
    .frame(maxWidth: .infinity, minHeight: 184, alignment: .topLeading)
    .background(Studio.backdrop.opacity(0.7))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func deployTextSection(title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.system(size: 11.5, weight: .semibold))
      Text(detail)
        .font(.system(size: 10.5))
        .foregroundStyle(Studio.secondary)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var primaryWhatsNew: String? {
    let primaryLocale = model.selectedAppStoreApp?.primaryLocale
    return model.appStoreLocalizations.first {
      $0.locale.caseInsensitiveCompare(primaryLocale ?? "") == .orderedSame
        && $0.whatsNew?.nonempty != nil
    }?.whatsNew?.nonempty
      ?? model.appStoreLocalizations.first { $0.whatsNew?.nonempty != nil }?.whatsNew?.nonempty
  }

  private var buildForSelectedVersion: AppStoreBuild? {
    guard let buildID = model.selectedAppStoreVersion?.buildID else { return nil }
    return model.appStoreBuilds.first { $0.id == buildID }
  }

  private var selectedBuildSummary: String {
    guard let build = buildForSelectedVersion ?? model.selectedAppStoreBuild else {
      return "No build is attached to the selected App Store version."
    }
    let version = build.marketingVersion.map { "\($0) (\(build.version))" } ?? build.version
    return "Build \(version) · \(friendlyBuildState(build.processingState))"
  }

  private var screenshotSummary: String {
    if let error = model.appStoreSectionErrors[.screenshots] { return error }
    let count = model.appStoreScreenshotSets.reduce(0) { $0 + $1.screenshots.count }
    guard count > 0 else { return "Apple returned no screenshots for the selected version." }
    return "\(count) remote screenshot\(count == 1 ? "" : "s") across \(model.appStoreScreenshotSets.count) localized set\(model.appStoreScreenshotSets.count == 1 ? "" : "s")."
  }

  private func betaGroupRow(_ group: AppStoreBetaGroup, compact: Bool = false) -> some View {
    HStack(spacing: 10) {
      Image(systemName: group.isInternal ? "person.2.fill" : "globe")
        .font(.system(size: compact ? 10 : 12, weight: .medium))
        .foregroundStyle(group.isInternal ? Studio.accent : Studio.secondary)
        .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
        .background(group.isInternal ? Studio.accentSoft : Studio.raised)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      VStack(alignment: .leading, spacing: 3) {
        Text(group.name)
          .font(.system(size: compact ? 9.5 : 11, weight: .semibold))
          .lineLimit(1)
        HStack(spacing: 5) {
          Text(group.isInternal ? "Internal" : "External")
          if let count = group.testerCount { Text("· \(count) tester\(count == 1 ? "" : "s")") }
        }
        .font(.system(size: compact ? 8.5 : 9.5))
        .foregroundStyle(Studio.secondary)
      }
      Spacer(minLength: 4)
    }
    .padding(.horizontal, compact ? 12 : 20)
    .frame(minHeight: compact ? 42 : 56)
  }

  private func feedbackRow(_ feedback: AppStoreFeedback, compact: Bool = false) -> some View {
    let title = feedback.comment?.nonempty
      ?? (feedback.kind == .crash ? "Crash report" : "Screenshot feedback")

    return HStack(alignment: .top, spacing: compact ? 10 : 14) {
      feedbackTypeIcon(feedback, compact: compact)

      VStack(alignment: .leading, spacing: compact ? 5 : 8) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(title)
            .font(.system(size: compact ? 9.5 : 11.5, weight: .semibold))
            .lineLimit(compact ? 2 : 3)
            .fixedSize(horizontal: false, vertical: true)

          if !compact {
            Spacer(minLength: 4)
            feedbackKindBadge(feedback)
          }
        }

        feedbackMetadata(feedback, compact: compact)

        if !compact {
          Button {
            Task { await model.startAgentTask(for: feedback) }
          } label: {
            Label(
              model.isPreparingFeedbackAgentTask ? "Preparing…" : "Fix with Agent",
              systemImage: "wand.and.sparkles")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .tint(Studio.accent)
          .font(.system(size: 9.5, weight: .medium))
          .disabled(model.isBusy || model.isPreparingFeedbackAgentTask)
          .help("Start a task in the selected coding agent with this feedback and its screenshots")
          .padding(.top, 1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if let imageURL = feedback.imageURL {
        feedbackThumbnail(feedback, imageURL: imageURL, compact: compact)
      }
    }
    .padding(.horizontal, compact ? 10 : 16)
    .padding(.vertical, compact ? 10 : 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Studio.raised.opacity(compact ? 0.58 : 0.52))
    .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
    .accessibilityElement(children: .contain)
  }

  private func feedbackTypeIcon(_ feedback: AppStoreFeedback, compact: Bool) -> some View {
    let isCrash = feedback.kind == .crash
    return Image(systemName: isCrash ? "exclamationmark.triangle" : "bubble.left")
      .font(.system(size: compact ? 10 : 13, weight: .medium))
      .foregroundStyle(isCrash ? Studio.warning : Studio.accent)
      .frame(width: compact ? 26 : 36, height: compact ? 26 : 36)
      .background(isCrash ? Studio.raised : Studio.accentSoft)
      .clipShape(RoundedRectangle(cornerRadius: compact ? 7 : 10, style: .continuous))
      .accessibilityHidden(true)
  }

  private func feedbackKindBadge(_ feedback: AppStoreFeedback) -> some View {
    let isCrash = feedback.kind == .crash
    return Label(
      isCrash ? "Crash" : "Screenshot",
      systemImage: isCrash ? "exclamationmark.triangle.fill" : "photo")
      .font(.system(size: 8.5, weight: .semibold))
      .foregroundStyle(isCrash ? Studio.warning : Studio.accent)
      .padding(.horizontal, 7)
      .frame(height: 22)
      .background((isCrash ? Studio.warning : Studio.accent).opacity(0.11))
      .clipShape(Capsule())
  }

  private func feedbackMetadata(_ feedback: AppStoreFeedback, compact: Bool) -> some View {
    HStack(spacing: 5) {
      if let device = feedback.deviceModel?.nonempty {
        Text(device)
      }
      if let os = feedback.osVersion?.nonempty {
        feedbackMetadataSeparator
        Text(os)
      }
      if let date = feedback.createdDate {
        feedbackMetadataSeparator
        Text(date.formatted(date: .abbreviated, time: .omitted))
      }
    }
    .font(.system(size: compact ? 8.5 : 9.5))
    .foregroundStyle(Studio.secondary)
    .lineLimit(1)
    .truncationMode(.tail)
  }

  private var feedbackMetadataSeparator: some View {
    Text("·")
      .foregroundStyle(Studio.tertiary)
  }

  private func feedbackThumbnail(
    _ feedback: AppStoreFeedback, imageURL: URL, compact: Bool
  ) -> some View {
    Button { feedbackScreenshot = feedback } label: {
      ZStack(alignment: .topTrailing) {
        AsyncImage(url: imageURL) { phase in
          switch phase {
          case .success(let image): image.resizable().scaledToFit().padding(4)
          case .failure:
            Image(systemName: "photo.badge.exclamationmark")
              .font(.system(size: compact ? 11 : 14))
              .foregroundStyle(Studio.tertiary)
          default: ProgressView().controlSize(.mini)
          }
        }
        .frame(width: compact ? 44 : 76, height: compact ? 58 : 98)
        .background(Studio.surface)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous))

        if feedback.imageURLs.count > 1 {
          Text("\(feedback.imageURLs.count)")
            .font(.system(size: 7.5, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minHeight: 14)
            .background(Color.black.opacity(0.72))
            .clipShape(Capsule())
            .padding(3)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("Open feedback screenshot")
    .accessibilityLabel(
      "Open \(feedback.imageURLs.count) feedback screenshot\(feedback.imageURLs.count == 1 ? "" : "s")")
    .layoutPriority(1)
  }

  private func friendlyAppStoreState(_ value: String) -> String {
    switch value {
    case "READY_FOR_DISTRIBUTION", "READY_FOR_SALE": "Ready for Distribution"
    case "PREPARE_FOR_SUBMISSION": "Prepare for Submission"
    case "WAITING_FOR_REVIEW": "Waiting for Review"
    case "IN_REVIEW": "In Review"
    case "PENDING_DEVELOPER_RELEASE": "Pending Developer Release"
    case "PROCESSING_FOR_DISTRIBUTION", "PROCESSING_FOR_APP_STORE": "Processing"
    default: friendlyValue(value)
    }
  }

  private func friendlyBuildState(_ value: String) -> String {
    switch value {
    case "VALID": "Ready"
    case "PROCESSING": "Processing"
    case "FAILED": "Processing Failed"
    case "INVALID": "Invalid"
    default: friendlyValue(value)
    }
  }

  private func friendlyScreenshotType(_ value: String) -> String {
    value.replacingOccurrences(of: "APP_", with: "")
      .replacingOccurrences(of: "_", with: " ")
      .capitalized
  }

  private func friendlyValue(_ value: String?) -> String {
    guard let value = value?.nonempty else { return "Not reported" }
    return value.replacingOccurrences(of: "_", with: " ").capitalized
  }

  private func chooseScreenshot(_ completion: (URL) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.png, .jpeg]
    panel.prompt = "Choose Screenshot"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    completion(url)
  }
}

private struct ScreenshotRemoval: Identifiable {
  var id: String
  var fileName: String
}

private struct FeedbackScreenshotViewer: View {
  @Environment(\.dismiss) private var dismiss
  let feedback: AppStoreFeedback
  @State private var selectedIndex = 0
  @State private var image: NSImage?
  @State private var loadError: String?
  @State private var status: String?

  private var selectedURL: URL? {
    guard feedback.imageURLs.indices.contains(selectedIndex) else { return nil }
    return feedback.imageURLs[selectedIndex]
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text(feedback.comment?.nonempty ?? "Feedback screenshot")
            .font(.system(size: 17, weight: .bold))
            .lineLimit(2)
          Text(feedbackMetadata)
            .font(.system(size: 10))
            .foregroundStyle(Studio.secondary)
        }
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
      .padding(20)

      Divider().overlay(Studio.separator)

      Group {
        if let image {
          Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .padding(20)
        } else if let loadError {
          DeployEmptyState(
            symbol: "photo.badge.exclamationmark", title: "Screenshot unavailable",
            detail: loadError, actionTitle: "Retry",
            action: { Task { await loadSelectedImage() } })
        } else {
          ProgressView("Loading screenshot…")
            .controlSize(.small)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Studio.raised)

      if feedback.imageURLs.count > 1 {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(Array(feedback.imageURLs.enumerated()), id: \.offset) { index, url in
              Button { selectedIndex = index } label: {
                AsyncImage(url: url) { phase in
                  switch phase {
                  case .success(let thumbnail): thumbnail.resizable().scaledToFill()
                  case .failure:
                    Image(systemName: "photo.badge.exclamationmark")
                      .foregroundStyle(Studio.tertiary)
                  default: ProgressView().controlSize(.mini)
                  }
                }
                .frame(width: 58, height: 58)
                .background(Studio.raised)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                  RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selectedIndex == index ? Studio.accent : .clear, lineWidth: 2)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Show feedback screenshot \(index + 1)")
            }
          }
          .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .frame(height: 78)
      }

      Divider().overlay(Studio.separator)
      HStack(spacing: 10) {
        if let status {
          Text(status).font(.system(size: 9.5)).foregroundStyle(Studio.secondary)
        }
        Spacer()
        Button("Copy", systemImage: "doc.on.doc", action: copyImage)
          .disabled(image == nil)
        Button("Save…", systemImage: "square.and.arrow.down", action: saveImage)
          .disabled(image == nil)
      }
      .padding(.horizontal, 20)
      .frame(height: 58)
    }
    .frame(width: 760, height: 720)
    .background(Studio.surface)
    .task(id: selectedURL) { await loadSelectedImage() }
  }

  private var feedbackMetadata: String {
    [
      feedback.deviceModel, feedback.osVersion,
      feedback.createdDate?.formatted(date: .abbreviated, time: .shortened),
    ].compactMap { $0 }.joined(separator: " · ")
  }

  private func loadSelectedImage() async {
    image = nil
    loadError = nil
    status = nil
    guard let selectedURL else {
      loadError = "Apple did not provide a valid screenshot URL."
      return
    }
    do {
      let (data, response) = try await URLSession.shared.data(from: selectedURL)
      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw URLError(.badServerResponse)
      }
      guard let loaded = NSImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
      image = loaded
    } catch {
      loadError = "The TestFlight screenshot could not be downloaded: \(error.localizedDescription)"
    }
  }

  private func copyImage() {
    guard let image else { return }
    NSPasteboard.general.clearContents()
    if NSPasteboard.general.writeObjects([image]) { status = "Copied to Clipboard" }
  }

  private func saveImage() {
    guard let image else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = "testflight-feedback-\(selectedIndex + 1).png"
    panel.prompt = "Save"
    guard panel.runModal() == .OK, let destination = panel.url else { return }
    do {
      guard let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
      else { throw CocoaError(.fileWriteUnknown) }
      try png.write(to: destination, options: .atomic)
      status = "Saved \(destination.lastPathComponent)"
    } catch {
      status = "Save failed: \(error.localizedDescription)"
    }
  }
}

private struct AppStoreReleaseSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var model: AppModel
  @State private var existingVersionID = ""
  @State private var versionString = ""
  @State private var buildID = ""
  @State private var releaseType: AppStoreReleaseType = .manual
  @State private var scheduledDate = Date().addingTimeInterval(86_400)
  @State private var locale = "en-US"
  @State private var whatsNew = ""
  @State private var usesNonExemptEncryption: Bool?
  @State private var betaGroupIDs: Set<String> = []
  @State private var submitForBetaReview = false
  @State private var submitForAppReview = false
  @State private var confirmsAppReview = false
  @State private var didInitialize = false

  private var editableVersions: [AppStoreVersion] {
    model.appStoreVersions.filter {
      ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"]
        .contains($0.state)
    }
  }

  private var validBuilds: [AppStoreBuild] {
    model.appStoreBuilds.filter { $0.processingState == "VALID" && !$0.expired }
  }

  private var selectedBuild: AppStoreBuild? {
    model.appStoreBuilds.first { $0.id == buildID }
  }

  private var isAppStoreEligibleBuild: Bool {
    selectedBuild?.audienceType != "INTERNAL_ONLY"
  }

  private var needsComplianceAnswer: Bool {
    selectedBuild?.usesNonExemptEncryption == nil
  }

  private var selectedExternalGroup: Bool {
    model.appStoreBetaGroups.contains {
      betaGroupIDs.contains($0.id) && !$0.isInternal && !$0.hasAccessToAllBuilds
    }
  }

  private var canContinue: Bool {
    !versionString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !buildID.isEmpty
      && !whatsNew.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (!needsComplianceAnswer || usesNonExemptEncryption != nil)
      && !model.appStoreReleasePhase.isRunning
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: "paperplane.fill")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(Studio.accent)
          .frame(width: 38, height: 38)
          .background(Studio.accentSoft)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        VStack(alignment: .leading, spacing: 3) {
          Text("Release an Update")
            .font(.system(size: 17, weight: .bold))
          Text("Prepare the version, TestFlight access, and App Review without leaving Lys.")
            .font(.system(size: 10))
            .foregroundStyle(Studio.secondary)
        }
        Spacer()
        if !model.appStoreReleasePhase.isRunning {
          Button("Close") { dismiss() }
            .keyboardShortcut(.cancelAction)
        }
      }
      .padding(20)

      Divider().overlay(Studio.separator)

      if model.appStoreReleasePhase == .complete {
        releaseResult
      } else {
        releaseForm
      }
    }
    .frame(width: 680, height: 760)
    .background(Studio.surface)
    .interactiveDismissDisabled(model.appStoreReleasePhase.isRunning)
    .onAppear(perform: initialize)
    .onChange(of: buildID) { _, _ in updateNewVersionFromBuild() }
    .onChange(of: model.appStoreLocalizations) { _, localizations in
      guard !existingVersionID.isEmpty, whatsNew.isEmpty else { return }
      whatsNew = preferredWhatsNew(in: localizations) ?? ""
    }
    .onChange(of: existingVersionID) { _, newValue in
      guard let version = editableVersions.first(where: { $0.id == newValue }) else {
        updateNewVersionFromBuild()
        return
      }
      versionString = version.versionString
      releaseType = AppStoreReleaseType(rawValue: version.releaseType ?? "") ?? .manual
      if let date = version.earliestReleaseDate { scheduledDate = date }
      if let build = model.appStoreBuilds.first(where: { $0.id == version.buildID }) {
        buildID = build.id
      }
      if model.appStoreSelectedVersionID != version.id {
        model.selectAppStoreVersion(version.id)
        whatsNew = ""
      } else {
        whatsNew = preferredWhatsNew(in: model.appStoreLocalizations) ?? whatsNew
      }
    }
    .alert("Submit this update to App Review?", isPresented: $confirmsAppReview) {
      Button("Cancel", role: .cancel) {}
      Button("Submit to Apple") { performRelease() }
    } message: {
      Text(
        "Apple will begin reviewing version \(versionString). If required metadata is missing, Lys will stop and show Apple's exact validation message."
      )
    }
  }

  private var releaseForm: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          releaseSection("Version & build") {
            Picker("Version record", selection: $existingVersionID) {
              Text("Create a new version").tag("")
              ForEach(editableVersions) { version in
                Text("Continue version \(version.versionString)").tag(version.id)
              }
            }
            if existingVersionID.isEmpty {
              TextField("Version number", text: $versionString)
                .textFieldStyle(.roundedBorder)
            } else {
              releaseValue("Version", versionString)
            }
            Picker("Processed build", selection: $buildID) {
              Text("Choose a build").tag("")
              ForEach(validBuilds) { build in
                Text(buildLabel(build)).tag(build.id)
              }
            }
            if validBuilds.isEmpty {
              Label("Upload a build and wait for Apple processing before releasing.", systemImage: "info.circle")
                .font(.system(size: 9.5))
                .foregroundStyle(Studio.secondary)
            }
          }

          releaseSection("Release notes") {
            HStack {
              Text("Locale")
              Spacer()
              TextField("Locale", text: $locale)
                .frame(width: 110)
                .textFieldStyle(.roundedBorder)
            }
            TextEditor(text: $whatsNew)
              .font(.system(size: 10.5))
              .frame(minHeight: 90)
              .padding(6)
              .background(Studio.backdrop.opacity(0.7))
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .stroke(Studio.separator, lineWidth: 1)
              }
            Text("What's New is saved to the selected app's primary locale.")
              .font(.system(size: 9))
              .foregroundStyle(Studio.secondary)
          }

          releaseSection("Customer release") {
            Picker("After approval", selection: $releaseType) {
              Text("Release manually").tag(AppStoreReleaseType.manual)
              Text("Release automatically").tag(AppStoreReleaseType.automatic)
              Text("Release on a date").tag(AppStoreReleaseType.scheduled)
            }
            if releaseType == .scheduled {
              DatePicker(
                "Release date", selection: $scheduledDate, in: Date()...,
                displayedComponents: [.date, .hourAndMinute])
            }
          }

          if needsComplianceAnswer {
            releaseSection("Export compliance required") {
              Text("Does this build use non-exempt encryption?")
                .font(.system(size: 10.5, weight: .semibold))
              Picker("Encryption", selection: $usesNonExemptEncryption) {
                Text("Choose an answer").tag(Optional<Bool>.none)
                Text("No — exempt or no encryption").tag(Optional(false))
                Text("Yes — non-exempt encryption").tag(Optional(true))
              }
              Text(
                usesNonExemptEncryption == true
                  ? "Apple may require an approved encryption declaration or supporting document before review."
                  : "Lys asks only because Apple marked this build's compliance answer as missing."
              )
              .font(.system(size: 9))
              .foregroundStyle(usesNonExemptEncryption == true ? Studio.warning : Studio.secondary)
            }
          }

          releaseSection("TestFlight groups") {
            if model.appStoreBetaGroups.isEmpty {
              Text("Apple returned no tester groups for this app.")
                .font(.system(size: 9.5))
                .foregroundStyle(Studio.secondary)
            } else {
              ForEach(model.appStoreBetaGroups) { group in
                Toggle(isOn: groupBinding(group)) {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.system(size: 10.5, weight: .medium))
                    Text(
                      group.hasAccessToAllBuilds
                        ? "Already receives every build"
                        : "\(group.isInternal ? "Internal" : "External") · \(group.testerCount ?? group.testers.count) testers"
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(Studio.secondary)
                  }
                }
                .disabled(
                  group.hasAccessToAllBuilds
                    || (!isAppStoreEligibleBuild && !group.isInternal))
              }
            }
            Toggle("Submit for TestFlight beta review", isOn: $submitForBetaReview)
              .disabled(!selectedExternalGroup)
            Text("External groups require Apple's beta review; internal groups do not.")
              .font(.system(size: 9))
              .foregroundStyle(Studio.secondary)
          }

          releaseSection("App Review") {
            Toggle("Submit this version to App Review now", isOn: $submitForAppReview)
              .disabled(!isAppStoreEligibleBuild)
            if !isAppStoreEligibleBuild {
              Text("This build was uploaded as internal-only and can never be submitted to the App Store.")
                .font(.system(size: 9.5))
                .foregroundStyle(Studio.warning)
            }
            HStack(spacing: 6) {
              Image(
                systemName: existingVersionID.isEmpty
                  ? "info.circle" : (model.appStoreScreenshotSets.isEmpty
                    ? "exclamationmark.triangle" : "checkmark.circle"))
                .foregroundStyle(
                  existingVersionID.isEmpty ? Studio.accent
                    : (model.appStoreScreenshotSets.isEmpty ? Studio.warning : Studio.success))
              Text(
                existingVersionID.isEmpty
                  ? "Lys will verify the new version after creation. Edit carried-forward assets in the Screenshots tab."
                  : (model.appStoreScreenshotSets.isEmpty
                    ? "No screenshots are loaded for this version. Add them in the Screenshots tab before review."
                    : "\(model.appStoreScreenshotSets.reduce(0) { $0 + $1.screenshots.count }) screenshots are loaded.")
              )
            }
            .font(.system(size: 9.5))
            .foregroundStyle(Studio.secondary)
          }
        }
        .padding(20)
        .disabled(model.appStoreReleasePhase.isRunning)
      }

      Divider().overlay(Studio.separator)
      VStack(alignment: .leading, spacing: 10) {
        if let error = model.appStoreReleaseError {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 9.5))
            .foregroundStyle(Studio.warning)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        } else if model.appStoreReleasePhase.isRunning {
          HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text(model.appStoreReleaseStatus)
          }
          .font(.system(size: 9.5, weight: .medium))
        }
        HStack {
          Text("Each remote change is saved step by step; a failure never rolls back completed Apple changes.")
            .font(.system(size: 9))
            .foregroundStyle(Studio.secondary)
          Spacer()
          Button("Cancel") { dismiss() }
            .disabled(model.appStoreReleasePhase.isRunning)
          Button(submitForAppReview ? "Review & Submit" : "Prepare Update") {
            if submitForAppReview { confirmsAppReview = true } else { performRelease() }
          }
          .buttonStyle(.borderedProminent)
          .disabled(!canContinue)
        }
      }
      .padding(16)
    }
  }

  private var releaseResult: some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 34))
        .foregroundStyle(Studio.success)
      Text(submitForAppReview ? "Update submitted" : "Update prepared")
        .font(.system(size: 16, weight: .bold))
      Text(model.appStoreReleaseStatus)
        .font(.system(size: 10.5))
        .foregroundStyle(Studio.secondary)
        .multilineTextAlignment(.center)
      Button("Done") { dismiss() }
        .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(32)
  }

  private func releaseSection<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.system(size: 11.5, weight: .semibold))
      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Studio.backdrop.opacity(0.55))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func releaseValue(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label).foregroundStyle(Studio.secondary)
      Spacer()
      Text(value).fontWeight(.medium)
    }
    .font(.system(size: 10))
  }

  private func groupBinding(_ group: AppStoreBetaGroup) -> Binding<Bool> {
    Binding(
      get: { group.hasAccessToAllBuilds || betaGroupIDs.contains(group.id) },
      set: { selected in
        if selected { betaGroupIDs.insert(group.id) } else { betaGroupIDs.remove(group.id) }
        if !selectedExternalGroup { submitForBetaReview = false }
      })
  }

  private func initialize() {
    guard !didInitialize else { return }
    didInitialize = true
    locale = model.selectedAppStoreApp?.primaryLocale ?? "en-US"
    if let selected = editableVersions.first(where: { $0.id == model.appStoreSelectedVersionID }) {
      existingVersionID = selected.id
      versionString = selected.versionString
      releaseType = AppStoreReleaseType(rawValue: selected.releaseType ?? "") ?? .manual
      if let date = selected.earliestReleaseDate { scheduledDate = date }
      if let selectedBuildID = selected.buildID { buildID = selectedBuildID }
      whatsNew = preferredWhatsNew(in: model.appStoreLocalizations) ?? ""
    }
    if let build = validBuilds.first {
      if buildID.isEmpty { buildID = build.id }
      if versionString.isEmpty { versionString = build.marketingVersion ?? "" }
    }
    usesNonExemptEncryption = selectedBuild?.usesNonExemptEncryption
    betaGroupIDs = Set(model.appStoreBetaGroups.filter(\.hasAccessToAllBuilds).map(\.id))
  }

  private func updateNewVersionFromBuild() {
    guard let build = selectedBuild else { return }
    if existingVersionID.isEmpty, let marketingVersion = build.marketingVersion {
      versionString = marketingVersion
    }
    usesNonExemptEncryption = build.usesNonExemptEncryption
    if !isAppStoreEligibleBuild {
      let externalIDs = Set(model.appStoreBetaGroups.filter { !$0.isInternal }.map(\.id))
      betaGroupIDs.subtract(externalIDs)
      submitForBetaReview = false
      submitForAppReview = false
    }
  }

  private func buildLabel(_ build: AppStoreBuild) -> String {
    if let marketingVersion = build.marketingVersion {
      return "Version \(marketingVersion) · build \(build.version)"
    }
    return "Build \(build.version)"
  }

  private func preferredWhatsNew(
    in localizations: [AppStoreVersionLocalization]
  ) -> String? {
    localizations.first {
      $0.locale.caseInsensitiveCompare(locale) == .orderedSame
    }?.whatsNew?.nonempty ?? localizations.first?.whatsNew?.nonempty
  }

  private func performRelease() {
    let configuration = AppStoreReleaseConfiguration(
      existingVersionID: existingVersionID.nonempty, versionString: versionString,
      releaseType: releaseType,
      earliestReleaseDate: releaseType == .scheduled ? scheduledDate : nil,
      locale: locale, whatsNew: whatsNew, buildID: buildID,
      usesNonExemptEncryption: usesNonExemptEncryption,
      betaGroupIDs: Set(betaGroupIDs.filter { groupID in
        model.appStoreBetaGroups.first(where: { $0.id == groupID })?.hasAccessToAllBuilds != true
      }),
      submitForBetaReview: submitForBetaReview, submitForAppReview: submitForAppReview)
    Task { await model.releaseAppStoreUpdate(configuration) }
  }
}

private struct AppStoreBuildDistributionSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var model: AppModel
  @State private var buildID = ""
  @State private var betaGroupIDs: Set<String> = []
  @State private var usesNonExemptEncryption: Bool?
  @State private var submitForBetaReview = false

  private var validBuilds: [AppStoreBuild] {
    model.appStoreBuilds.filter { $0.processingState == "VALID" && !$0.expired }
  }

  private var selectedBuild: AppStoreBuild? {
    model.appStoreBuilds.first { $0.id == buildID }
  }

  private var selectedExternalGroup: Bool {
    model.appStoreBetaGroups.contains {
      betaGroupIDs.contains($0.id) && !$0.isInternal && !$0.hasAccessToAllBuilds
    }
  }

  private var needsComplianceAnswer: Bool {
    selectedBuild?.usesNonExemptEncryption == nil
  }

  private var canDistribute: Bool {
    !buildID.isEmpty && !betaGroupIDs.isEmpty
      && (!needsComplianceAnswer || usesNonExemptEncryption != nil)
      && !model.appStoreReleasePhase.isRunning
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: "person.2.badge.plus")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(Studio.accent)
          .frame(width: 38, height: 38)
          .background(Studio.accentSoft)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        VStack(alignment: .leading, spacing: 3) {
          Text("Send Build to Testers")
            .font(.system(size: 17, weight: .bold))
          Text("Give TestFlight groups access to a processed build.")
            .font(.system(size: 10))
            .foregroundStyle(Studio.secondary)
        }
        Spacer()
        if !model.appStoreReleasePhase.isRunning {
          Button("Close") { dismiss() }
            .keyboardShortcut(.cancelAction)
        }
      }
      .padding(20)

      Divider().overlay(Studio.separator)

      if model.appStoreReleasePhase == .complete {
        distributionResult
      } else {
        distributionForm
      }
    }
    .frame(width: 540, height: 620)
    .background(Studio.surface)
    .interactiveDismissDisabled(model.appStoreReleasePhase.isRunning)
    .onAppear(perform: initialize)
    .onChange(of: buildID) { _, _ in
      usesNonExemptEncryption = selectedBuild?.usesNonExemptEncryption
      removeIneligibleExternalGroups()
    }
    .onChange(of: betaGroupIDs) { _, _ in
      submitForBetaReview = selectedExternalGroup
    }
  }

  private var distributionForm: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          distributionSection("Processed build") {
            Picker("Build", selection: $buildID) {
              Text("Choose a build").tag("")
              ForEach(validBuilds) { build in
                Text(buildLabel(build)).tag(build.id)
              }
            }
            if validBuilds.isEmpty {
              Label(
                "Apple has not returned a processed build yet.",
                systemImage: "clock")
                .font(.system(size: 9.5))
                .foregroundStyle(Studio.secondary)
            }
          }

          distributionSection("TestFlight groups") {
            ForEach(model.appStoreBetaGroups) { group in
              if group.hasAccessToAllBuilds {
                HStack(spacing: 9) {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Studio.success)
                  groupLabel(group, detail: "Already receives every build")
                  Spacer()
                }
              } else {
                Toggle(isOn: groupBinding(group)) {
                  groupLabel(
                    group,
                    detail:
                      "\(group.isInternal ? "Internal" : "External") · "
                      + "\(group.testerCount ?? group.testers.count) testers")
                }
                .disabled(selectedBuild?.audienceType == "INTERNAL_ONLY" && !group.isInternal)
              }
            }
            if model.appStoreBetaGroups.isEmpty {
              Text("Apple returned no tester groups for this app.")
                .font(.system(size: 9.5))
                .foregroundStyle(Studio.secondary)
            }
          }

          if needsComplianceAnswer {
            distributionSection("Export compliance") {
              Text("Does this build use non-exempt encryption?")
                .font(.system(size: 10.5, weight: .semibold))
              Picker("Encryption", selection: $usesNonExemptEncryption) {
                Text("Choose an answer").tag(Optional<Bool>.none)
                Text("No — exempt or no encryption").tag(Optional(false))
                Text("Yes — non-exempt encryption").tag(Optional(true))
              }
              Text("Apple requires this answer before the build can be distributed.")
                .font(.system(size: 9))
                .foregroundStyle(Studio.secondary)
            }
          }

          if selectedExternalGroup {
            distributionSection("External testing") {
              Toggle("Submit for TestFlight beta review", isOn: $submitForBetaReview)
              Text("External testers receive the build after Apple approves the beta review.")
                .font(.system(size: 9))
                .foregroundStyle(Studio.secondary)
            }
          }
        }
        .padding(20)
        .disabled(model.appStoreReleasePhase.isRunning)
      }

      Divider().overlay(Studio.separator)
      VStack(alignment: .leading, spacing: 10) {
        if let error = model.appStoreReleaseError {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 9.5))
            .foregroundStyle(Studio.warning)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        } else if model.appStoreReleasePhase.isRunning {
          HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text(model.appStoreReleaseStatus)
          }
          .font(.system(size: 9.5, weight: .medium))
        }
        HStack {
          Text("Only the selected groups gain access to this build.")
            .font(.system(size: 9))
            .foregroundStyle(Studio.secondary)
          Spacer()
          Button("Cancel") { dismiss() }
            .disabled(model.appStoreReleasePhase.isRunning)
          Button(selectedExternalGroup ? "Assign & Submit" : "Send to Testers") {
            Task {
              await model.distributeAppStoreBuild(
                buildID: buildID, betaGroupIDs: betaGroupIDs,
                usesNonExemptEncryption: usesNonExemptEncryption,
                submitForBetaReview: submitForBetaReview)
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(!canDistribute || (selectedExternalGroup && !submitForBetaReview))
        }
      }
      .padding(16)
    }
  }

  private var distributionResult: some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 34))
        .foregroundStyle(Studio.success)
      Text("Build sent to testers")
        .font(.system(size: 16, weight: .bold))
      Text(model.appStoreReleaseStatus)
        .font(.system(size: 10.5))
        .foregroundStyle(Studio.secondary)
        .multilineTextAlignment(.center)
      Button("Done") { dismiss() }
        .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(32)
  }

  private func distributionSection<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.system(size: 11.5, weight: .semibold))
      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Studio.backdrop.opacity(0.55))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func groupLabel(_ group: AppStoreBetaGroup, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(group.name).font(.system(size: 10.5, weight: .medium))
      Text(detail)
        .font(.system(size: 9))
        .foregroundStyle(Studio.secondary)
    }
  }

  private func groupBinding(_ group: AppStoreBetaGroup) -> Binding<Bool> {
    Binding(
      get: { betaGroupIDs.contains(group.id) },
      set: { selected in
        if selected {
          betaGroupIDs.insert(group.id)
        } else {
          betaGroupIDs.remove(group.id)
        }
      })
  }

  private func initialize() {
    if let selected = model.selectedAppStoreBuild,
      selected.processingState == "VALID", !selected.expired
    {
      buildID = selected.id
    } else {
      buildID = validBuilds.first?.id ?? ""
    }
    usesNonExemptEncryption = selectedBuild?.usesNonExemptEncryption
  }

  private func removeIneligibleExternalGroups() {
    guard selectedBuild?.audienceType == "INTERNAL_ONLY" else { return }
    let externalIDs = Set(model.appStoreBetaGroups.filter { !$0.isInternal }.map(\.id))
    betaGroupIDs.subtract(externalIDs)
  }

  private func buildLabel(_ build: AppStoreBuild) -> String {
    build.marketingVersion.map { "Version \($0) · build \(build.version)" }
      ?? "Build \(build.version)"
  }
}

private struct AppStoreUploadSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var model: AppModel
  var onDistribute: () -> Void = {}

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: "arrow.up.circle.fill")
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(Studio.accent)
          .frame(width: 38, height: 38)
          .background(Studio.accentSoft)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        VStack(alignment: .leading, spacing: 3) {
          Text("Archive & Upload")
            .font(.system(size: 17, weight: .bold))
          Text("Create a signed Release archive and upload it to App Store Connect.")
            .font(.system(size: 10))
            .foregroundStyle(Studio.secondary)
        }
        Spacer(minLength: 12)
        if !model.appStoreUploadPhase.isRunning {
          Button("Close") { dismiss() }
            .keyboardShortcut(.cancelAction)
        }
      }
      .padding(20)

      Divider().overlay(Studio.separator)

      Group {
        switch model.appStoreUploadPhase {
        case .idle, .preflighting:
          uploadLoadingState
        case .ready:
          uploadReview
        case .archiving, .inspecting, .uploading, .processing:
          uploadProgress
        case .complete, .uploaded:
          uploadResult
        case .failed, .cancelled:
          uploadFailure
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 620, height: 660)
    .background(Studio.surface)
    .interactiveDismissDisabled(model.appStoreUploadPhase.isRunning)
  }

  private var uploadLoadingState: some View {
    VStack(spacing: 12) {
      ProgressView().controlSize(.small)
      Text("Checking the Release target")
        .font(.system(size: 12, weight: .semibold))
      Text(model.appStoreUploadStatus.nonempty ?? "Reading version, signing, and source details…")
        .font(.system(size: 10))
        .foregroundStyle(Studio.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(30)
  }

  @ViewBuilder private var uploadReview: some View {
    if let preflight = model.appStoreUploadPreflight {
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 0) {
              uploadReviewRow("App", model.selectedAppStoreApp?.name ?? "Not selected")
              uploadReviewRow("Source", preflight.sourceRoot.path, monospaced: true)
              uploadReviewRow("Scheme", preflight.target.scheme)
              uploadReviewRow("Bundle ID", preflight.target.bundleID, monospaced: true)
              uploadReviewRow(
                "Version", "\(preflight.target.marketingVersion) (\(preflight.target.buildNumber))")
              uploadReviewRow(
                "Team",
                preflight.effectiveTeamID(
                  override: model.appStoreUploadOptions.developmentTeamID) ?? "Needed below")
              uploadReviewRow(
                "Signing",
                preflight.effectiveTeamID(
                  override: model.appStoreUploadOptions.developmentTeamID) == nil
                  ? (preflight.target.codeSignStyle ?? "Project default")
                  : "Automatic · managed by Lys")
              uploadReviewRow(
                "Distribution identity",
                preflight.distributionIdentities.first?.name ?? "Not installed", isLast: true)
            }
            .background(Studio.backdrop.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !preflight.warnings.isEmpty {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(preflight.warnings, id: \.self) { warning in
                  Label {
                    Text(warning)
                  } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                      .foregroundStyle(Studio.warning)
                  }
                  .font(.system(size: 9.5))
                  .fixedSize(horizontal: false, vertical: true)
                }
              }
            }

            VStack(alignment: .leading, spacing: 9) {
              HStack(spacing: 8) {
                Image(systemName: "person.text.rectangle")
                  .foregroundStyle(Studio.accent)
                Text("Apple signing team")
                  .font(.system(size: 11, weight: .semibold))
              }
              TextField(
                "10-character Team ID", text: $model.appStoreUploadOptions.developmentTeamID
              )
              .textFieldStyle(.roundedBorder)
              .font(.system(size: 10.5).monospaced())
              .textCase(.uppercase)
              Text(
                "Lys saves this nonsecret ID to the connected account and passes it to Xcode "
                  + "for this archive. The project file is not changed."
              )
              .font(.system(size: 9))
              .foregroundStyle(Studio.secondary)
              .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Studio.backdrop.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            let unresolvedIssues = preflight.unresolvedIssues(
              allowProvisioningUpdates: model.appStoreUploadOptions.allowProvisioningUpdates,
              developmentTeamID: model.appStoreUploadOptions.developmentTeamID)
            if !unresolvedIssues.isEmpty {
              VStack(alignment: .leading, spacing: 12) {
                Label("Signing setup required", systemImage: "exclamationmark.shield.fill")
                  .font(.system(size: 11, weight: .semibold))
                  .foregroundStyle(.red)
                ForEach(unresolvedIssues, id: \.self) { issue in
                  Text(issue)
                    .font(.system(size: 9.5))
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
              .padding(14)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.red.opacity(0.055))
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .stroke(Color.red.opacity(0.16), lineWidth: 1)
              }
            }

            VStack(alignment: .leading, spacing: 12) {
              Toggle(
                "Allow Xcode to update signing and provisioning",
                isOn: $model.appStoreUploadOptions.allowProvisioningUpdates)
              Text(
                "Uses the connected App Store Connect key only for this operation. Xcode may "
                  + "create or download eligible signing assets."
              )
              .font(.system(size: 9))
              .foregroundStyle(Studio.secondary)
              .padding(.leading, 20)

              Toggle(
                "Restrict this build to internal TestFlight testing",
                isOn: $model.appStoreUploadOptions.internalTestingOnly)
              Text(
                "Permanent for this build: it cannot later be used for external TestFlight or "
                  + "submitted to the App Store."
              )
              .font(.system(size: 9))
              .foregroundStyle(
                model.appStoreUploadOptions.internalTestingOnly ? Studio.warning : Studio.secondary)
              .padding(.leading, 20)

              Toggle("Upload symbols for crash reports", isOn: $model.appStoreUploadOptions.uploadSymbols)
            }
            .font(.system(size: 10))
          }
          .padding(20)
        }

        Divider().overlay(Studio.separator)
        HStack {
          Text("Nothing is uploaded until you approve this step.")
            .font(.system(size: 9))
            .foregroundStyle(Studio.secondary)
          Spacer()
          Button("Cancel") { dismiss() }
          Button("Archive & Upload") { model.startAppStoreUpload() }
            .buttonStyle(.borderedProminent)
            .disabled(
              !preflight.canArchive(
                allowProvisioningUpdates: model.appStoreUploadOptions.allowProvisioningUpdates,
                developmentTeamID: model.appStoreUploadOptions.developmentTeamID))
        }
        .padding(16)
      }
    } else {
      uploadFailure
    }
  }

  private var uploadProgress: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          VStack(alignment: .leading, spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text(model.appStoreUploadStatus)
              .font(.system(size: 12, weight: .semibold))
            Text(progressDetail)
              .font(.system(size: 9.5))
              .foregroundStyle(Studio.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          VStack(spacing: 0) {
            uploadStep("Create signed Release archive", phase: .archiving)
            uploadStep("Verify bundle, version, build, and team", phase: .inspecting)
            uploadStep("Upload archive and symbols", phase: .uploading)
            uploadStep("Wait for App Store processing", phase: .processing, isLast: true)
          }
          .background(Studio.backdrop.opacity(0.7))
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

          Button {
            model.evidenceWorkspaceTab = .terminal
            model.isEvidenceWorkspaceOpen = true
            dismiss()
          } label: {
            Label("View live xcodebuild output", systemImage: "terminal")
          }
          .buttonStyle(.plain)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(Studio.accent)
        }
        .padding(24)
      }
      Divider().overlay(Studio.separator)
      HStack {
        if model.appStoreUploadPhase == .processing {
          Text("Apple processing continues safely if you close this window.")
            .font(.system(size: 9))
            .foregroundStyle(Studio.secondary)
        }
        Spacer()
        if model.appStoreUploadPhase == .processing {
          Button("Continue in Background") { dismiss() }
            .buttonStyle(.borderedProminent)
        }
        Button(model.appStoreUploadPhase == .processing ? "Stop Waiting" : "Cancel") {
          model.cancelAppStoreUpload()
        }
      }
      .padding(16)
    }
  }

  private var uploadResult: some View {
    VStack(spacing: 18) {
      Image(
        systemName: model.appStoreUploadPhase == .complete
          ? "checkmark.circle.fill" : "clock.fill"
      )
      .font(.system(size: 34, weight: .medium))
      .foregroundStyle(model.appStoreUploadPhase == .complete ? Studio.success : Studio.accent)
      Text(model.appStoreUploadPhase == .complete ? "Build ready" : "Upload accepted")
        .font(.system(size: 16, weight: .bold))
      Text(model.appStoreUploadStatus)
        .font(.system(size: 10))
        .foregroundStyle(Studio.secondary)
        .multilineTextAlignment(.center)
      if let inspection = model.appStoreUploadArchiveInspection {
        Text("\(inspection.bundleID) · \(inspection.marketingVersion) (\(inspection.buildNumber))")
          .font(.system(size: 9.5).monospaced())
          .textSelection(.enabled)
      }
      HStack {
        if let archiveURL = model.appStoreUploadArchiveURL {
          Button("Reveal Archive") {
            NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
          }
        }
        Button("Done") { dismiss() }
        if model.appStoreUploadPhase == .complete {
          Button("Send to Testers…") {
            onDistribute()
            dismiss()
          }
          .buttonStyle(.borderedProminent)
        }
      }
    }
    .padding(32)
  }

  private var uploadFailure: some View {
    VStack(spacing: 14) {
      Image(systemName: model.appStoreUploadPhase == .cancelled ? "xmark.circle" : "exclamationmark.triangle")
        .font(.system(size: 30, weight: .light))
        .foregroundStyle(model.appStoreUploadPhase == .cancelled ? Studio.secondary : Studio.warning)
      Text(model.appStoreUploadStatus.nonempty ?? "Upload unavailable")
        .font(.system(size: 14, weight: .bold))
      Text(model.appStoreUploadError ?? "The operation was cancelled before upload completed.")
        .font(.system(size: 10))
        .foregroundStyle(Studio.secondary)
        .multilineTextAlignment(.center)
        .textSelection(.enabled)
        .frame(maxWidth: 430)
      HStack {
        Button("Close") { dismiss() }
        Button {
          model.evidenceWorkspaceTab = .terminal
          model.isEvidenceWorkspaceOpen = true
          dismiss()
        } label: {
          Label("View Build Log", systemImage: "terminal")
        }
        Button(model.appStoreUploadPreflight == nil ? "Run Preflight" : "Try Again") {
          if model.appStoreUploadPreflight == nil {
            Task { await model.prepareAppStoreUpload() }
          } else {
            model.startAppStoreUpload()
          }
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(32)
  }

  private func uploadReviewRow(
    _ label: String, _ value: String, monospaced: Bool = false, isLast: Bool = false
  ) -> some View {
    VStack(spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: 16) {
        Text(label)
          .font(.system(size: 9.5))
          .foregroundStyle(Studio.secondary)
          .frame(width: 132, alignment: .leading)
        Text(value)
          .font(monospaced ? .system(size: 9.5).monospaced() : .system(size: 9.5, weight: .medium))
          .lineLimit(label == "Source" ? 2 : 1)
          .truncationMode(.middle)
          .textSelection(.enabled)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14)
      .frame(minHeight: 38)
      if !isLast { Divider().overlay(Studio.separator).padding(.leading, 14) }
    }
  }

  private func uploadStep(
    _ title: String, phase: AppStoreUploadPhase, isLast: Bool = false
  ) -> some View {
    let state = stepState(for: phase)
    return VStack(spacing: 0) {
      HStack(spacing: 10) {
        Group {
          switch state {
          case .complete:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Studio.success)
          case .active:
            ProgressView().controlSize(.mini)
          case .waiting:
            Image(systemName: "circle").foregroundStyle(Studio.tertiary)
          }
        }
        .frame(width: 18)
        Text(title)
          .font(.system(size: 10, weight: state == .active ? .semibold : .regular))
        Spacer()
      }
      .padding(.horizontal, 14)
      .frame(height: 42)
      if !isLast { Divider().overlay(Studio.separator).padding(.leading, 42) }
    }
  }

  private enum UploadStepState { case waiting, active, complete }

  private func stepState(for step: AppStoreUploadPhase) -> UploadStepState {
    let order: [AppStoreUploadPhase] = [.archiving, .inspecting, .uploading, .processing]
    guard let current = order.firstIndex(of: model.appStoreUploadPhase),
      let target = order.firstIndex(of: step)
    else { return model.appStoreUploadPhase == .complete ? .complete : .waiting }
    if target < current { return .complete }
    if target == current { return .active }
    return .waiting
  }

  private var progressDetail: String {
    switch model.appStoreUploadPhase {
    case .archiving:
      "Xcode is resolving the Release build and creating a signed .xcarchive."
    case .inspecting:
      "Lys is checking the archive against the app identity you approved."
    case .uploading:
      "Xcode is exporting for App Store Connect and transferring the binary to Apple."
    case .processing:
      "The upload succeeded. Apple must process it before TestFlight can use it."
    default: ""
    }
  }
}

private struct AppStoreAppPicker: View {
  @EnvironmentObject var model: AppModel
  @State private var isPresented = false
  @State private var search = ""

  private var filteredApps: [AppStoreApp] {
    guard let query = search.nonempty?.lowercased() else { return model.appStoreApps }
    return model.appStoreApps.filter {
      $0.name.lowercased().contains(query) || $0.bundleID.lowercased().contains(query)
    }
  }

  var body: some View {
    Button { isPresented.toggle() } label: {
      HStack(spacing: 9) {
        Image(systemName: model.selectedAppStoreApp == nil ? "app.dashed" : "app.badge.checkmark")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Studio.accent)
          .frame(width: 28, height: 28)
          .background(Studio.accentSoft)
          .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        VStack(alignment: .leading, spacing: 2) {
          Text(model.selectedAppStoreApp?.name ?? "Choose an app")
            .font(.system(size: 10.5, weight: .semibold))
            .lineLimit(1)
          Text(model.selectedAppStoreApp?.bundleID ?? "Search accessible apps")
            .font(.system(size: 8.5).monospaced())
            .foregroundStyle(Studio.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 5)
        Image(systemName: "chevron.up.chevron.down")
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(Studio.tertiary)
      }
      .padding(.horizontal, 9)
      .frame(height: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(Studio.surface)
    .overlay {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .stroke(Studio.separator, lineWidth: 1)
    }
    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    .popover(isPresented: $isPresented, arrowEdge: .trailing) {
      VStack(spacing: 0) {
        HStack(spacing: 9) {
          Image(systemName: "magnifyingglass").foregroundStyle(Studio.secondary)
          TextField("Search apps…", text: $search)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        Divider().overlay(Studio.separator)
        ScrollView {
          LazyVStack(spacing: 4) {
            ForEach(filteredApps) { app in
              let matchesProject = model.appStoreDistributionTarget.map {
                $0.bundleID == app.bundleID
              }
              Button {
                _ = model.selectAppStoreApp(app.id)
                isPresented = false
              } label: {
                HStack(spacing: 12) {
                  Image(systemName: "app")
                    .font(.system(size: 13))
                    .foregroundStyle(Studio.secondary)
                    .frame(width: 28, height: 28)
                  VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(app.bundleID)
                      .font(.system(size: 9.5).monospaced())
                      .foregroundStyle(Studio.secondary)
                      .lineLimit(1)
                  }
                  Spacer()
                  if matchesProject == true {
                    Text("Project")
                      .font(.system(size: 8.5, weight: .semibold))
                      .foregroundStyle(Studio.accent)
                  } else if matchesProject == false {
                    Image(systemName: "exclamationmark.triangle")
                      .font(.system(size: 10))
                      .foregroundStyle(Studio.warning)
                  }
                  if model.selectedAppStoreApp?.id == app.id {
                    Image(systemName: "checkmark")
                      .font(.system(size: 11, weight: .bold))
                      .foregroundStyle(Studio.accent)
                  }
                }
                .padding(.horizontal, 12)
                .frame(height: 54)
                .background(model.selectedAppStoreApp?.id == app.id ? Studio.accentSoft : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
          .padding(10)
        }
        if let target = model.appStoreDistributionTarget {
          Divider().overlay(Studio.separator)
          Label("Locked to Release bundle ID \(target.bundleID)", systemImage: "lock.shield")
            .font(.system(size: 9.5))
            .foregroundStyle(Studio.secondary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        }
      }
      .frame(width: 370, height: 360)
    }
  }
}

private struct AppStoreTesterEditorSheet: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  let groupID: String
  @State private var email = ""
  @State private var firstName = ""
  @State private var lastName = ""
  @State private var pendingRemoval: AppStoreBetaTester?

  private var group: AppStoreBetaGroup? {
    model.appStoreBetaGroups.first { $0.id == groupID }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(group?.name ?? "TestFlight Testers").font(.system(size: 17, weight: .bold))
          Text("Email identities are fixed by Apple. Add or remove group membership here.")
            .font(.system(size: 10)).foregroundStyle(Studio.secondary)
        }
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      .padding(20)
      Divider().overlay(Studio.separator)

      VStack(alignment: .leading, spacing: 10) {
        Text("Add tester").font(.system(size: 11, weight: .semibold))
        TextField("Email", text: $email).textFieldStyle(.roundedBorder)
        HStack {
          TextField("First name (optional)", text: $firstName).textFieldStyle(.roundedBorder)
          TextField("Last name (optional)", text: $lastName).textFieldStyle(.roundedBorder)
          Button("Add") {
            Task {
              if await model.addAppStoreBetaTester(
                email: email, firstName: firstName, lastName: lastName, groupID: groupID)
              {
                email = ""
                firstName = ""
                lastName = ""
              }
            }
          }
          .disabled(email.nonempty == nil || model.isAppStoreMutationInProgress)
        }
        if let error = model.appStoreMutationError {
          Label(error, systemImage: "exclamationmark.triangle")
            .font(.system(size: 9.5)).foregroundStyle(Studio.warning)
        }
      }
      .padding(20)
      Divider().overlay(Studio.separator)

      if group?.testers.isEmpty != false {
        DeployEmptyState(
          symbol: "person.badge.plus", title: "No individual testers",
          detail: "Add an email above to enroll a tester in this group.")
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(group?.testers ?? []) { tester in
              HStack(spacing: 12) {
                Image(systemName: "person.crop.circle").foregroundStyle(Studio.secondary)
                VStack(alignment: .leading, spacing: 2) {
                  Text(tester.email).font(.system(size: 11, weight: .medium)).textSelection(.enabled)
                  Text(tester.name ?? "No name provided")
                    .font(.system(size: 9.5)).foregroundStyle(Studio.secondary)
                }
                Spacer()
                Button(role: .destructive) { pendingRemoval = tester } label: {
                  Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove from this group")
              }
              .padding(.horizontal, 20)
              .frame(minHeight: 52)
              Divider().overlay(Studio.separator)
            }
          }
        }
      }
    }
    .frame(width: 560, height: 560)
    .background(Studio.backdrop)
    .alert(item: $pendingRemoval) { tester in
      Alert(
        title: Text("Remove tester from group?"),
        message: Text("\(tester.email) will lose access through \(group?.name ?? "this group")."),
        primaryButton: .destructive(Text("Remove")) {
          Task { await model.removeAppStoreBetaTester(tester.id, fromGroup: groupID) }
        },
        secondaryButton: .cancel())
    }
  }
}

private struct DeploySurface<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Studio.surface)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(Studio.separator, lineWidth: 1)
      }
  }
}

private struct AppStoreConnectionSheet: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var label = "App Store Connect"
  @State private var keyID = ""
  @State private var issuerID = ""
  @State private var teamID = ""
  @State private var editedTeamID = ""
  @State private var isEditingTeamID = false
  @State private var privateKeyURL: URL?
  @State private var showsReplacementForm = false

  private var isWorking: Bool {
    model.appStoreConnectionPhase == .connecting
      || model.appStoreConnectionPhase == .refreshing
      || model.isAppStoreSigningMetadataLoading
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 11) {
        Image(systemName: "lock.shield.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Studio.accent)
          .frame(width: 32, height: 32)
          .background(Studio.accentSoft)
          .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        VStack(alignment: .leading, spacing: 3) {
          Text("App Store Connect")
            .font(.system(size: 15, weight: .semibold))
          Text("Secure access for app data, signing, and deployment.")
            .font(.system(size: 10.5))
            .foregroundStyle(Studio.secondary)
        }
        Spacer()
        Button { dismiss() } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 16))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Studio.secondary)
        }
        .buttonStyle(.plain)
        .help("Close")
        .accessibilityLabel("Close")
          .keyboardShortcut(.cancelAction)
          .disabled(isWorking)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 16)

      Divider().overlay(Studio.separator)

      if let connection = model.appStoreConnection, !showsReplacementForm {
        currentConnection(connection)
      } else {
        connectionForm
      }
    }
    .frame(width: 456)
    .background(Studio.surface)
    .interactiveDismissDisabled(isWorking)
  }

  private func currentConnection(_ connection: AppStoreConnection) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .center, spacing: 11) {
        Image(systemName: model.appStoreConnectionPhase == .connected
          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
          .font(.system(size: 17))
          .foregroundStyle(
            model.appStoreConnectionPhase == .connected ? Studio.success : Studio.warning)
        VStack(alignment: .leading, spacing: 4) {
          Text(model.appStoreConnectionPhase == .connected ? "Connected" : "Connection needs attention")
            .font(.system(size: 12, weight: .semibold))
          Text(model.appStoreConnectionPhase == .connected
            ? "Apple returned \(model.appStoreApps.count) accessible app\(model.appStoreApps.count == 1 ? "" : "s")."
            : "The saved connection could not be validated.")
            .font(.system(size: 10.5))
            .foregroundStyle(Studio.secondary)
        }
      }

      VStack(spacing: 0) {
        connectionValue("Name", connection.label)
        Divider().overlay(Studio.separator)
        connectionValue("Key type", "Team API key")
        Divider().overlay(Studio.separator)
        connectionValue("Key ID", connection.keyID, monospaced: true)
        Divider().overlay(Studio.separator)
        connectionValue("Issuer ID", connection.issuerID ?? "Missing", monospaced: true)
        Divider().overlay(Studio.separator)
        teamIDValue(connection)
        Divider().overlay(Studio.separator)
        connectionValue(
          "Accessible apps", "\(model.appStoreApps.count)")
        Divider().overlay(Studio.separator)
        connectionValue("Private key", "Stored in Keychain")
        if let lastSync = model.appStoreLastSyncedAt {
          Divider().overlay(Studio.separator)
          connectionValue(
            "Last synced",
            lastSync.formatted(date: .abbreviated, time: .shortened))
        }
      }
      .background(Studio.raised)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

      if let message = model.appStoreSigningMetadataMessage, !message.isEmpty {
        Label(message, systemImage: "checkmark.circle.fill")
          .font(.system(size: 10.5))
          .foregroundStyle(Studio.success)
      }
      errorMessage

      HStack {
        Button("Disconnect", role: .destructive) {
          Task {
            await model.disconnectAppStore()
            if model.appStoreConnection == nil { dismiss() }
          }
        }
        .disabled(isWorking)
        Spacer()
        Button("Replace Key…") { showsReplacementForm = true }
          .disabled(isWorking)
        Button {
          Task { await model.refreshAppStoreConnection() }
        } label: {
          if model.appStoreConnectionPhase == .refreshing {
            ProgressView().controlSize(.small)
          } else {
            Text("Sync Apps")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isWorking)
      }
    }
    .padding(18)
  }

  private var connectionForm: some View {
    VStack(alignment: .leading, spacing: 15) {
      VStack(alignment: .leading, spacing: 5) {
        Text("Team API key").font(.system(size: 12, weight: .semibold))
        Text("Enter a least-privileged team key from Users and Access → Integrations.")
          .font(.system(size: 10.5))
          .foregroundStyle(Studio.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 11) {
        GridRow {
          formLabel("Name")
          TextField("App Store Connect", text: $label)
            .textFieldStyle(.roundedBorder)
        }
        GridRow {
          formLabel("Key ID")
          TextField("ABC123DEFG", text: $keyID)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11).monospaced())
        }
        GridRow {
          formLabel("Issuer ID")
          TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $issuerID)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11).monospaced())
        }
        GridRow {
          formLabel("Team ID")
          TextField("Optional · ABC123DEFG", text: $teamID)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11).monospaced())
            .textCase(.uppercase)
        }
        GridRow(alignment: .center) {
          formLabel("Private key")
          HStack(spacing: 7) {
            Image(systemName: privateKeyURL == nil ? "doc.badge.key" : "checkmark.circle.fill")
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(privateKeyURL == nil ? Studio.tertiary : Studio.success)
            Text(privateKeyURL?.lastPathComponent ?? "No .p8 file selected")
              .font(.system(size: 10.5, weight: privateKeyURL == nil ? .regular : .medium))
              .foregroundStyle(privateKeyURL == nil ? Studio.secondary : Color.primary)
              .lineLimit(1)
              .truncationMode(.middle)
            Spacer(minLength: 6)
            Button("Choose…", action: choosePrivateKey)
              .controlSize(.small)
          }
          .padding(.leading, 8)
          .padding(.trailing, 4)
          .frame(height: 30)
          .background(Color(nsColor: .controlBackgroundColor))
          .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
          }
        }
      }

      HStack(spacing: 6) {
        Image(systemName: "lock.fill")
          .font(.system(size: 8.5, weight: .semibold))
        Text("The private key is validated before it is saved to this Mac's Keychain.")
      }
      .font(.system(size: 9.5))
      .foregroundStyle(Studio.secondary)
      .padding(.leading, 88)

      errorMessage

      HStack {
        Link(
          "Create API Key ↗",
          destination: URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!)
          .font(.system(size: 10.5))
        Spacer()
        Button("Cancel") {
          if model.appStoreConnection != nil {
            showsReplacementForm = false
          } else {
            dismiss()
          }
        }
        .keyboardShortcut(.cancelAction)
        .disabled(isWorking)
        Button {
          guard let privateKeyURL else { return }
          Task {
            if await model.connectAppStore(
              label: label, keyID: keyID, issuerID: issuerID, teamID: teamID,
              privateKeyURL: privateKeyURL)
            {
              dismiss()
            }
          }
        } label: {
          if model.appStoreConnectionPhase == .connecting {
            ProgressView().controlSize(.small)
          } else {
            Text("Connect")
          }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(
          isWorking || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || issuerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || privateKeyURL == nil)
      }
      .padding(.top, 2)
    }
    .padding(18)
  }

  private func formLabel(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 10.5, weight: .medium))
      .foregroundStyle(Studio.secondary)
      .frame(width: 76, alignment: .trailing)
  }

  @ViewBuilder private var errorMessage: some View {
    if let error = model.appStoreConnectionError, !error.isEmpty {
      Label(error, systemImage: "exclamationmark.triangle.fill")
        .font(.system(size: 10.5))
        .foregroundStyle(Studio.warning)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("App Store Connect error: \(error)")
    }
  }

  private func connectionValue(_ label: String, _ value: String, monospaced: Bool = false)
    -> some View
  {
    HStack(spacing: 12) {
      Text(label)
        .font(.system(size: 10))
        .foregroundStyle(Studio.secondary)
        .frame(width: 74, alignment: .leading)
      Text(value)
        .font(monospaced ? .system(size: 10, weight: .medium).monospaced() : .system(size: 10, weight: .medium))
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 38)
  }

  private func teamIDValue(_ connection: AppStoreConnection) -> some View {
    HStack(spacing: 8) {
      Text("Team ID")
        .font(.system(size: 10))
        .foregroundStyle(Studio.secondary)
        .frame(width: 74, alignment: .leading)
      if isEditingTeamID {
        TextField("ABC123DEFG", text: $editedTeamID)
          .textFieldStyle(.roundedBorder)
          .font(.system(size: 10, weight: .medium).monospaced())
          .textCase(.uppercase)
          .frame(maxWidth: 150)
        Button("Cancel") { isEditingTeamID = false }
          .controlSize(.small)
        Button("Save") {
          Task {
            if await model.saveAppStoreTeamID(editedTeamID) {
              isEditingTeamID = false
            }
          }
        }
        .controlSize(.small)
        .buttonStyle(.borderedProminent)
        .disabled(
          AppStoreDistributionSupport.normalizedTeamID(editedTeamID) == nil
            || model.isAppStoreSigningMetadataLoading)
      } else {
        Text(connection.teamID ?? "Not set")
          .font(.system(size: 10, weight: .medium).monospaced())
          .foregroundStyle(connection.teamID == nil ? Studio.secondary : Color.primary)
          .lineLimit(1)
        Spacer(minLength: 4)
        Button("Edit") {
          editedTeamID = connection.teamID ?? ""
          isEditingTeamID = true
        }
        .controlSize(.small)
        Button {
          Task { _ = await model.discoverAppStoreTeamID() }
        } label: {
          if model.isAppStoreSigningMetadataLoading {
            ProgressView().controlSize(.small)
          } else {
            Label("Discover", systemImage: "arrow.triangle.2.circlepath")
          }
        }
        .controlSize(.small)
        .help("Discover the Team ID from Apple distribution-certificate metadata")
        .disabled(isWorking)
      }
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 42)
  }

  private func choosePrivateKey() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [UTType(filenameExtension: "p8") ?? .data]
    panel.prompt = "Choose Private Key"
    guard panel.runModal() == .OK else { return }
    privateKeyURL = panel.url
  }
}

public struct AppStoreConnectionSnapshotView: View {
  public init() {}

  public var body: some View {
    AppStoreConnectionSheet()
  }
}

private struct DeployEmptyState: View {
  let symbol: String
  let title: String
  let detail: String
  let actionTitle: String?
  let action: (() -> Void)?

  init(
    symbol: String, title: String, detail: String, actionTitle: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.symbol = symbol
    self.title = title
    self.detail = detail
    self.actionTitle = actionTitle
    self.action = action
  }

  var body: some View {
    VStack(spacing: 9) {
      Image(systemName: symbol)
        .font(.system(size: 24, weight: .light))
        .foregroundStyle(Studio.tertiary)
      Text(title)
        .font(.system(size: 12, weight: .semibold))
      Text(detail)
        .font(.system(size: 10.5))
        .foregroundStyle(Studio.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 230)
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .padding(.top, 3)
      }
    }
    .padding(22)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct DeployInfoRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(label)
        .font(.system(size: 10.5))
        .foregroundStyle(Studio.secondary)
        .frame(width: 76, alignment: .leading)
      Text(value)
        .font(.system(size: 10.5, weight: .medium))
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .frame(minHeight: 34)
  }
}

private struct WorkspaceHeader: View {
  let symbol: String
  let title: String
  let detail: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(Studio.accent)
        .frame(width: 32, height: 32)
        .background(Studio.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 18, weight: .bold))
        Text(detail)
          .font(.system(size: 11))
          .foregroundStyle(Studio.secondary)
          .lineLimit(1)
      }
    }
  }
}

private struct CodeWorkspace: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 16) {
        WorkspaceHeader(
          symbol: "chevron.left.forwardslash.chevron.right",
          title: "Code",
          detail: model.repository?.lastPathComponent ?? "Inspect source inside the current workspace"
        )
        Spacer(minLength: 0)
        StatusBadge(
          title: model.activeWorktree == nil ? "Read only" : "Task worktree",
          state: model.activeWorktree == nil ? .neutral : .active
        )
        Button {
          model.saveFile()
        } label: {
          Label("Save", systemImage: "checkmark")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(model.selectedFile == nil || model.activeWorktree == nil)
        .help("Save this file to the isolated task worktree")
      }
      .padding(.horizontal, 24)
      .frame(height: 72)
      .background(Studio.surface)
      Divider().overlay(Studio.separator)

      HStack(spacing: 0) {
        FileBrowser().frame(width: 286)
        Divider().overlay(Studio.separator)
        VStack(spacing: 0) {
          HStack(spacing: 9) {
            Image(systemName: model.selectedFile == nil ? "doc" : "doc.text")
              .foregroundStyle(Studio.secondary)
            Text(model.selectedFile?.lastPathComponent ?? "No file selected")
              .font(.system(size: 11.5, weight: .semibold))
              .lineLimit(1)
            Spacer()
            if model.selectedFile != nil {
              Text("\(lineCount) lines")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Studio.tertiary)
            }
          }
          .padding(.horizontal, 18)
          .frame(height: 44)
          .background(Studio.surface)
          Divider().overlay(Studio.separator)
          if model.selectedFile == nil {
            WorkspaceEmpty(
              symbol: "doc.text.magnifyingglass",
              title: "Select a source file",
              detail: "Choose a file from the browser to inspect it with line numbers, find, and syntax color."
            )
          } else {
            CodeEditor(
              text: $model.source, fileURL: model.selectedFile,
              readOnly: model.activeWorktree == nil)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .clipped()
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(Studio.backdrop)
  }

  private var lineCount: Int {
    max(1, model.source.split(separator: "\n", omittingEmptySubsequences: false).count)
  }
}

private struct FileBrowser: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(model.activeWorktree == nil ? "Repository" : "Task Files")
            .font(.system(size: 12, weight: .semibold))
          if !model.files.isEmpty {
            Text("\(model.files.count) top-level items")
              .font(.system(size: 9.5))
              .foregroundStyle(Studio.tertiary)
          }
        }
        Spacer(minLength: 0)
        Button(action: model.chooseRepository) {
          Image(systemName: "folder.badge.plus")
            .font(.system(size: 13, weight: .medium))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Studio.accent)
        .help("Open a repository")
      }
      .padding(.horizontal, 16)
      .frame(height: 52)
      .background(Studio.surface)
      Divider().overlay(Studio.separator)
      if model.files.isEmpty {
        WorkspaceEmpty(
          symbol: "folder", title: "No files", detail: "Open a repository to browse files.",
          actionTitle: "Open Repository…", action: model.chooseRepository)
      } else {
        ScrollView {
          LazyVStack(spacing: 1) {
            ForEach(model.files) { node in
              FileTreeNodeRow(node: node, depth: 0)
            }
          }
          .padding(10)
        }
      }
    }
    .background(Studio.surface)
  }
}

private struct FileTreeNodeRow: View {
  @EnvironmentObject var model: AppModel
  let node: FileNode
  let depth: Int

  @State private var isExpanded = false
  @State private var isLoading = false
  @State private var children: [FileNode]?
  @State private var loadError: String?
  @State private var loadAttempt = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Button(action: activate) {
        HStack(spacing: 7) {
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .foregroundStyle(Studio.tertiary)
            .frame(width: 11, height: 18)
            .opacity(node.isDirectory ? 1 : 0)

          Image(systemName: node.isDirectory ? folderSymbol : fileSymbol(node.name))
            .foregroundStyle(node.isDirectory ? Studio.accent : Studio.secondary)
            .frame(width: 16)

          Text(node.name)
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
        .padding(.leading, CGFloat(depth) * 16 + 8)
        .padding(.trailing, 8)
        .frame(height: 30)
        .background(isSelected ? Studio.accentSoft : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(node.name)
      .accessibilityValue(
        node.isDirectory ? (isExpanded ? "Expanded folder" : "Collapsed folder") : "File")
      .help(node.url.path)

      if isExpanded {
        if isLoading {
          HStack(spacing: 7) {
            ProgressView().controlSize(.mini)
            Text("Loading…")
          }
          .font(.system(size: 10))
          .foregroundStyle(Studio.secondary)
          .padding(.leading, CGFloat(depth + 1) * 16 + 26)
          .frame(height: 28)
        } else if let loadError {
          Button {
            children = nil
            self.loadError = nil
            loadAttempt += 1
          } label: {
            Label("Couldn’t open folder · Retry", systemImage: "exclamationmark.triangle")
              .font(.system(size: 10))
              .foregroundStyle(Studio.warning)
              .lineLimit(1)
              .padding(.leading, CGFloat(depth + 1) * 16 + 10)
              .frame(height: 28)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help(loadError)
        } else if let children, children.isEmpty {
          Text("Empty folder")
            .font(.system(size: 10))
            .foregroundStyle(Studio.tertiary)
            .padding(.leading, CGFloat(depth + 1) * 16 + 26)
            .frame(height: 28)
        } else if let children {
          ForEach(children) { child in
            FileTreeNodeRow(node: child, depth: depth + 1)
          }
        }
      }
    }
    .task(id: "\(isExpanded)-\(loadAttempt)") {
      guard isExpanded, node.isDirectory, children == nil else { return }
      isLoading = true
      loadError = nil
      let result = await Task.detached(priority: .userInitiated) {
        FileTreeLoader.loadContents(of: node.url)
      }.value
      guard !Task.isCancelled else { return }
      isLoading = false
      switch result {
      case .success(let loadedChildren):
        children = loadedChildren
      case .failure(let message):
        loadError = message
      }
    }
  }

  private var isSelected: Bool {
    !node.isDirectory && model.selectedFile == node.url
  }

  private var folderSymbol: String {
    isExpanded ? "folder.fill" : "folder"
  }

  private func activate() {
    if node.isDirectory {
      isExpanded.toggle()
    } else {
      model.selectFile(node.url)
    }
  }

  private func fileSymbol(_ name: String) -> String {
    if name.hasSuffix(".swift") { return "swift" }
    if name.hasSuffix(".json") { return "curlybraces" }
    return "doc"
  }
}

private struct GitWorkspace: View {
  @EnvironmentObject var model: AppModel
  @State private var selectedPath: String?
  @State private var selectedDiff: ProposedFileDiff?
  @State private var isLoadingDiff = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 16) {
        WorkspaceHeader(
          symbol: "arrow.triangle.branch",
          title: "Changes",
          detail: model.activeWorktree == nil
            ? "Review uncommitted files in the repository checkout"
            : "Review the isolated task against its exact baseline"
        )
        Spacer(minLength: 0)
        StatusBadge(
          title: scopeBadgeTitle,
          state: scopeBadgeState
        )
        Button {
          if model.activeWorktree == nil {
            Task { await model.refreshRepositoryChanges() }
          } else {
            model.reviewChanges()
          }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(
          model.activeWorktree == nil
            ? "Refresh the repository working-tree status"
            : "Refresh the baseline-relative change set")
      }
      .padding(.horizontal, 24)
      .frame(height: 72)
      .background(Studio.surface)
      Divider().overlay(Studio.separator)

      HStack(spacing: 0) {
        changeMetric("Changed", count: modifiedCount, color: Studio.accent)
        changeMetricSeparator
        changeMetric("Added", count: addedCount, color: Studio.success)
        changeMetricSeparator
        changeMetric("Deleted", count: deletedCount, color: .red)
        Spacer()
        HStack(spacing: 7) {
          Image(systemName: model.activeWorktree == nil ? "arrow.triangle.branch" : "checkmark.seal")
          Text(
            model.activeWorktree == nil
              ? "Working tree compared with HEAD" : "Showing only task-scoped changes")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(Studio.secondary)
        .padding(.trailing, 24)
      }
      .padding(.leading, 24)
      .frame(height: 58)
      .background(Studio.surface)
      Divider().overlay(Studio.separator)

      if model.visibleChanges.isEmpty {
        WorkspaceEmpty(
          symbol: "arrow.triangle.branch",
          title: model.activeWorktree == nil ? "No uncommitted changes" : "No proposed changes",
          detail: model.activeWorktree == nil
            ? "The repository checkout currently matches HEAD."
            : "The active task currently matches its baseline.")
      } else {
        HStack(spacing: 0) {
          changeFileList
            .frame(width: 310)
          Divider().overlay(Studio.separator)
          changeDetail
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Studio.surface)
        .clipShape(RoundedRectangle(cornerRadius: Studio.panelRadius, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: Studio.panelRadius, style: .continuous)
            .stroke(Studio.separator, lineWidth: 1)
        }
        .padding(20)
      }
    }
    .background(Studio.backdrop)
    .task(id: diffTaskID) {
      await loadSelectedDiff()
    }
    .onChange(of: changes.map(\.path)) { _, paths in
      if let selectedPath, !paths.contains(selectedPath) {
        self.selectedPath = nil
      }
      selectedDiff = nil
    }
  }

  private func changeMetric(_ title: String, count: Int, color: Color) -> some View {
    HStack(spacing: 8) {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Studio.secondary)
      Text("\(count)").font(.system(size: 12, weight: .semibold).monospacedDigit())
    }
    .padding(.horizontal, 16)
  }

  private var changeMetricSeparator: some View {
    Rectangle()
      .fill(Studio.separator)
      .frame(width: 1, height: 30)
      .padding(.horizontal, 8)
  }

  private var changes: [ProposedChange] { model.visibleChanges }

  private var addedCount: Int { changes.filter { $0.kind == .added }.count }
  private var modifiedCount: Int { changes.filter { $0.kind == .modified }.count }
  private var deletedCount: Int { changes.filter { $0.kind == .deleted }.count }

  private var selectedChange: ProposedChange? {
    if let selectedPath {
      return changes.first { $0.path == selectedPath }
    }
    return changes.first
  }

  private var diffTaskID: String {
    let files = changes.map {
      "\($0.path):\($0.kind.rawValue):\($0.binary)"
    }.joined(separator: "|")
    let revision = model.activeWorktree == nil
      ? model.repositoryChangesRevision : model.proposedChangesRevision
    return "\(revision)::\(model.generation)::\(selectedChange?.path ?? "none")::\(files)"
  }

  private var scopeBadgeTitle: String {
    if model.activeWorktree != nil { return "Task worktree" }
    if model.repository == nil { return "No project" }
    if !model.isGitRepository { return "Read-only folder" }
    return model.repositoryChanges.isEmpty ? "Clean checkout" : "Uncommitted work"
  }

  private var scopeBadgeState: StatusBadge.State {
    if model.activeWorktree != nil { return .active }
    return model.repositoryChanges.isEmpty ? .neutral : .warning
  }

  private var changeFileList: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Changed files")
          .font(.system(size: 11, weight: .semibold))
        Spacer()
        Text("\(changes.count)")
          .font(.system(size: 10, weight: .semibold).monospacedDigit())
          .foregroundStyle(Studio.secondary)
      }
      .padding(.horizontal, 16)
      .frame(height: 44)
      Divider().overlay(Studio.separator)

      ScrollView {
        LazyVStack(spacing: 3) {
          ForEach(changes) { change in
            Button {
              selectedPath = change.path
            } label: {
              ChangeFileRow(
                change: change, selected: selectedChange?.path == change.path)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(change.kind.rawValue) \(change.path)")
            .accessibilityValue(change.binary ? "Binary file" : "Text file")
          }

          if !model.applyConflicts.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
              Label("Apply needs review", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Studio.warning)
              ForEach(model.applyConflicts) { conflict in
                VStack(alignment: .leading, spacing: 3) {
                  Text(conflict.path)
                    .font(.system(size: 10, weight: .semibold).monospaced())
                  Text(conflict.reason)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Studio.secondary)
                    .lineLimit(3)
                }
                if let artifact = conflict.resolutionArtifact {
                  Text(artifact)
                    .font(.system(size: 9).monospaced())
                    .foregroundStyle(Studio.secondary)
                    .textSelection(.enabled)
                }
              }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(.top, 8)
          }
        }
        .padding(8)
      }
    }
    .background(Studio.surface)
  }

  @ViewBuilder
  private var changeDetail: some View {
    if let change = selectedChange {
      VStack(spacing: 0) {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 5) {
            Text(change.path)
              .font(.system(size: 12, weight: .semibold).monospaced())
              .lineLimit(1)
              .truncationMode(.middle)
            HStack(spacing: 10) {
              DiffKindBadge(kind: change.kind)
              if change.binary || selectedDiff?.binary == true {
                Text("Binary")
                  .font(.system(size: 9.5, weight: .medium))
                  .foregroundStyle(Studio.warning)
              } else if let selectedDiff {
                Text("+\(selectedDiff.addedLineCount)")
                  .foregroundStyle(Studio.success)
                Text("−\(selectedDiff.removedLineCount)")
                  .foregroundStyle(.red)
              } else {
                Text(model.activeWorktree == nil ? "HEAD → working tree" : "Baseline → task")
                  .foregroundStyle(Studio.secondary)
              }
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
          }
          Spacer(minLength: 0)
          Text(model.activeWorktree == nil ? "HEAD diff" : "Task diff")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Studio.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        Divider().overlay(Studio.separator)

        if isLoadingDiff {
          VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(
              model.activeWorktree == nil
                ? "Reading HEAD and working-tree file…" : "Reading baseline and task file…")
              .font(.system(size: 10.5))
              .foregroundStyle(Studio.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let selectedDiff {
          if let message = selectedDiff.message, selectedDiff.lines.isEmpty {
            VStack(spacing: 10) {
              Image(systemName: selectedDiff.binary ? "shippingbox" : "doc.text.magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Studio.tertiary)
              Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Studio.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            diffLines(selectedDiff)
          }
        } else {
          VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
              .font(.system(size: 26, weight: .light))
              .foregroundStyle(Studio.tertiary)
            Text("Diff unavailable")
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(Studio.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .background(Studio.surface)
    } else {
      WorkspaceEmpty(
        symbol: "doc.text.magnifyingglass", title: "Select a changed file",
        detail: model.activeWorktree == nil
          ? "Choose a file to compare the working tree with HEAD."
          : "Choose a file to compare the task worktree with its baseline.")
    }
  }

  private func diffLines(_ diff: ProposedFileDiff) -> some View {
    let language = SyntaxLanguage(fileURL: URL(fileURLWithPath: diff.path))
    return ScrollView([.vertical, .horizontal]) {
      LazyVStack(spacing: 0) {
        ForEach(diff.lines) { line in
          DiffLineRow(line: line, language: language)
        }
      }
      .padding(.vertical, 8)
    }
    .background(Studio.raised.opacity(0.42))
  }

  private func loadSelectedDiff() async {
    guard let change = selectedChange else {
      selectedDiff = nil
      isLoadingDiff = false
      return
    }
    isLoadingDiff = true
    let diff = model.activeWorktree == nil
      ? await model.repositoryDiff(for: change)
      : await model.proposedDiff(for: change)
    guard !Task.isCancelled else { return }
    selectedDiff = diff
    isLoadingDiff = false
  }
}

private struct ChangeFileRow: View {
  let change: ProposedChange
  let selected: Bool

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: change.binary ? "shippingbox" : "doc.text")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(proposedChangeColor(change.kind))
        .frame(width: 28, height: 28)
        .background(proposedChangeColor(change.kind).opacity(0.11))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

      VStack(alignment: .leading, spacing: 3) {
        Text(fileName)
          .font(.system(size: 11, weight: selected ? .semibold : .medium))
          .lineLimit(1)
          .truncationMode(.middle)
        Text(directory)
          .font(.system(size: 9.5, weight: .medium).monospaced())
          .foregroundStyle(Studio.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: 5)
      Text(change.kind.rawValue.capitalized)
        .font(.system(size: 8.5, weight: .bold).monospaced())
        .foregroundStyle(proposedChangeColor(change.kind))
    }
    .padding(.horizontal, 10)
    .frame(minHeight: 58)
    .background(selected ? Studio.accentSoft : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    .contentShape(Rectangle())
  }

  private var fileName: String { change.path.split(separator: "/").last.map(String.init) ?? change.path }

  private var directory: String {
    let components = change.path.split(separator: "/")
    guard components.count > 1 else { return "Project root" }
    return components.dropLast().joined(separator: "/")
  }
}

private struct DiffKindBadge: View {
  let kind: ProposedChangeKind

  var body: some View {
    HStack(spacing: 5) {
      Circle().fill(proposedChangeColor(kind)).frame(width: 6, height: 6)
      Text(kind.rawValue.capitalized)
    }
    .foregroundStyle(proposedChangeColor(kind))
  }
}

private struct DiffLineRow: View {
  let line: ProposedDiffLine
  let language: SyntaxLanguage

  var body: some View {
    HStack(spacing: 0) {
      Text(lineNumber)
        .frame(width: 42, alignment: .trailing)
        .foregroundStyle(Studio.tertiary)
      Text(prefix)
        .frame(width: 24)
        .foregroundStyle(prefixColor)
      SyntaxHighlightedText(text: line.text, language: language)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 420, alignment: .leading)
        .textSelection(.enabled)
    }
    .foregroundStyle(Studio.secondary)
    .padding(.horizontal, 10)
    .frame(minHeight: 23, alignment: .center)
    .background(rowColor)
    .overlay(alignment: .bottom) { Divider().overlay(Studio.separator.opacity(0.5)) }
  }

  private var lineNumber: String {
    String(line.newLineNumber ?? line.oldLineNumber ?? 0)
  }

  private var prefix: String {
    switch line.kind {
    case .context: " "
    case .added: "+"
    case .removed: "−"
    }
  }

  private var prefixColor: Color {
    switch line.kind {
    case .context: Studio.tertiary
    case .added: Studio.success
    case .removed: .red
    }
  }

  private var rowColor: Color {
    switch line.kind {
    case .context: .clear
    case .added: Studio.success.opacity(0.09)
    case .removed: Color.red.opacity(0.08)
    }
  }
}

private func proposedChangeColor(_ kind: ProposedChangeKind) -> Color {
  switch kind {
  case .added: Studio.success
  case .modified: Studio.accent
  case .deleted: .red
  }
}

private struct SettingsWorkspace: View {
  @EnvironmentObject var model: AppModel
  @State private var testSecretID = ""
  @State private var testSecretValue = ""
  @State private var showsTestSecretSetup = false
  @State private var showsAppStoreConnection = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 16) {
        WorkspaceHeader(
          symbol: "gearshape",
          title: "Settings",
          detail: "Toolchain, agent connections, compatibility, and recovery"
        )
        Spacer(minLength: 0)
        StatusBadge(title: "Local", state: .neutral)
      }
      .padding(.horizontal, 24)
      .frame(height: 72)
      .background(Studio.surface)
      Divider().overlay(Studio.separator)

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
        SettingsGroup(title: "App Store Connect") {
          SettingRow(
            symbol: model.appStoreConnectionPhase == .connected
              ? "checkmark.shield.fill" : "link.badge.plus",
            title: model.appStoreConnection?.label ?? "Connect Apple account",
            detail: appStoreConnectionDetail
          ) {
            Button(model.appStoreConnection == nil ? "Connect…" : "Manage…") {
              showsAppStoreConnection = true
            }
          }
        }
        SettingsGroup(title: "Apple toolchain") {
          SettingRow(
            symbol: "hammer",
            title: model.preflight?.isFullXcode == true
              ? "Full Xcode selected" : "Xcode setup required",
            detail: toolchainDetail
          ) {
            Button("Select Xcode…", action: model.chooseXcode)
          }
        }
        SettingsGroup(title: "Coding agents") {
          ForEach(model.adapters) { adapter in
            SettingRow(
              agentID: adapter.id, title: adapter.displayName,
              detail: adapterDetail(adapter)
            ) {
              Text(adapterStatus(adapter))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(adapterStatusColor(adapter))
            }
          }
        }
        SettingsGroup(title: "Compatibility gates") {
          SettingRow(
            symbol: SimulatorLiveSession.helperAvailable ? "iphone.gen3.radiowaves.left.and.right" : "video.slash",
            title: SimulatorLiveSession.helperAvailable
              ? "In-app Simulator ready" : "In-app Simulator setup required",
            detail: SimulatorLiveSession.helperAvailable
              ? "Continuous CoreSimulator framebuffer and low-latency HID input are available. Screenshots remain separate evidence artifacts."
              : "Install the pinned AXe helper to enable the continuous in-app framebuffer and direct touch input."
          ) {
            Text(SimulatorLiveSession.helperAvailable ? "Ready" : "Setup required")
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(
                SimulatorLiveSession.helperAvailable ? Studio.success : Studio.warning)
          }
          SettingRow(
            symbol: wdaSymbol, title: model.wdaStatus.title, detail: model.wdaStatus.detail
          ) {
            if model.wdaStatus.availability == .setupRequired,
              model.selectedDestination != nil
            {
              Button("Build Runner…", action: model.setupWebDriverAgent)
                .disabled(model.isBusy)
            } else {
              Text(wdaBadge)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(wdaColor)
            }
          }
        }
        SettingsGroup(title: "Authenticated testing") {
          SettingRow(
            symbol: "key.fill", title: "Test-session secrets",
            detail:
              "Store local credentials by ID. Values are kept in Keychain and are never exposed to agents or diagnostics."
          ) {
            Button(model.testSecretIDs.isEmpty ? "Set Authentication…" : "Add Authentication…") {
              showsTestSecretSetup = true
            }
            .popover(isPresented: $showsTestSecretSetup, arrowEdge: .trailing) {
              testAuthenticationPopover
            }
          }
          if !model.testSecretIDs.isEmpty {
            SettingRow(
              symbol: "checkmark.shield", title: "Available secret IDs",
              detail: model.testSecretIDs.joined(separator: " · ")
            ) {
              Text("\(model.testSecretIDs.count)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Studio.success)
            }
          }
        }
        SettingsGroup(title: "Crash recovery") {
          if model.recoverableWorkspaces.isEmpty {
            SettingRow(
              symbol: "checkmark.arrow.trianglehead.counterclockwise", title: "No pending tasks",
              detail:
                "Incomplete isolated worktrees are retained here after an app or runtime interruption."
            ) {
              Text("Clear").font(.system(size: 11, weight: .medium)).foregroundStyle(
                Studio.success)
            }
          } else {
            ForEach(model.recoverableWorkspaces) { recovered in
              SettingRow(
                symbol: "arrow.counterclockwise", title: recovered.worktree.lastPathComponent,
                detail:
                  "\(recovered.manifest.repositoryRoot) · \(recovered.manifest.createdAt.formatted(date: .abbreviated, time: .shortened))"
              ) {
                Button("Resume") { model.resume(recovered) }
              }
            }
          }
        }
        SettingsGroup(title: "Privacy") {
          SettingRow(
            symbol: "doc.zipper", title: "Redacted diagnostics",
            detail:
              "Export is explicit and removes registered secrets and repository-root paths. No telemetry is sent."
          ) { Button("Export…", action: model.exportDiagnostics) }
        }
      }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: 980, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .background(Studio.backdrop)
    .sheet(isPresented: $showsAppStoreConnection) {
      AppStoreConnectionSheet().environmentObject(model)
    }
  }
  private var appStoreConnectionDetail: String {
    switch model.appStoreConnectionPhase {
    case .connected:
      let sync = model.appStoreLastSyncedAt?.formatted(date: .abbreviated, time: .shortened)
        ?? "not synced"
      let team = model.appStoreConnection?.teamID.map { "Team \($0)" } ?? "Team ID not set"
      let key = model.appStoreConnection.map { "Key \($0.keyID)" } ?? ""
      return
        "Connected · \(team) · \(key) · \(model.appStoreApps.count) accessible "
        + "app\(model.appStoreApps.count == 1 ? "" : "s") · synced \(sync)"
    case .connecting: return "Validating the Team API key with Apple."
    case .refreshing: return "Refreshing accessible apps from Apple."
    case .failed: return model.appStoreConnectionError ?? "The connection needs attention."
    case .disconnected:
      return "Use a Team API key. The private key stays in this Mac's Keychain."
    }
  }

  private var testAuthenticationPopover: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Set Test Authentication")
          .font(.system(size: 14, weight: .semibold))
        Text("Save one credential value under the ID used by your test blueprint.")
          .font(.system(size: 9.5))
          .foregroundStyle(Studio.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Authentication ID")
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(Studio.secondary)
        TextField("Example: auth.primary.password", text: $testSecretID)
          .textFieldStyle(.roundedBorder)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Secret or password")
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(Studio.secondary)
        SecureField("Stored in Keychain", text: $testSecretValue)
          .textFieldStyle(.roundedBorder)
      }

      Label("The value is never shown to agents or included in diagnostics.", systemImage: "lock.fill")
        .font(.system(size: 9))
        .foregroundStyle(Studio.secondary)

      HStack {
        Button("Cancel") { showsTestSecretSetup = false }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Save Authentication") {
          model.saveTestSecret(id: testSecretID, value: testSecretValue)
          testSecretID = ""
          testSecretValue = ""
          showsTestSecretSetup = false
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(
          testSecretID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || testSecretValue.isEmpty)
      }
    }
    .padding(18)
    .frame(width: 330)
  }
  private var toolchainDetail: String {
    if let version = model.preflight?.xcodeVersion, let build = model.preflight?.xcodeBuild {
      return "Xcode \(version) · build \(build) · \(model.preflight?.developerDirectory ?? "")"
    }
    return model.preflight?.issues.first
      ?? "Select Xcode.app to enable build and Simulator discovery."
  }
  private func adapterDetail(_ adapter: DetectedAdapter) -> String {
    if let executable = adapter.executable { return "ACP v1 ready · \(executable.path)" }
    if let cli = adapter.cliExecutable {
      return "CLI detected at \(cli.path). \(adapter.limitation ?? "ACP adapter setup required.")"
    }
    return adapter.limitation ?? "Not installed"
  }
  private func adapterStatus(_ adapter: DetectedAdapter) -> String {
    switch adapter.availability {
    case .ready: "ACP ready"
    case .cliDetected: "CLI found"
    case .configurationOnly: "CLI missing"
    case .missing: "Not installed"
    }
  }
  private func adapterStatusColor(_ adapter: DetectedAdapter) -> Color {
    switch adapter.availability {
    case .ready: Studio.success
    case .cliDetected: Studio.accent
    case .configurationOnly: Studio.warning
    case .missing: Studio.secondary
    }
  }
  private var wdaSymbol: String {
    model.wdaStatus.availability == .ready ? "checkmark.shield" : "lock.shield"
  }
  private var wdaBadge: String {
    model.wdaStatus.availability == .ready ? "Ready" : "Blocked"
  }
  private var wdaColor: Color {
    model.wdaStatus.availability == .ready ? Studio.success : Studio.warning
  }
}

private struct SettingsGroup<Content: View>: View {
  let title: String
  @ViewBuilder var content: Content
  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Studio.secondary)
      VStack(spacing: 0) { content }
        .background(Studio.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.018), radius: 11, y: 4)
    }
  }
}

private struct SettingRow<Accessory: View>: View {
  let symbol: String?
  let agentID: String?
  let title: String
  let detail: String
  @ViewBuilder var accessory: Accessory
  init(symbol: String, title: String, detail: String, @ViewBuilder accessory: () -> Accessory) {
    self.symbol = symbol
    agentID = nil
    self.title = title
    self.detail = detail
    self.accessory = accessory()
  }
  init(agentID: String, title: String, detail: String, @ViewBuilder accessory: () -> Accessory) {
    symbol = nil
    self.agentID = agentID
    self.title = title
    self.detail = detail
    self.accessory = accessory()
  }
  var body: some View {
    HStack(spacing: 14) {
      Group {
        if let agentID {
          AgentMark(id: agentID)
        } else if let symbol {
          Image(systemName: symbol).font(.system(size: 17, weight: .regular))
        }
      }
      .foregroundStyle(Studio.accent)
      .frame(width: 32, height: 32)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: 12, weight: .semibold))
        Text(detail).font(.system(size: 10)).foregroundStyle(Studio.secondary).lineLimit(2)
      }
      Spacer()
      accessory
    }
    .padding(.horizontal, 16).frame(minHeight: 64)
  }
}

private struct AgentMark: View {
  let id: String
  var size: CGFloat = 22
  var body: some View {
    if let url = LysResourceBundle.ui.url(
      forResource: id, withExtension: "svg", subdirectory: "AgentIcons")
      ?? LysResourceBundle.ui.url(forResource: id, withExtension: "svg"),
      let image = NSImage(contentsOf: url)
    {
      Image(nsImage: image)
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    } else {
      Image(systemName: "sparkles").font(.system(size: 17, weight: .regular))
    }
  }
}

private struct WorkspaceEmpty: View {
  let symbol: String
  let title: String
  let detail: String
  let actionTitle: String?
  let action: (() -> Void)?

  init(
    symbol: String,
    title: String,
    detail: String,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.symbol = symbol
    self.title = title
    self.detail = detail
    self.actionTitle = actionTitle
    self.action = action
  }

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(
        Studio.tertiary)
      Text(title).font(.system(size: 16, weight: .semibold))
      Text(detail).font(.system(size: 11)).foregroundStyle(Studio.secondary).multilineTextAlignment(
        .center
      )
      .frame(maxWidth: 460)
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
  }
}

private struct StatusBadge: View {
  enum State { case active, neutral, warning }
  let title: String
  let state: State
  var body: some View {
    HStack(spacing: 6) {
      Circle().fill(color).frame(width: 6, height: 6)
      Text(title).lineLimit(1)
    }
    .font(.system(size: 10, weight: .semibold))
    .foregroundStyle(color)
    .padding(.horizontal, 9).frame(height: 24)
    .background(color.opacity(0.11)).clipShape(Capsule())
    .accessibilityLabel("Task status: \(title)")
  }
  private var color: Color {
    switch state {
    case .active: Studio.accent
    case .neutral: Studio.secondary
    case .warning: Studio.warning
    }
  }
}

private struct PlanStateMark: View {
  let state: TaskPlanItem.State
  var activeMarkComplete = false
  var body: some View {
    Group {
      switch state {
      case .complete: Image(systemName: "checkmark.circle.fill").foregroundStyle(Studio.success)
      case .active:
        if activeMarkComplete {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(Studio.success)
        } else {
          Circle().fill(Studio.accent).frame(width: 9, height: 9)
        }
      case .waiting: Circle().stroke(Studio.tertiary, lineWidth: 1).frame(width: 11, height: 11)
      case .blocked: Image(systemName: "lock.circle").foregroundStyle(Studio.warning)
      }
    }
    .font(.system(size: 12, weight: .semibold))
    .accessibilityLabel(accessibilityText)
  }
  private var accessibilityText: String {
    switch state {
    case .complete: "Complete"
    case .active: "In progress"
    case .waiting: "Waiting"
    case .blocked: "Blocked"
    }
  }
}

private struct AgentSessionItem: View {
  let item: TimelineItem

  @ViewBuilder var body: some View {
    switch item.category {
    case .human, .agent:
      AgentMessageRow(item: item)
    case .tool, .permission:
      AgentToolRow(item: item)
    case .system:
      EmptyView()
    }
  }
}

private struct AgentMessageRow: View {
  let item: TimelineItem

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        Circle()
          .fill(item.category == .human ? Studio.accentSoft : Studio.raised)
        Text(item.category == .human ? "U" : agentMonogram)
          .font(.system(size: item.category == .human ? 11 : 10, weight: .semibold))
          .foregroundStyle(item.category == .human ? Studio.accent : Color.primary)
      }
      .frame(width: 34, height: 34)
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 7) {
          Text(item.category == .human ? "You" : item.title)
            .font(.system(size: 11.5, weight: .semibold))
          Text(item.time)
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(Studio.secondary)
        }
        if !item.detail.isEmpty {
          Text(item.detail)
            .font(.system(size: 11))
            .foregroundStyle(Color.primary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        } else if item.state == .active {
          ProgressView()
            .controlSize(.mini)
            .frame(height: 16, alignment: .leading)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(item.category == .human ? "You" : item.title), \(item.time). \(item.detail)")
  }

  private var agentMonogram: String {
    let words = item.title.split(separator: " ")
    if words.count > 1 {
      return words.prefix(2).compactMap(\.first).map(String.init).joined().lowercased()
    }
    return String(item.title.prefix(3)).lowercased()
  }
}

private struct AgentToolRow: View {
  let item: TimelineItem

  var body: some View {
    HStack(spacing: 11) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(color)
        .frame(width: 34, height: 34)
        .background(color.opacity(0.09))
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: 3) {
        Text(item.title)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)
        if !item.detail.isEmpty {
          Text(item.detail)
            .font(.system(size: 10.5))
            .foregroundStyle(Studio.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
      }

      Spacer(minLength: 6)
      stateMark
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    .background(Studio.raised.opacity(0.78))
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Agent action: \(item.title). \(item.detail)")
  }

  @ViewBuilder private var stateMark: some View {
    switch item.state {
    case .complete:
      Image(systemName: "checkmark.circle")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Studio.success)
    case .active:
      ProgressView()
        .controlSize(.small)
        .tint(Studio.accent)
    case .waiting:
      Image(systemName: "clock")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Studio.secondary)
    case .warning:
      Image(systemName: "exclamationmark.circle")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Studio.warning)
    }
  }

  private var color: Color {
    if item.category == .permission { return Studio.warning }
    if item.state == .warning { return Studio.warning }
    let normalized = item.title.lowercased()
    if normalized.contains("edit") || normalized.contains("file") || normalized.contains("change") {
      return item.state == .complete ? Studio.success : Studio.accent
    }
    if normalized.contains("test") || normalized.contains("inspect")
      || normalized.contains("screenshot") || normalized.contains("validation")
    { return Color(red: 0.48, green: 0.38, blue: 0.82) }
    return Studio.accent
  }

  private var symbol: String {
    if item.category == .permission { return "hand.raised" }
    let normalized = item.title.lowercased()
    if normalized.contains("edit") || normalized.contains("file") || normalized.contains("change") {
      return "chevron.left.forwardslash.chevron.right"
    }
    if normalized.contains("build") { return "hammer" }
    if normalized.contains("test") { return "flask" }
    if normalized.contains("inspect") || normalized.contains("screenshot")
      || normalized.contains("validation")
    { return "magnifyingglass" }
    if normalized.contains("command") || normalized.contains("terminal") { return "terminal" }
    return "wrench.and.screwdriver"
  }
}

private struct AgentPermissionCard: View {
  @EnvironmentObject var model: AppModel
  let permission: AgentPermissionRequest

  private var primaryAllow: AgentPermissionOption? {
    permission.options.first(where: { $0.kind == "allow_once" })
      ?? permission.options.first(where: \.isAllow)
  }

  private var deny: AgentPermissionOption? {
    permission.options.first(where: { $0.kind == "reject_once" })
      ?? permission.options.first(where: { !$0.isAllow })
  }

  private var taskAllow: AgentPermissionOption? {
    permission.options.first(where: { $0.kind == "allow_always" })
  }

  private var moreOptions: [AgentPermissionOption] {
    permission.options.filter {
      $0.id != primaryAllow?.id && $0.id != taskAllow?.id && $0.id != deny?.id
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(alignment: .top, spacing: 9) {
        Image(systemName: "shield.lefthalf.filled")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Studio.accent)
          .frame(width: 24, height: 24)
          .background(Studio.surface.opacity(0.8))
          .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        VStack(alignment: .leading, spacing: 3) {
          Text(permission.title)
            .font(.system(size: 13, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
          Label(permission.scopeLabel, systemImage: "scope")
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(Studio.secondary)
        }
        Spacer(minLength: 0)
      }

      Text(permission.detail)
        .font(.system(size: 11))
        .foregroundStyle(Studio.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if let command = permission.command, !command.isEmpty {
        Text(command)
          .font(.system(size: 10, design: .monospaced))
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .lineLimit(3)
          .padding(9)
          .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel("Command to approve")
      }

      if let scopeDetail = permission.scopeDetail, !scopeDetail.isEmpty {
        Text(scopeDetail)
          .font(.system(size: 9.5, design: .monospaced))
          .foregroundStyle(Studio.tertiary)
          .lineLimit(2)
          .truncationMode(.middle)
          .textSelection(.enabled)
      }

      HStack(spacing: 8) {
        if let deny {
          Button(deny.displayName) { model.resolveAgentPermission(optionID: deny.id) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Stop this action and continue reviewing the task")
        } else {
          Button("Deny") { model.resolveAgentPermission(optionID: nil) }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        Spacer(minLength: 4)
        if !moreOptions.isEmpty {
          Menu {
            ForEach(moreOptions) { option in
              Button(option.displayName, role: option.isAllow ? nil : .destructive) {
                model.resolveAgentPermission(optionID: option.id)
              }
            }
          } label: {
            Image(systemName: "ellipsis.circle")
              .frame(width: 22, height: 22)
              .contentShape(Rectangle())
              .accessibilityLabel("More permission choices")
          }
          .menuStyle(.borderlessButton)
          .fixedSize()
          .help("Task-scoped permission choices")
        }
        if let taskAllow, taskAllow.id != primaryAllow?.id {
          Button(taskAllow.displayName) {
            model.resolveAgentPermission(optionID: taskAllow.id)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .help("Remember this choice for the current isolated task")
        }
        if let primaryAllow {
          Button(primaryAllow.displayName) {
            model.resolveAgentPermission(optionID: primaryAllow.id)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .keyboardShortcut(.return, modifiers: [])
        }
      }
    }
    .padding(12)
    .background(Studio.accentSoft.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .stroke(Studio.accent.opacity(0.16), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Agent permission request")
  }
}

private func runtimeName(_ runtime: String) -> String {
  runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.iOS-", with: "iOS ")
    .replacingOccurrences(of: "-", with: ".")
}
