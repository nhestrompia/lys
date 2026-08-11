import AppKit
import IOSDevCore
import SwiftUI

private enum Studio {
  static let backdrop = Color(red: 0.965, green: 0.968, blue: 0.974)
  static let surface = Color.white
  static let raised = Color(red: 0.955, green: 0.96, blue: 0.968)
  static let separator = Color.black.opacity(0.085)
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
        OperateToolbar()
          .layoutPriority(2)
        Divider().overlay(Studio.separator)
        HStack(spacing: 0) {
          NavigationRail()
          Divider().overlay(Studio.separator)
          content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .layoutPriority(0)
        Divider().overlay(Studio.separator)
        TerminalDrawer()
          .layoutPriority(2)
        Divider().overlay(Studio.separator)
        TaskActionBar()
          .layoutPriority(2)
      }
      .frame(width: viewport.size.width, height: viewport.size.height, alignment: .top)
      .clipped()
    }
    .background(Studio.backdrop)
    .foregroundStyle(Color(nsColor: .labelColor))
    .tint(Studio.accent)
    .alert(
      "Operate",
      isPresented: Binding(
        get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })
    ) {
      Button("OK") { model.notice = nil }
    } message: {
      Text(model.notice ?? "")
    }
  }

  @ViewBuilder private var content: some View {
    switch model.section {
    case .agent:
      HStack(spacing: 12) {
        AgentPanel().frame(width: 380)
        AppStage().frame(maxWidth: .infinity)
        VerificationPanel().frame(width: 420)
      }
      .padding(12)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .code:
      CodeWorkspace()
    case .files:
      FilesWorkspace()
    case .git:
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

private struct OperateToolbar: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    HStack(spacing: 12) {
      Spacer().frame(width: 102)
      Text("Operate")
        .font(.system(size: 18, weight: .bold))
        .padding(.trailing, 20)
      Divider().frame(height: 24).overlay(Studio.separator)

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
          symbol: "shippingbox", title: model.repository?.lastPathComponent ?? "Open Project",
          width: 152)
      }
      .menuStyle(.borderlessButton)
      .tint(Color(nsColor: .labelColor))

      ToolbarControl(
        symbol: "arrow.triangle.branch", title: model.branchName, width: 118)

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
          title: model.selectedDestination.map { "\($0.name) · \(runtimeName($0.runtime))" }
            ?? "Select Simulator", width: 250)
      }
      .menuStyle(.borderlessButton)
      .tint(Color(nsColor: .labelColor))

      if model.schemes.count > 1 {
        Menu {
          ForEach(model.schemes, id: \.self) { scheme in
            Button(scheme) { model.selectScheme(scheme) }
          }
        } label: {
          ToolbarControl(
            symbol: "square.stack.3d.up",
            title: model.selectedScheme.isEmpty ? "Scheme" : model.selectedScheme,
            width: 142)
        }
        .menuStyle(.borderlessButton)
        .tint(Color(nsColor: .labelColor))
      }

      Spacer(minLength: 12)

      HStack(spacing: 7) {
        Circle().fill(statusColor).frame(width: 9, height: 9)
        Text(model.status).font(.system(size: 12, weight: .medium)).lineLimit(1)
        if model.isBusy { ProgressView().controlSize(.small).scaleEffect(0.72) }
      }
      .padding(.horizontal, 12)
      .frame(height: 36)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Status: \(model.status)")

      HStack(spacing: 0) {
        Button(action: model.run) {
          Label("Run", systemImage: "play.fill")
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 92, height: 36)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .disabled(!model.canRun)
        Divider().overlay(Color.white.opacity(0.22)).frame(height: 36)
        Menu {
          Button("Build", action: model.build).disabled(!model.canBuild)
          Button("Stop", action: model.stop).disabled(!model.isBusy)
          if model.isExpoRepository {
            Divider()
            Toggle("Start Expo development server", isOn: $model.startDevServerOnRun)
          }
          Divider()
          Button("Open Simulator", action: model.openSimulator)
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 42, height: 36)
            .foregroundStyle(.white)
        }
        .menuStyle(.borderlessButton)
      }
      .background(Studio.accent.opacity(model.canRun ? 1 : 0.5))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

      Spacer().frame(width: 24)
    }
    .padding(.horizontal, 14)
    .frame(height: 68)
    .background(Studio.surface)
  }

  private var statusColor: Color {
    if model.status.contains("failed") || model.status.contains("blocked") { return Studio.warning }
    if model.isBusy { return Studio.accent }
    return model.repository == nil ? Studio.tertiary : Studio.success
  }
}

private struct ToolbarControl: View {
  let symbol: String
  let title: String
  let width: CGFloat

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: symbol).font(.system(size: 13, weight: .medium))
      Text(title).lineLimit(1)
    }
    .font(.system(size: 12, weight: .medium))
    .padding(.horizontal, 12)
    .frame(width: width, height: 36)
    .background(Studio.raised)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .shadow(color: .black.opacity(0.035), radius: 5, y: 2)
  }
}

private struct NavigationRail: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    VStack(spacing: 8) {
      ForEach(PrimarySection.allCases) { section in
        Button {
          model.section = section
        } label: {
          VStack(spacing: 5) {
            Image(systemName: section.symbol)
              .symbolVariant(model.section == section ? .fill : .none)
              .font(.system(size: 19, weight: .regular))
              .frame(width: 38, height: 34)
              .background(model.section == section ? Studio.accentSoft : .clear)
              .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(section.rawValue).font(.system(size: 10, weight: .medium))
          }
          .foregroundStyle(model.section == section ? Studio.accent : Studio.secondary)
          .frame(width: 68, height: 66)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.rawValue)
        if section == .git { Spacer() }
      }
    }
    .padding(.vertical, 22)
    .frame(minWidth: 88, maxWidth: 88, maxHeight: .infinity)
    .background(Studio.surface)
  }
}

private struct AgentPanel: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Agent")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Studio.accent)
        .padding(.horizontal, 22)
        .padding(.top, 20)

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 10) {
            Text(model.taskTitle.isEmpty ? "What should the agent change?" : model.taskTitle)
              .font(.system(size: model.taskTitle.isEmpty ? 21 : 19, weight: .bold))
              .lineSpacing(5)
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
              Text("Host tracked").font(.system(size: 11)).foregroundStyle(Studio.secondary)
            }
            VStack(spacing: 10) {
              ForEach(Array(model.plan.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                  Text("\(index + 1).").font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Studio.accent).frame(width: 18, alignment: .trailing)
                  Text(item.title).font(.system(size: 12)).lineLimit(2)
                  Spacer()
                  PlanStateMark(state: item.state)
                }
              }
            }
          }

          if let journey = model.activeJourney {
            JourneyProgressSection(journey: journey)
          }

          Divider().overlay(Studio.separator)
          HStack {
            Text("Agent activity").font(.system(size: 12, weight: .semibold))
            Spacer()
            HStack(spacing: 5) {
              Text(model.isBusy ? "Live" : "Idle")
              Circle().fill(model.isBusy ? Studio.accent : Studio.tertiary).frame(
                width: 6, height: 6)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(model.isBusy ? Studio.accent : Studio.secondary)
          }
          if model.timeline.isEmpty {
            Text("Open a repository to begin.").font(.system(size: 12)).foregroundStyle(
              Studio.secondary)
          } else {
            VStack(spacing: 0) {
              ForEach(model.timeline.suffix(10)) { item in
                ActivityRow(item: item)
              }
            }
          }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
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
        .frame(minHeight: 48)
        .background(Studio.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

        Text(model.agentComposerBlocker ?? "Command–Return to send")
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(model.agentComposerBlocker == nil ? Studio.secondary : Studio.warning)
          .lineLimit(2)

        VStack(alignment: .leading, spacing: 7) {
          HStack {
            Menu {
              if model.adapters.allSatisfy({ $0.executable == nil }) {
                Text("No ACP-ready adapters detected")
              }
              ForEach(model.adapters) { adapter in
                Button(adapter.displayName) { model.selectAgentAdapter(adapter.id) }
                  .disabled(adapter.executable == nil || model.hasAgentSession)
              }
            } label: {
              Text(agentLabel)
              .font(.system(size: 11))
              .foregroundStyle(Studio.secondary)
            }
            .menuStyle(.borderlessButton)
            Spacer()
            Button {
              model.section = .settings
            } label: {
              Image(systemName: "gearshape").frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Studio.accent)
          }

          HStack(spacing: 6) {
            if let option = model.agentModelOption {
              AgentConfigPicker(
                option: option, title: "Model", value: model.agentModelLabel,
                symbol: "cpu")
            } else {
              AgentConfigPlaceholder(title: "Model", symbol: "cpu")
            }
            if let option = model.agentReasoningOption {
              AgentConfigPicker(
                option: option, title: "Reasoning", value: model.agentReasoningLabel,
                symbol: "brain.head.profile")
            } else {
              AgentConfigPlaceholder(title: "Reasoning", symbol: "brain.head.profile")
            }
            Spacer(minLength: 0)
          }
          Text(model.agentConfigStatusText)
            .font(.system(size: 9.5))
            .foregroundStyle(Studio.tertiary)
            .lineLimit(2)
        }
      }
      .padding(16)
    }
    .background(Studio.surface)
    .clipShape(RoundedRectangle(cornerRadius: Studio.panelRadius, style: .continuous))
    .shadow(color: .black.opacity(0.045), radius: 16, y: 7)
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

  private var agentLabel: String {
    guard let adapter = model.adapters.first(where: { $0.id == model.selectedAdapterID }) else {
      return "Choose ACP agent"
    }
    return adapter.executable == nil
      ? "\(adapter.displayName) needs setup" : adapter.displayName
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

private struct AgentConfigPicker: View {
  @EnvironmentObject var model: AppModel
  let option: ACPConfigOption
  let title: String
  let value: String
  let symbol: String

  var body: some View {
    Menu {
      ForEach(option.options) { item in
        Button {
          model.setAgentConfigOption(option, value: item)
        } label: {
          HStack {
            Text(item.name)
            if isCurrent(item) {
              Spacer()
              Image(systemName: "checkmark")
            }
          }
        }
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: symbol)
        Text("\(title): \(value)")
          .font(.system(size: 9.5, weight: .medium))
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .foregroundStyle(Studio.secondary)
      .padding(.horizontal, 8)
      .frame(height: 26)
      .background(Studio.raised)
      .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .menuStyle(.borderlessButton)
    .help(
      model.canChangeAgentConfigOption(option)
        ? (option.description ?? "Choose the agent \(title.lowercased())")
        : model.agentConfigStatusText)
    .disabled(
      !model.canChangeAgentConfigOption(option)
        || (model.hasAgentSession && model.isBusy))
  }

  private func isCurrent(_ item: ACPConfigOptionValue) -> Bool {
    option.currentValue?.stringValue == item.value
  }
}

private struct AgentConfigPlaceholder: View {
  let title: String
  let symbol: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
      Text("\(title): Not reported")
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(Studio.tertiary)
    }
    .foregroundStyle(Studio.secondary)
    .padding(.horizontal, 8)
    .frame(height: 26)
    .background(Studio.raised)
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    .help("The selected CLI has not reported a \(title.lowercased()) yet.")
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
          "No .xcworkspace or .xcodeproj was found. Generate it here, then Operate will discover the scheme automatically."
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

  var body: some View {
    GeometryReader { geometry in
      let fittedDeviceHeight = min(650, max(300, geometry.size.height - 132))
      let previewViewportWidth = max(0, geometry.size.width - 58)

      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Menu {
            ForEach(model.schemes, id: \.self) { scheme in
              Button(scheme) { model.selectScheme(scheme) }
            }
          } label: {
            Text(model.selectedScheme.isEmpty ? "App" : model.selectedScheme)
            .font(.system(size: 12, weight: .semibold))
          }
          .menuStyle(.borderlessButton)
          if model.designPreview {
            Text("Synthetic QA fixture")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(Studio.accent)
              .padding(.horizontal, 8).padding(.vertical, 4)
              .background(Studio.accentSoft).clipShape(Capsule())
          }
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
          if let journey = model.activeJourney {
            let completed = journey.steps.filter { $0.status == .passed }.count
            Label {
              Text(
                journey.steps.isEmpty
                  ? "Agent testing"
                  : "Agent testing \(completed)/\(journey.steps.count)"
              )
            } icon: {
              Image(systemName: journey.status == .passed ? "checkmark.circle.fill" : "scope")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(journey.status == .failed ? Studio.warning : Studio.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Studio.accentSoft)
            .clipShape(Capsule())
            .help(journey.goal)
          }
          Spacer()
          Button(action: model.openSimulator) {
            Label("Open Simulator", systemImage: "arrow.up.right.square")
              .font(.system(size: 11, weight: .medium))
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(model.preflight?.isFullXcode != true)
          .help("Open Apple's separate Simulator window")
          Button(action: model.refreshApp) {
            Label("Refresh", systemImage: "arrow.clockwise")
              .font(.system(size: 11, weight: .medium))
              .frame(minHeight: 32)
          }
          .buttonStyle(.plain)
          .disabled(model.selectedTarget == nil || model.isBusy)
          .help("Relaunch the installed app and capture a fresh screenshot")
          Menu {
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
        .frame(height: 52)

        HStack(spacing: 0) {
          ScrollView([.horizontal, .vertical]) {
            DevicePreview(height: fittedDeviceHeight * previewZoom)
              .padding(.horizontal, 22)
              .padding(.vertical, 14)
              .frame(
                minWidth: max(0, previewViewportWidth - 44),
                minHeight: max(0, geometry.size.height - 116), alignment: .top)
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
          previewInteractionStatus
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
      }
    }
    .background(Studio.surface)
    .clipShape(RoundedRectangle(cornerRadius: Studio.panelRadius, style: .continuous))
    .shadow(color: .black.opacity(0.035), radius: 16, y: 7)
  }

  private var appearanceControls: some View {
    HStack(spacing: 2) {
      Image(systemName: "sun.max").foregroundStyle(Studio.secondary).frame(width: 30)
      appearanceButton(.light, title: "Light")
      appearanceButton(.dark, title: "Dark")
      Divider().frame(height: 20).padding(.horizontal, 6)
      Image(systemName: "iphone").foregroundStyle(Studio.secondary)
      Text("Portrait").font(.system(size: 11, weight: .medium)).fixedSize()
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

  private var scale: CGFloat { height / 650 }
  private var width: CGFloat { height * 306 / 650 }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 52 * scale, style: .continuous)
        .fill(Color(red: 0.08, green: 0.085, blue: 0.095))
        .shadow(color: .black.opacity(0.22), radius: 18, y: 9)
      RoundedRectangle(cornerRadius: 47 * scale, style: .continuous)
        .stroke(Color.white.opacity(0.32), lineWidth: max(1, 2 * scale)).padding(4 * scale)
      if let title = model.appOperation.title, let detail = model.appOperation.detail {
        deviceOperation(title: title, detail: detail)
      } else if model.designPreview {
        SyntheticProfilePreview()
          .clipShape(RoundedRectangle(cornerRadius: 45 * scale, style: .continuous))
          .padding(8 * scale)
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
    .frame(width: width, height: height)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      model.currentScreenshot == nil ? "No app screenshot" : "Latest app screenshot")
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
      return "Generate the native iOS workspace once; Operate will detect it automatically."
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
    VStack(spacing: 5) {
      paletteButton("list.bullet.rectangle", help: "Inspect accessibility hierarchy") {
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

      paletteButton("checkmark.seal", help: "Assert that the selected element is present") {
        model.assertSelectedElement()
      }
      .disabled(!hasDeterministicSelection)

      if automationAvailable {
        Image(systemName: "checkmark.shield.fill")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(Studio.success)
          .frame(width: 42, height: 24)
          .help("Semantic interaction is ready")
      } else {
        Button(action: model.setupWebDriverAgent) {
          Image(systemName: "lock.open")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(
              model.wdaStatus.availability == .setupRequired ? Studio.accent : Studio.tertiary
            )
            .frame(width: 42, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(model.wdaStatus.availability != .setupRequired || model.isBusy)
        .help(model.wdaStatus.detail)
      }
    }
    .padding(6)
    .background(Studio.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
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
      Image(systemName: symbol).font(.system(size: 17, weight: .regular)).frame(
        width: 42, height: 42
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
  @State private var selectedEvidence: Evidence?

  var body: some View {
    VStack(spacing: 12) {
      VStack(spacing: 0) {
        HStack {
          Text("Verify").font(.system(size: 12, weight: .semibold)).foregroundStyle(Studio.accent)
          Spacer()
          Text("Generation \(model.generation)").font(.system(size: 10).monospacedDigit())
            .foregroundStyle(Studio.secondary)
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        Divider().overlay(Studio.separator)

        HStack(spacing: 14) {
          VerificationGlyph(status: summaryStatus, size: 42)
          VStack(alignment: .leading, spacing: 4) {
            Text(summaryTitle).font(.system(size: 18, weight: .bold))
            Text(summaryDetail).font(.system(size: 11)).foregroundStyle(Studio.secondary)
          }
          Spacer()
        }
        .padding(20)

        Divider().overlay(Studio.separator)
        ForEach(checks, id: \.title) { check in
          VerificationRow(check: check)
          if check.title != checks.last?.title { Divider().overlay(Studio.separator) }
        }
      }
      .background(Studio.surface)
      .clipShape(RoundedRectangle(cornerRadius: Studio.panelRadius, style: .continuous))
      .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
      .fixedSize(horizontal: false, vertical: true)

      VStack(spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Evidence").font(.system(size: 12, weight: .semibold))
            Text("Machine-recorded proof · manual preview actions are excluded · click to inspect")
              .font(.system(size: 9.5))
              .foregroundStyle(Studio.secondary)
              .lineLimit(1)
          }
          Spacer()
          Text(model.verificationEvidence.isEmpty ? "No proof" : "\(model.verificationEvidence.count) artifacts")
            .font(.system(size: 11)).foregroundStyle(Studio.accent)
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
        Divider().overlay(Studio.separator)
        if model.verificationEvidence.isEmpty {
          VStack(spacing: 10) {
            Image(systemName: "checklist.unchecked").font(.system(size: 24, weight: .light))
              .foregroundStyle(Studio.tertiary)
            Text(
              "Manual preview actions are exploratory, not verification proof. Capture a stable screenshot or run an assertion."
            )
              .font(.system(size: 11)).foregroundStyle(Studio.secondary)
              .multilineTextAlignment(.center)
              .frame(maxWidth: 280)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(Array(model.verificationEvidence.reversed())) { evidence in
                EvidenceRow(evidence: evidence) { selectedEvidence = evidence }
                if evidence.id != model.verificationEvidence.first?.id {
                  Divider().overlay(Studio.separator)
                }
              }
            }
          }
          .scrollIndicators(.visible)
        }
      }
      .frame(maxHeight: .infinity, alignment: .top)
      .background(Studio.surface)
      .clipShape(RoundedRectangle(cornerRadius: Studio.panelRadius, style: .continuous))
      .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
      .popover(item: $selectedEvidence, arrowEdge: .trailing) { evidence in
        EvidenceArtifactInspector(evidence: evidence)
      }
    }
  }

  private var checks: [VerificationCheck] {
    [
      check("Build", kind: .build, waiting: "Waiting for a fresh build"),
      check("Launch", kind: .launch, waiting: "Waiting for app launch"),
      check(
        "UI interaction", kind: .uiAssertion,
        waiting: model.requiresUIVerification
          ? (model.isSemanticAutomationReady
            ? "Waiting for a deterministic UI assertion" : "WDA compatibility setup required")
          : "Optional until an editable task requires UI verification"),
      check("Screenshot", kind: .screenshot, waiting: "Waiting for current screenshot"),
    ]
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

  private var summaryStatus: VerificationCheck.Status {
    switch model.verificationReport?.status {
    case .verified: .passed
    case .failed: .failed
    case .blocked: .blocked
    case .partiallyVerified, nil: .waiting
    }
  }
  private var summaryTitle: String {
    switch model.verificationReport?.status {
    case .verified: "Verified"
    case .failed: "Verification failed"
    case .blocked: "Verification blocked"
    case .partiallyVerified: "Partially verified"
    case nil: "No current verification"
    }
  }
  private var summaryDetail: String {
    guard let report = model.verificationReport else {
      return "Run the app to collect machine-recorded evidence."
    }
    if report.missing.isEmpty { return "Evidence is current for generation \(model.generation)." }
    return report.missing.first.map { "Missing: \($0)" }
      ?? "Additional evidence is required."
  }
}

private struct VerificationCheck {
  enum Status { case passed, failed, waiting, blocked, optional }
  var title: String
  var detail: String
  var status: Status
}

private struct VerificationRow: View {
  let check: VerificationCheck
  var body: some View {
    HStack(spacing: 12) {
      VerificationGlyph(status: check.status, size: 22)
      VStack(alignment: .leading, spacing: 4) {
        Text(check.title).font(.system(size: 13, weight: .semibold))
        Text(check.detail).font(.system(size: 11)).foregroundStyle(Studio.secondary).lineLimit(2)
      }
      Spacer()
      Text(statusText).font(.system(size: 10, weight: .medium)).foregroundStyle(statusColor)
    }
    .padding(.horizontal, 20)
    .frame(minHeight: 70)
  }
  private var statusText: String {
    switch check.status {
    case .passed: "Fresh"
    case .failed: "Failed"
    case .waiting: "Waiting"
    case .blocked: "Blocked"
    case .optional: "Optional"
    }
  }
  private var statusColor: Color {
    switch check.status {
    case .passed: Studio.success
    case .failed: .red
    case .waiting: Studio.secondary
    case .blocked: Studio.warning
    case .optional: Studio.secondary
    }
  }
}

private struct VerificationGlyph: View {
  let status: VerificationCheck.Status
  var size: CGFloat = 22
  var body: some View {
    ZStack {
      Circle().fill(fill).frame(width: size, height: size)
      Image(systemName: symbol).font(.system(size: size * 0.48, weight: .bold)).foregroundStyle(
        foreground)
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
    }
  }
  private var foreground: Color {
    switch status {
    case .passed, .failed: .white
    case .waiting: Studio.accent
    case .blocked: Studio.warning
    case .optional: Studio.secondary
    }
  }
  private var symbol: String {
    switch status {
    case .passed: "checkmark"
    case .failed: "xmark"
    case .waiting: "clock"
    case .blocked: "lock"
    case .optional: "minus"
    }
  }
  private var label: String {
    switch status {
    case .passed: "Passed"
    case .failed: "Failed"
    case .waiting: "Waiting"
    case .blocked: "Blocked"
    case .optional: "Optional"
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

private struct TaskActionBar: View {
  @EnvironmentObject var model: AppModel
  var body: some View {
    HStack {
      Spacer().frame(width: 88)
      Button(action: showChanges) {
        HStack(spacing: 10) {
          Image(systemName: "shippingbox.fill").foregroundStyle(Studio.accent)
          Text(
            "\(model.changedFileCount) \(model.changedFileCount == 1 ? "file" : "files") changed"
          )
          .font(.system(size: 12, weight: .semibold)).monospacedDigit()
          Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Studio.secondary)
        }
      }
      .buttonStyle(.plain)
      .disabled(model.activeWorktree == nil)
      Spacer()
      Button("Discard Task", action: model.discardTask)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(model.activeWorktree == nil)
      Button(action: reviewAction) {
        HStack(spacing: 22) {
          Text(model.proposedChanges.isEmpty ? "Review Changes" : "Apply Changes")
          Divider().overlay(Color.white.opacity(0.25)).frame(height: 42)
          Image(systemName: "arrow.right")
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(height: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white)
      .background(
        model.activeWorktree == nil ? Studio.tertiary.opacity(0.32) : Studio.accent
      )
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .disabled(model.activeWorktree == nil)
    }
    .padding(.horizontal, 20)
    .frame(height: 76)
    .background(Studio.surface)
  }
  private func reviewAction() {
    if model.proposedChanges.isEmpty {
      model.reviewChanges()
      model.section = .git
    } else {
      model.applyAll()
    }
  }
  private func showChanges() {
    if model.proposedChanges.isEmpty { model.reviewChanges() }
    model.section = .git
  }
}

private struct SyntheticProfilePreview: View {
  var body: some View {
    ZStack {
      Color(red: 0.055, green: 0.065, blue: 0.075)
      VStack(spacing: 0) {
        Text("SYNTHETIC UI FIXTURE")
          .font(.system(size: 8, weight: .semibold)).tracking(0.8)
          .foregroundStyle(.white.opacity(0.45)).padding(.top, 38)
        Text("Profile").font(.system(size: 17, weight: .bold)).foregroundStyle(.white).padding(
          .top, 8)
        Circle().fill(Color(red: 0.25, green: 0.35, blue: 0.48)).frame(width: 84, height: 84)
          .overlay(
            Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(
              .white.opacity(0.9))
          )
          .padding(.top, 20)
        Text("Sarah Chen").font(.system(size: 18, weight: .bold)).foregroundStyle(.white).padding(
          .top, 10)
        Text("sarah@example.com").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
        VStack(spacing: 8) {
          SyntheticProfileRow(
            symbol: "person.crop.circle", title: "Edit Profile", detail: "Name, photo, bio")
          SyntheticProfileRow(
            symbol: "gearshape", title: "Settings", detail: "Preferences and more")
          SyntheticProfileRow(symbol: "moon", title: "Appearance", detail: "Dark")
          SyntheticProfileRow(symbol: "info.circle", title: "About", detail: "Version and support")
        }
        .padding(.horizontal, 18).padding(.top, 20)
        Spacer()
        HStack {
          ForEach(["house", "suitcase", "envelope", "person"], id: \.self) { symbol in
            Image(systemName: symbol).frame(maxWidth: .infinity)
          }
        }
        .font(.system(size: 17)).foregroundStyle(.white.opacity(0.72)).padding(.horizontal, 16)
        .padding(.bottom, 22)
      }
    }
  }
}

private struct SyntheticProfileRow: View {
  let symbol: String
  let title: String
  let detail: String
  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol).font(.system(size: 15)).frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 11, weight: .medium))
        Text(detail).font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
      }
      Spacer()
      Image(systemName: "chevron.right").font(.system(size: 9))
    }
    .foregroundStyle(.white).padding(.horizontal, 12).frame(height: 48)
    .background(Color.white.opacity(0.065)).clipShape(RoundedRectangle(cornerRadius: 9))
  }
}

private struct CodeWorkspace: View {
  @EnvironmentObject var model: AppModel
  var body: some View {
    HStack(spacing: 0) {
      FileBrowser().frame(width: 270)
      Divider().overlay(Studio.separator)
      VStack(spacing: 0) {
        HStack {
          Text(model.selectedFile?.lastPathComponent ?? "Code")
            .font(.system(size: 12, weight: .semibold))
          Spacer()
          Text(model.activeWorktree == nil ? "Read only" : "Task worktree")
            .font(.system(size: 10)).foregroundStyle(Studio.secondary)
          Button("Save", action: model.saveFile).disabled(
            model.selectedFile == nil || model.activeWorktree == nil)
        }
        .padding(.horizontal, 16).frame(height: 48).background(Studio.surface)
        Divider().overlay(Studio.separator)
        if model.selectedFile == nil {
          WorkspaceEmpty(
            symbol: "doc.text.magnifyingglass", title: "Select a source file",
            detail:
              "The native editor supports line numbers, syntax color, find, undo, and save inside a task worktree."
          )
        } else {
          CodeEditor(text: $model.source, readOnly: model.activeWorktree == nil)
        }
      }
    }
  }
}

private struct FilesWorkspace: View {
  @EnvironmentObject var model: AppModel
  var body: some View {
    HStack(spacing: 0) {
      FileBrowser().frame(width: 300)
      Divider().overlay(Studio.separator)
      WorkspaceEmpty(
        symbol: "folder", title: model.repository?.lastPathComponent ?? "No repository",
        detail: model.repository?.path ?? "Open a project to inspect its files.")
    }
  }
}

private struct FileBrowser: View {
  @EnvironmentObject var model: AppModel
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(model.activeWorktree == nil ? "Repository" : "Task Files")
          .font(.system(size: 12, weight: .semibold))
        Spacer()
        Button(action: model.chooseRepository) { Image(systemName: "folder.badge.plus") }
          .buttonStyle(.plain).foregroundStyle(Studio.accent)
      }
      .padding(.horizontal, 16).frame(height: 48)
      Divider().overlay(Studio.separator)
      if model.files.isEmpty {
        WorkspaceEmpty(
          symbol: "folder", title: "No files", detail: "Open a repository to browse files.")
      } else {
        ScrollView {
          OutlineGroup(model.files, children: \.children) { node in
            Button {
              model.selectFile(node.url)
            } label: {
              HStack(spacing: 7) {
                Image(systemName: node.children == nil ? fileSymbol(node.name) : "folder")
                  .foregroundStyle(node.children == nil ? Studio.secondary : Studio.accent)
                Text(node.name).lineLimit(1)
                Spacer()
              }
              .font(.system(size: 11))
              .frame(height: 26)
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
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Review Changes").font(.system(size: 18, weight: .bold))
          Text(
            "Compared with the exact task baseline; the original checkout is never overwritten on conflict."
          )
          .font(.system(size: 11)).foregroundStyle(Studio.secondary)
        }
        Spacer()
        Button("Refresh", action: model.reviewChanges)
      }
      .padding(.horizontal, 24).frame(height: 72).background(Studio.surface)
      Divider().overlay(Studio.separator)
      if model.proposedChanges.isEmpty {
        WorkspaceEmpty(
          symbol: "arrow.triangle.branch", title: "No proposed changes",
          detail: "Create an isolated task or refresh the baseline-relative change set.")
      } else {
        ScrollView {
          LazyVStack(spacing: 1) {
            ForEach(model.proposedChanges) { change in
              HStack(spacing: 12) {
                Text(change.kind.rawValue.uppercased())
                  .font(.system(size: 9, weight: .bold).monospaced())
                  .foregroundStyle(changeColor(change.kind)).frame(width: 62, alignment: .leading)
                Text(change.path).font(.system(size: 12))
                Spacer()
                if change.binary {
                  Text("Binary").font(.system(size: 10)).foregroundStyle(Studio.warning)
                }
              }
              .padding(.horizontal, 24).frame(height: 48).background(Studio.surface)
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
              .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
                Color.orange.opacity(0.08))
            }
          }
          .padding(20)
        }
      }
    }
  }
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
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("Settings").font(.system(size: 24, weight: .bold))
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
      .padding(32)
      .frame(maxWidth: 900, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
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
        .frame(width: 22, height: 22)
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
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(
        Studio.tertiary)
      Text(title).font(.system(size: 16, weight: .semibold))
      Text(detail).font(.system(size: 11)).foregroundStyle(Studio.secondary).multilineTextAlignment(
        .center
      )
      .frame(maxWidth: 460)
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
  var body: some View {
    Group {
      switch state {
      case .complete: Image(systemName: "checkmark.circle.fill").foregroundStyle(Studio.success)
      case .active: Circle().fill(Studio.accent).frame(width: 9, height: 9)
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
