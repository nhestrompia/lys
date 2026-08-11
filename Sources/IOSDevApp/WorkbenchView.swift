import AppKit
import IOSDevCore
import SwiftUI

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
            if model.isEvidenceWorkspaceOpen {
              Divider().overlay(Studio.separator)
              EvidenceWorkspace()
                .frame(
                  minHeight: compact ? 132 : 180,
                  idealHeight: compact ? 150 : 240,
                  maxHeight: compact ? 158 : 240)
                .layoutPriority(2)
            }
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
      HStack(spacing: 12) {
        AgentPanel().frame(width: narrow ? 300 : 340)
        AppStage()
          .frame(maxWidth: .infinity)
        VerificationPanel().frame(width: narrow ? 320 : 400)
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
      Text("Lys")
        .font(.system(size: 20, weight: .bold))
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
        Divider()
        Button("Open Simulator", action: model.openSimulator)
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
      HStack(spacing: 9) {
        Image(systemName: "sparkles")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(Studio.accent)
        Text("Agent")
          .font(.system(size: 13, weight: .semibold))
        Spacer()
        HStack(spacing: 5) {
          Circle().fill(Studio.success).frame(width: 7, height: 7)
          Text(model.isBusy ? "Working" : "Live")
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(model.isBusy ? Studio.accent : Studio.success)
      }
      .padding(.horizontal, 20)
      .frame(height: 52)

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 10) {
            Text(taskTitleText)
              .font(.system(size: model.taskTitle.isEmpty ? 20 : 17, weight: .bold))
              .lineSpacing(3)
              .fixedSize(horizontal: false, vertical: true)
            Text(taskSubtitle)
              .font(.system(size: 12))
              .foregroundStyle(Studio.secondary)
              .fixedSize(horizontal: false, vertical: true)
            if !model.taskTitle.isEmpty {
              StatusBadge(title: model.status, state: badgeState)
            }
          }

          if model.needsExpoPreparation {
            ExpoSetupCallout()
          }

          if !model.plan.isEmpty {
            Divider().overlay(Studio.separator)
            HStack {
              Text("Plan").font(.system(size: 12, weight: .semibold))
              Spacer()
              Text("Generation \(model.generation)")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Studio.secondary)
            }
            VStack(spacing: 0) {
              ForEach(Array(model.plan.enumerated()), id: \.element.id) { index, item in
                PlanActivityRow(
                  index: index, item: item, detail: planDetail(for: index),
                  duration: nil, activeMarkComplete: false)
              }
            }
          }

          if let journey = model.activeJourney {
            JourneyProgressSection(journey: journey)
          }

          if model.plan.isEmpty {
            Divider().overlay(Studio.separator)
            HStack {
              Text("Agent activity").font(.system(size: 12, weight: .semibold))
              Spacer()
              Text(model.isBusy ? "Live" : "Idle")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(model.isBusy ? Studio.accent : Studio.secondary)
            }
            if model.timeline.isEmpty {
              Text("Open a repository to begin.").font(.system(size: 12)).foregroundStyle(
                Studio.secondary)
            } else {
              VStack(spacing: 0) {
                ForEach(model.timeline.suffix(8)) { item in
                  ActivityRow(item: item)
                }
              }
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
      }

      if let permission = model.pendingAgentPermission {
        Divider().overlay(Studio.separator)
        AgentPermissionCard(permission: permission)
          .padding(.horizontal, 16)
          .padding(.vertical, 14)
      }

      Divider().overlay(Studio.separator)
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .bottom, spacing: 8) {
          ZStack(alignment: .topLeading) {
            if model.taskPrompt.isEmpty {
              Text(
                model.hasAgentSession
                  ? "Continue the conversation…" : "Ask the agent to test or change something…"
              )
              .font(.system(size: 12))
              .foregroundStyle(Studio.tertiary)
              .padding(.horizontal, 4).padding(.vertical, 7)
              .allowsHitTesting(false)
            }
            AgentComposerEditor(text: $model.taskPrompt, onSubmit: model.sendAgentPrompt)
              .frame(minHeight: 34, maxHeight: 68)
              .accessibilityLabel("Agent message")
          }
          Button(action: model.sendAgentPrompt) {
            Image(systemName: "paperplane.fill").frame(width: 28, height: 28)
          }
          .buttonStyle(.plain)
          .foregroundStyle(model.canSendAgentPrompt ? Studio.accent : Studio.tertiary)
          .disabled(!model.canSendAgentPrompt)
          .keyboardShortcut(.return, modifiers: [.command])
          .help(model.agentComposerBlocker ?? "Send message (Command–Return)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(height: 48)
        .background(Studio.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

        Text(model.agentComposerBlocker ?? "Command–Return to send")
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(model.agentComposerBlocker == nil ? Studio.secondary : Studio.warning)
          .lineLimit(2)

        AgentConfigurationBar()

        Text(model.agentConfigStatusText)
          .font(.system(size: 9.5))
          .foregroundStyle(Studio.tertiary)
          .lineLimit(2)
      }
      .padding(.horizontal, 16)
      .padding(.top, 16)
      .padding(.bottom, 16)
    }
    .background(Studio.surface)
    .clipShape(RoundedRectangle(cornerRadius: Studio.panelRadius, style: .continuous))
    .shadow(color: .black.opacity(0.022), radius: 14, y: 4)
  }

  private var taskTitleText: String {
    if model.taskTitle.isEmpty { return "What should the agent change?" }
    return model.taskTitle
  }

  private func planDetail(for index: Int) -> String {
    switch index {
    case 0: return "Preparing the task context."
    case 1: return "Updating the isolated worktree."
    case 2: return "Waiting for agent output."
    case 3: return "Collecting fresh evidence."
    default: return "Waiting for the previous step."
    }
  }

  private var taskSubtitle: String {
    if model.repository == nil {
      return "Open an existing Git repository. Every editable task starts in an isolated worktree."
    }
    if !model.isGitRepository {
      return "App inspection and testing are available. Source editing requires Git."
    }
    if model.taskTitle.isEmpty {
      return
        "Describe one outcome. Build and verification evidence will stay tied to the current mutation generation."
    }
    if model.activeTaskIntent?.allowsSourceWrites == false {
      return "Current app preserved · Source read-only · Generation \(model.generation)"
    }
    return "Original checkout protected · Generation \(model.generation)"
  }

  private var badgeState: StatusBadge.State {
    if model.status.contains("failed") || model.status.contains("blocked") { return .warning }
    if model.isBusy { return .active }
    return .neutral
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
        .frame(height: 20)
        .padding(.horizontal, 9)
      AgentEffortSelector()
        .fixedSize(horizontal: true, vertical: false)
    }
    .frame(height: 34)
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
      .frame(height: 32)
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
        HStack(spacing: 7) {
          Text(model.agentReasoningLabel)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Color.primary)
          Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Studio.secondary)
        }
        .padding(.horizontal, 3)
        .frame(height: 32)
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
        .frame(height: 32)
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
  @State private var previewZoom: CGFloat = 1
  @State private var landscape = false

  var body: some View {
    GeometryReader { geometry in
      let compact = geometry.size.height < 560
      let emptyState = model.repository == nil
      let previewViewportWidth = max(0, geometry.size.width - 58)
      let widthFittedDeviceHeight = landscape
        ? max(300, previewViewportWidth - 44)
        : max(300, (previewViewportWidth - 44) / 0.505)
      let fittedDeviceHeight = min(
        650,
        max(360, min(geometry.size.height - (compact ? 180 : 100), widthFittedDeviceHeight)))
      let emptyDeviceHeight = min(
        700,
        max(420, min(geometry.size.height * 0.80, widthFittedDeviceHeight)))
      let deviceHeight = compact
        ? max(300, geometry.size.height - 180)
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
              Label(
                model.startDevServerOnRun ? "Metro on Run" : "Metro off",
                systemImage: model.startDevServerOnRun
                  ? "bolt.horizontal.circle.fill" : "bolt.slash.circle"
              )
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(model.startDevServerOnRun ? Studio.success : Studio.secondary)
            }
            .buttonStyle(.plain)
            .help("Choose whether Run starts the Expo development server")
          }
          Spacer()
          orientationControls
          Button(action: model.refreshApp) {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 13, weight: .medium))
              .frame(width: 30, height: 30)
          }
          .buttonStyle(.plain)
          .disabled(model.selectedTarget == nil || model.isBusy)
          .help("Relaunch the installed app and capture a fresh screenshot")
          Menu {
            Button("Open Simulator", systemImage: "arrow.up.right.square", action: model.openSimulator)
              .disabled(model.preflight?.isFullXcode != true)
            Button("Refresh App", systemImage: "arrow.clockwise", action: model.refreshApp)
              .disabled(model.selectedTarget == nil || model.isBusy)
            Toggle("Open Apple Simulator after Run", isOn: $model.openLiveSimulatorOnRun)
            Button(
              "Capture Screenshot", systemImage: "camera", action: model.captureCurrentScreenshot
            )
            .disabled(model.selectedTarget == nil)
            Button("Stop", action: model.stop).disabled(!model.isBusy)
          } label: {
            Image(systemName: "ellipsis").frame(width: 32, height: 32)
          }
          .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 20)
        .frame(height: compact ? 38 : 44)

        HStack(spacing: 0) {
          if emptyState {
            VStack(spacing: 0) {
              Spacer(minLength: 0)
              DevicePreview(height: deviceHeight * previewZoom, landscape: landscape)
                .offset(y: geometry.size.height >= 800 ? 32 : 0)
              Spacer(minLength: 0)
            }
            .frame(minWidth: previewViewportWidth, maxWidth: previewViewportWidth, maxHeight: .infinity)
            .background(Studio.backdrop)
            .clipped()
          } else {
            ScrollView([.horizontal, .vertical]) {
              DevicePreview(height: deviceHeight * previewZoom, landscape: landscape)
                .padding(.horizontal, 22)
                .padding(.top, compact ? 120 : 8)
                .padding(.bottom, compact ? 0 : 8)
                .frame(
                  minWidth: max(0, previewViewportWidth - 44),
                  minHeight: max(0, geometry.size.height - (compact ? 78 : 98)), alignment: .top)
            }
            .frame(
              minWidth: previewViewportWidth, maxWidth: previewViewportWidth,
              maxHeight: .infinity)
            .scrollIndicators(.automatic)
            .background(Studio.backdrop)
            .clipped()
          }
          InteractionPalette()
            .frame(width: 58)
            .frame(maxHeight: .infinity)
            .background(Studio.backdrop)
        }
        .background(Studio.backdrop)

        HStack(spacing: 0) {
          appearanceControls
          if !compact {
            Divider().frame(height: 22).padding(.horizontal, 10)
            zoomControls
          }
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
      Divider().frame(height: 20).padding(.horizontal, 8)
      Button {
        landscape.toggle()
      } label: {
        Image(systemName: "arrow.triangle.2.circlepath")
          .font(.system(size: 13, weight: .medium))
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.plain)
      .foregroundStyle(Studio.secondary)
      .help("Rotate the preview")
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
    }
    .buttonStyle(.plain)
  }

  private var appearanceControls: some View {
    HStack(spacing: 2) {
      Image(systemName: "sun.max").foregroundStyle(Studio.secondary).frame(width: 30)
      appearanceButton(.light, title: "Light")
      appearanceButton(.dark, title: "Dark")
      Divider().frame(height: 20).padding(.horizontal, 6)
      Image(systemName: "iphone").foregroundStyle(Studio.secondary)
      Text(landscape ? "Landscape" : "Portrait")
        .font(.system(size: 11, weight: .medium))
        .fixedSize()
    }
    .fixedSize()
  }

  private var zoomControls: some View {
    HStack(spacing: 3) {
      Button {
        adjustZoom(by: -0.1)
      } label: {
        Image(systemName: "minus.magnifyingglass").frame(width: 32, height: 32)
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
        Image(systemName: "plus.magnifyingglass").frame(width: 32, height: 32)
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
          SimulatorLiveSurface(session: model.simulatorLiveSession)
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
        Button("Open Simulator", systemImage: "arrow.up.right.square", action: model.openSimulator)
          .disabled(model.preflight?.isFullXcode != true)
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
      Button("Simulator", action: model.openSimulator)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(model.preflight?.isFullXcode != true)
        .help("Open the selected Simulator")
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
      HStack(spacing: 0) {
        ForEach(EvidenceWorkspaceTab.allCases) { tab in
          tabButton(tab)
        }
        if !model.proposedChanges.isEmpty {
          Text("\(model.proposedChanges.count)")
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .foregroundStyle(Studio.secondary)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Studio.raised)
            .clipShape(Capsule())
            .padding(.leading, -4)
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
      }
      .padding(.horizontal, 16)
      .frame(height: 40)
      Divider().overlay(Studio.separator)
      tabContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Studio.surface)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .shadow(color: .black.opacity(0.018), radius: 11, y: 4)
    .padding(.leading, 24)
    .padding(.trailing, 24)
    .padding(.top, 8)
    .padding(.bottom, 4)
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
    case .changes:
      if model.proposedChanges.isEmpty {
        workspaceMessage(
          symbol: "checkmark", title: "No changes",
          detail: "The isolated task has not produced a change set.")
      } else {
        changesContent
      }
    }
  }

  private var evidenceContent: some View {
    HStack(spacing: 0) {
      ScrollView(.horizontal) {
        HStack(spacing: 12) {
          ForEach(Array(model.verificationEvidence.reversed().prefix(4))) { evidence in
            Button { selectedEvidence = evidence } label: {
              EvidenceThumbnail(evidence: evidence)
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

  private var changesContent: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(model.proposedChanges) { change in
          HStack(spacing: 14) {
            Text(change.kind.rawValue.uppercased())
              .font(.system(size: 9, weight: .bold).monospaced())
              .foregroundStyle(changeColor(change.kind))
              .frame(width: 68, alignment: .leading)
            Text(change.path)
              .font(.system(size: 10.5).monospaced())
              .lineLimit(1)
            Spacer(minLength: 0)
            if change.binary {
              Text("Binary")
                .font(.system(size: 9.5))
                .foregroundStyle(Studio.warning)
            }
          }
          .padding(.horizontal, 18)
          .frame(minHeight: 32)
        }
      }
    }
  }

  private func tabButton(_ tab: EvidenceWorkspaceTab) -> some View {
    Button {
      model.evidenceWorkspaceTab = tab
      if tab == .terminal { model.isTerminalExpanded = true }
    } label: {
      Text(tab.rawValue)
        .font(.system(size: 10.5, weight: model.evidenceWorkspaceTab == tab ? .semibold : .medium))
        .foregroundStyle(model.evidenceWorkspaceTab == tab ? Color.primary : Studio.secondary)
        .frame(width: tabWidth(tab), height: 40)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
        Rectangle()
          .fill(model.evidenceWorkspaceTab == tab ? Color.primary : .clear)
          .frame(
            width: model.evidenceWorkspaceTab == tab ? tabWidth(tab) - 18 : 0,
            height: 2)
        }
    }
    .buttonStyle(.plain)
    .contentShape(Rectangle())
    .accessibilityLabel("Show \(tab.rawValue)")
    .accessibilityValue(model.evidenceWorkspaceTab == tab ? "Selected" : "")
  }

  private func tabWidth(_ tab: EvidenceWorkspaceTab) -> CGFloat {
    switch tab {
    case .terminal, .logs: 70
    case .evidence: 88
    case .changes: 78
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

  private func changeColor(_ kind: ProposedChangeKind) -> Color {
    switch kind {
    case .added: Studio.success
    case .modified: Studio.accent
    case .deleted: .red
    }
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

private struct EvidenceToggleButton: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    Button(action: model.toggleEvidenceWorkspace) {
      Image(systemName: model.isEvidenceWorkspaceOpen ? "chevron.down" : "chevron.up")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Studio.secondary)
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .keyboardShortcut("e", modifiers: [.command, .shift])
    .accessibilityLabel(
      model.isEvidenceWorkspaceOpen ? "Close bottom workspace" : "Open bottom workspace")
    .help(
      model.isEvidenceWorkspaceOpen
        ? "Close bottom workspace (⇧⌘E)" : "Open bottom workspace (⇧⌘E)")
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
          Image(systemName: model.activeWorktree == nil ? "checkmark.circle" : "shippingbox.fill")
            .foregroundStyle(model.activeWorktree == nil ? Studio.success : Studio.accent)
          Text(model.activeWorktree == nil ? "All changes committed" :
            "\(model.changedFileCount) \(model.changedFileCount == 1 ? "file" : "files") changed")
          .font(.system(size: 12, weight: .semibold)).monospacedDigit()
          if model.activeWorktree != nil {
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
              .foregroundStyle(Studio.secondary)
          }
        }
      }
      .buttonStyle(.plain)
      .disabled(model.activeWorktree == nil)
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
          }
          .buttonStyle(.plain)
          .foregroundStyle(.white)
          .background(Studio.accent)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Button {
          model.notice = "No unread notifications."
        } label: {
          Image(systemName: "bell")
            .font(.system(size: 14, weight: .medium))
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Studio.secondary)
        .help("Notifications")
        Divider()
          .frame(height: 18)
          .overlay(Studio.separator)
        EvidenceToggleButton()
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
    if model.proposedChanges.isEmpty { model.reviewChanges() }
    model.section = .changes
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
  }

  private var releaseColumn: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Deploy")
        .font(.system(size: 19, weight: .bold))
      Text("Distribute your app with TestFlight.")
        .font(.system(size: 11))
        .foregroundStyle(Studio.secondary)
        .padding(.top, 7)

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
      .padding(.top, 22)

      DeploySurface {
        DeployEmptyState(
          symbol: listTab == .releases ? "shippingbox" : "hammer",
          title: listTab == .releases ? "No releases yet" : "No deployment builds yet",
          detail: listTab == .releases
            ? "Release history will appear here when TestFlight data is connected."
            : "Builds prepared for distribution will appear here."
        )
      }
      .frame(maxHeight: .infinity)
      .padding(.top, 14)
    }
  }

  private var detailColumn: some View {
    DeploySurface {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 5) {
          Text("No release selected")
            .font(.system(size: 20, weight: .bold))
          Text("Choose a release after deployment data is connected.")
            .font(.system(size: 10.5))
            .foregroundStyle(Studio.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)

        ScrollView(.horizontal) {
          HStack(spacing: 25) {
            ForEach(DeployDetailTab.allCases) { tab in
              Button {
                detailTab = tab
              } label: {
                VStack(spacing: 9) {
                  Text(tab.rawValue)
                    .font(.system(size: 10.5, weight: detailTab == tab ? .semibold : .medium))
                    .foregroundStyle(detailTab == tab ? Color.primary : Studio.secondary)
                  Rectangle()
                    .fill(detailTab == tab ? Color.primary : .clear)
                    .frame(height: 1)
                }
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Show deploy \(tab.rawValue.lowercased())")
            }
          }
          .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 24)

        Divider().overlay(Studio.separator)
        detailContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  @ViewBuilder private var detailContent: some View {
    switch detailTab {
    case .overview:
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .top, spacing: 14) {
            deploySection(title: "App Preview") {
              appPreview
            }
            deploySection(title: "Build Information") {
              buildInformation
            }
            .frame(width: 250)
          }
          .padding(18)

          Divider().overlay(Studio.separator)
          deployTextSection(
            title: "Processing",
            detail: "Processing information will appear when a deployment build is active.")
          Divider().overlay(Studio.separator)
          deployTextSection(
            title: "What's New",
            detail: "Release notes will appear here when they are available.")
          Divider().overlay(Studio.separator)
          screenshotSection
        }
      }
    case .whatsNew:
      DeployEmptyState(
        symbol: "text.alignleft", title: "No release notes",
        detail: "Release notes will appear when a release is selected.")
    case .screenshots:
      if let image = model.currentScreenshotImage {
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
          .padding(24)
      } else {
        DeployEmptyState(
          symbol: "photo.on.rectangle", title: "No release screenshots",
          detail: "Screenshots attached to the selected release will appear here.")
      }
    case .testers:
      DeployEmptyState(
        symbol: "person.2", title: "No tester data",
        detail: "Tester access will appear when TestFlight data is connected.")
    case .feedback:
      DeployEmptyState(
        symbol: "bubble.left.and.bubble.right", title: "No feedback",
        detail: "Tester feedback for the selected release will appear here.")
    case .buildDetails:
      VStack(alignment: .leading, spacing: 0) {
        buildInformation
          .padding(24)
        Spacer(minLength: 0)
      }
    }
  }

  private var insightsColumn: some View {
    VStack(spacing: 14) {
      DeploySurface {
        VStack(alignment: .leading, spacing: 0) {
          HStack {
            Text("Testers").font(.system(size: 12, weight: .semibold))
            Spacer()
          }
          .padding(.horizontal, 20)
          .frame(height: 54)
          Divider().overlay(Studio.separator)
          DeployEmptyState(
            symbol: "person.2", title: "No testers",
            detail: "Tester groups and access will appear here.")
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
          DeployEmptyState(
            symbol: "bubble.left", title: "No feedback yet",
            detail: "Feedback from connected tester groups will appear here.")
        }
      }
      .frame(maxHeight: .infinity)
    }
  }

  private var appPreview: some View {
    HStack(spacing: 15) {
      Group {
        if let image = model.currentScreenshotImage {
          Image(nsImage: image).resizable().scaledToFill()
        } else {
          Image(systemName: "app.dashed")
            .font(.system(size: 27, weight: .light))
            .foregroundStyle(Studio.tertiary)
        }
      }
      .frame(width: 82, height: 82)
      .background(Studio.raised)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

      VStack(alignment: .leading, spacing: 5) {
        Text(model.selectedScheme.isEmpty ? "No app selected" : model.selectedScheme)
          .font(.system(size: 16, weight: .bold))
          .lineLimit(1)
        Text(model.selectedTarget == nil ? "Run a project to create an app preview." : "Current local app preview")
          .font(.system(size: 10.5))
          .foregroundStyle(Studio.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
      if let image = model.currentScreenshotImage {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: 104, height: 142)
          .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
      } else {
        Text("No release screenshots are available.")
          .font(.system(size: 10.5))
          .foregroundStyle(Studio.secondary)
      }
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

private struct DeployEmptyState: View {
  let symbol: String
  let title: String
  let detail: String

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
            CodeEditor(text: $model.source, readOnly: model.activeWorktree == nil)
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
          OutlineGroup(model.files, children: \.children) { node in
            let isSelected = model.selectedFile == node.url
            Button {
              model.selectFile(node.url)
            } label: {
              HStack(spacing: 7) {
                Image(systemName: node.children == nil ? fileSymbol(node.name) : "folder")
                  .foregroundStyle(node.children == nil ? Studio.secondary : Studio.accent)
                Text(node.name).lineLimit(1)
                Spacer(minLength: 0)
              }
              .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
              .padding(.horizontal, 8)
              .frame(height: 29)
              .background(isSelected ? Studio.accentSoft : .clear)
              .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
          .padding(10)
        }
      }
    }
    .background(Studio.surface)
  }

  private func fileSymbol(_ name: String) -> String {
    if name.hasSuffix(".swift") { return "swift" }
    if name.hasSuffix(".json") { return "curlybraces" }
    return "doc"
  }
}

private struct GitWorkspace: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 16) {
        WorkspaceHeader(
          symbol: "arrow.triangle.branch",
          title: "Changes",
          detail: "Review the isolated task against its exact baseline"
        )
        Spacer(minLength: 0)
        StatusBadge(
          title: model.activeWorktree == nil ? "No task" : "Task worktree",
          state: model.activeWorktree == nil ? .neutral : .active
        )
        Button {
          model.reviewChanges()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Refresh the baseline-relative change set")
      }
      .padding(.horizontal, 24)
      .frame(height: 72)
      .background(Studio.surface)
      Divider().overlay(Studio.separator)

      HStack(spacing: 0) {
        changeMetric("Changed", count: modifiedCount, color: Studio.accent)
        Divider().frame(height: 26).overlay(Studio.separator)
        changeMetric("Added", count: addedCount, color: Studio.success)
        Divider().frame(height: 26).overlay(Studio.separator)
        changeMetric("Deleted", count: deletedCount, color: .red)
        Spacer()
        Text(model.activeWorktree?.lastPathComponent ?? "No isolated task selected")
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(Studio.tertiary)
          .lineLimit(1)
          .truncationMode(.middle)
          .padding(.trailing, 24)
      }
      .padding(.leading, 24)
      .frame(height: 58)
      .background(Studio.surface)
      Divider().overlay(Studio.separator)

      if model.proposedChanges.isEmpty {
        WorkspaceEmpty(
          symbol: "arrow.triangle.branch", title: "No proposed changes",
          detail: "Create an isolated task or refresh the baseline-relative change set.")
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(model.proposedChanges) { change in
              HStack(spacing: 12) {
                Text(change.kind.rawValue.uppercased())
                  .font(.system(size: 9, weight: .bold).monospaced())
                  .foregroundStyle(changeColor(change.kind))
                  .frame(width: 62, alignment: .leading)
                Image(systemName: change.binary ? "shippingbox" : "doc.text")
                  .foregroundStyle(Studio.secondary)
                Text(change.path)
                  .font(.system(size: 11.5, design: .monospaced))
                  .lineLimit(1)
                  .truncationMode(.middle)
                Spacer(minLength: 0)
                if change.binary {
                  Text("Binary")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Studio.warning)
                }
              }
              .padding(.horizontal, 24)
              .frame(height: 48)
              .background(Studio.surface)
              .overlay(alignment: .bottom) { Divider().overlay(Studio.separator) }
            }
            ForEach(model.applyConflicts) { conflict in
              VStack(alignment: .leading, spacing: 5) {
                Label(
                  "Manual resolution required · \(conflict.path)",
                  systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Studio.warning)
                Text(conflict.reason).font(.system(size: 11)).foregroundStyle(Studio.secondary)
                if let artifact = conflict.resolutionArtifact {
                  Text(artifact).font(.system(size: 10).monospaced()).textSelection(.enabled)
                }
              }
              .padding(16)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.orange.opacity(0.08))
            }
          }
          .padding(20)
        }
      }
    }
    .background(Studio.backdrop)
  }

  private func changeMetric(_ title: String, count: Int, color: Color) -> some View {
    HStack(spacing: 8) {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Studio.secondary)
      Text("\(count)").font(.system(size: 12, weight: .semibold).monospacedDigit())
    }
    .frame(width: 112, alignment: .leading)
  }

  private var addedCount: Int { model.proposedChanges.filter { $0.kind == .added }.count }
  private var modifiedCount: Int { model.proposedChanges.filter { $0.kind == .modified }.count }
  private var deletedCount: Int { model.proposedChanges.filter { $0.kind == .deleted }.count }

  private func changeColor(_ kind: ProposedChangeKind) -> Color {
    switch kind {
    case .added: Studio.success
    case .modified: Studio.accent
    case .deleted: .red
    }
  }
}

private struct SettingsWorkspace: View {
  @EnvironmentObject var model: AppModel

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
    if let url = Bundle.module.url(
      forResource: id, withExtension: "svg", subdirectory: "AgentIcons")
      ?? Bundle.module.url(forResource: id, withExtension: "svg"),
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

private struct ActivityRow: View {
  let item: TimelineItem
  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Text(item.time).font(.system(size: 10).monospacedDigit()).foregroundStyle(Studio.secondary)
        .frame(width: 42, alignment: .leading)
      Circle().fill(color).frame(width: 7, height: 7).padding(.top, 4)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title).font(
          .system(size: 11, weight: item.state == .active ? .semibold : .regular)
        )
        .foregroundStyle(
          item.state == .complete && item.category != .agent ? Studio.success : Color.primary)
        if !item.detail.isEmpty {
          Text(item.detail).font(.system(size: 10)).foregroundStyle(Studio.secondary)
            .lineLimit(item.category == .agent ? 6 : 2)
            .textSelection(.enabled)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 5)
  }
  private var color: Color {
    switch item.state {
    case .complete: Studio.success
    case .active: Studio.accent
    case .waiting: Studio.tertiary
    case .warning: Studio.warning
    }
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
