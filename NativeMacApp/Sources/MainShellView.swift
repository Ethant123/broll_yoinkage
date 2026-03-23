import SwiftUI
import AppKit

struct MainShellView: View {
    @ObservedObject var controller: AppController
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isProjectFieldFocused: Bool
    @State private var urlEditorDynamicHeight: CGFloat = 104

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 42)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        commandCard
                        queueCard
                    }
                    .frame(maxWidth: 840, alignment: .leading)
                    .padding(.top, 32)
                    .padding(.bottom, 36)
                    .padding(.horizontal, 28)
                }
            }
            .disabled(controller.isBootstrapVisible || controller.installPrompt != nil || controller.availableUpdate != nil)
            .blur(radius: (controller.isBootstrapVisible || controller.installPrompt != nil || controller.availableUpdate != nil) ? 12 : 0)

            VStack {
                HStack(alignment: .top) {
                    floatingThemeToggle
                    Spacer()
                }
                Spacer()
            }
            .padding(.top, 22)
            .padding(.leading, 18)

            if controller.isBootstrapVisible {
                bootstrapOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if controller.installPrompt != nil {
                installOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if let update = controller.availableUpdate {
                updateOverlay(update)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(minWidth: 1020, minHeight: 820)
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.08, green: 0.10, blue: 0.14), Color(red: 0.11, green: 0.14, blue: 0.20)]
                    : [Color(red: 0.93, green: 0.95, blue: 0.98), Color(red: 0.88, green: 0.91, blue: 0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.10))
                .frame(width: 320, height: 320)
                .blur(radius: 40)
                .offset(x: 360, y: -260)

            Circle()
                .fill(.white.opacity(colorScheme == .dark ? 0.06 : 0.18))
                .frame(width: 260, height: 260)
                .blur(radius: 34)
                .offset(x: -380, y: 260)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("B-Roll Downloader")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryText)

                HStack(spacing: 10) {
                    pill("YouTube", selected: true)
                    Text("Downloads to ~/Downloads/B-Roll")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(secondaryText)
                }

                Text(controller.queueStatusSummary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondaryText.opacity(0.92))
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    if case .available = controller.updateStatus {
                        controller.openLatestRelease()
                    } else {
                        controller.checkForUpdates()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if controller.updateStatus == .checking {
                            ProgressView()
                                .controlSize(.small)
                                .tint(updateStatusForeground)
                        }
                        Text(controller.updateStatusLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(updateStatusForeground)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(updateStatusBackground)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    metaBadge(controller.buildChannelLabel)
                    metaBadge("v\(controller.appVersionLabel)")
                }
            }
        }
    }

    private var commandCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    Spacer()

                    Toggle(isOn: Binding(
                        get: { controller.projectRequired },
                        set: { controller.setProjectRequired($0) }
                    )) {
                        Text("Project Name Required")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(primaryText)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                }

                if controller.projectRequired {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Project Name")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(secondaryText)

                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Enter project name", text: $controller.projectName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 15, weight: .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .background(controller.projectFieldInvalid ? softRed.opacity(0.14) : fieldBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(controller.projectFieldInvalid ? softRed : hairline, lineWidth: controller.projectFieldInvalid ? 2 : 1.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .modifier(ShakeEffect(trigger: controller.projectValidationToken))
                                .focused($isProjectFieldFocused)

                            if isProjectFieldFocused && controller.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let suggestions = filteredProjects
                                if !suggestions.isEmpty {
                                    VStack(spacing: 0) {
                                        ForEach(suggestions) { project in
                                            HStack(spacing: 10) {
                                                Button(project.name) {
                                                    controller.useRecentProject(named: project.name)
                                                }
                                                .buttonStyle(.plain)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(primaryText)
                                                .contentShape(Rectangle())

                                                Spacer()

                                                Button {
                                                    controller.removeRecentProject(named: project.name)
                                                } label: {
                                                    Image(systemName: "xmark")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundStyle(secondaryText)
                                                }
                                                .buttonStyle(.plain)
                                                .frame(width: 24, height: 24)
                                                .contentShape(Rectangle())
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 11)

                                            if project.id != suggestions.last?.id {
                                                Divider().overlay(hairline)
                                            }
                                        }
                                    }
                                    .background(cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(hairline, lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("YouTube URLs")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryText)

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(fieldBackground)

                        if controller.urlInput.isEmpty {
                            Text("Paste one YouTube URL per line")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(secondaryText.opacity(0.82))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                        }

                        AutoGrowingTextEditor(
                            text: $controller.urlInput,
                            dynamicHeight: $urlEditorDynamicHeight,
                            textColor: nsPrimaryTextColor,
                            font: .systemFont(ofSize: 14, weight: .medium)
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                    }
                    .frame(height: currentURLEditorHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(hairline, lineWidth: 1)
                    )
                    .onChange(of: controller.urlInput) { _, _ in
                        controller.updateInputSummary()
                    }

                    if controller.inputSummary.validCount > 0 || controller.inputSummary.duplicateCount > 0 || controller.inputSummary.invalidCount > 0 {
                        HStack(spacing: 12) {
                            if controller.inputSummary.validCount > 0 {
                                Text("\(controller.inputSummary.validCount) valid links")
                            }
                            if controller.inputSummary.duplicateCount > 0 {
                                Text("• \(controller.inputSummary.duplicateCount) duplicates skipped")
                            }
                            if controller.inputSummary.invalidCount > 0 {
                                Text("• \(controller.inputSummary.invalidCount) invalid ignored")
                            }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryText)
                    }
                }

                Button {
                    controller.submitBatch()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(controller.inputSummary.validCount > 0 ? activeBlue : buttonBackground)
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(controller.inputSummary.validCount > 0 ? activeBlue.opacity(0.0) : hairline, lineWidth: 1)
                        Text(controller.primaryButtonLabel)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(controller.inputSummary.validCount > 0 ? Color.white : primaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var queueCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Queue")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(primaryText)
                        Text("Smaller files start first, but the list stays in the order you added it.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(secondaryText)
                    }

                    Spacer()

                    Button(action: {
                        controller.clearQueue()
                    }) {
                        Text("Clear Queue")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(buttonBackground)
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if controller.queueItems.isEmpty {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(fieldBackground)
                        .frame(height: 116)
                        .overlay(
                            VStack(spacing: 8) {
                                Text("No downloads queued yet")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(primaryText)
                                Text("Start a batch above and the queue will fill in here.")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(secondaryText)
                            }
                        )
                } else {
                    VStack(spacing: 12) {
                        ForEach(controller.queueItems.sorted(by: { $0.visualOrder < $1.visualOrder })) { item in
                            QueueRow(item: item) {
                                controller.cancel(item.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private var floatingThemeToggle: some View {
        HStack(spacing: 6) {
            ForEach(ThemeMode.allCases, id: \.rawValue) { mode in
                Button {
                    controller.setThemeMode(mode)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(controller.themeMode == mode ? activeBlue : Color.clear)
                        Image(systemName: themeSymbol(for: mode))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(controller.themeMode == mode ? Color.white : primaryText)
                    }
                    .frame(width: 30, height: 30)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var bootstrapOverlay: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.24 : 0.16)
                .ignoresSafeArea()

            GlassCard {
                VStack(spacing: 18) {
                    Text("B-Roll Downloader")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(buttonBackground)
                        .clipShape(Capsule())

                    VStack(spacing: 8) {
                        Text(controller.bootstrap.title)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(primaryText)

                        Text(controller.bootstrap.detail)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(secondaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }

                    VStack(spacing: 10) {
                        ProgressView(value: controller.bootstrap.progress, total: 1)
                            .progressViewStyle(.linear)
                            .tint(activeBlue)
                            .scaleEffect(x: 1, y: 1.7, anchor: .center)
                            .frame(width: 320)

                        Text("\(Int((controller.bootstrap.progress * 100).rounded()))%")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(primaryText)
                    }

                    if controller.bootstrap.phase == .failed {
                        HStack(spacing: 10) {
                            Button(action: {
                                NSApp.terminate(nil)
                            }) {
                                Text("Quit")
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(buttonBackground)
                                    .clipShape(Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                controller.retryBootstrap()
                            }) {
                                Text("Retry")
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(activeBlue)
                                    .clipShape(Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 460)
            }
        }
    }

    private func updateOverlay(_ update: AppReleaseInfo) -> some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.20 : 0.12)
                .ignoresSafeArea()

            GlassCard {
                VStack(spacing: 18) {
                    Text("Update Available")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(primaryText)

                    Text("Version \(update.version) is available on GitHub Releases. You can keep working, or open the release page and update when you’re ready.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    HStack(spacing: 10) {
                        Button {
                            controller.dismissUpdatePrompt()
                        } label: {
                            Text("Later")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(primaryText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(buttonBackground)
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            controller.openLatestRelease()
                        } label: {
                            Text("Open Latest Release")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(activeBlue)
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 520)
            }
        }
    }

    private var installOverlay: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.20 : 0.12)
                .ignoresSafeArea()

            GlassCard {
                VStack(spacing: 18) {
                    Text("Move to Applications")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(primaryText)

                    Text(controller.installPromptDescription)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    if let message = controller.installErrorMessage, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(softRed)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }

                    HStack(spacing: 10) {
                        Button {
                            controller.dismissInstallPrompt()
                        } label: {
                            Text("Later")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(primaryText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(buttonBackground)
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.isInstallingApp)

                        Button {
                            controller.installCurrentAppToApplications()
                        } label: {
                            HStack(spacing: 8) {
                                if controller.isInstallingApp {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                }
                                Text(controller.isInstallingApp ? "Installing…" : "Install to Applications")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(activeBlue)
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.isInstallingApp)
                    }
                }
                .frame(width: 520)
            }
        }
    }

    private var currentURLEditorHeight: CGFloat {
        min(max(urlEditorDynamicHeight, 104), 244)
    }

    private var filteredProjects: [RecentProject] {
        Array(controller.recentProjects.prefix(6))
    }

    private func themeSymbol(for mode: ThemeMode) -> String {
        switch mode {
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        case .system:
            return "display"
        }
    }

    private func pill(_ label: String, selected: Bool) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(selected ? primaryText : secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? buttonBackground : Color.clear)
            .clipShape(Capsule())
    }

    private func metaBadge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(buttonBackground)
            .clipShape(Capsule())
    }

    private var updateStatusBackground: Color {
        switch controller.updateStatus {
        case .available:
            return activeBlue.opacity(0.18)
        case .failed:
            return softRed.opacity(0.16)
        default:
            return buttonBackground
        }
    }

    private var updateStatusForeground: Color {
        switch controller.updateStatus {
        case .available:
            return activeBlue
        case .failed:
            return softRed
        default:
            return primaryText
        }
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.12, green: 0.16, blue: 0.22)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.34, green: 0.39, blue: 0.48)
    }

    private var hairline: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.45)
    }

    private var buttonBackground: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.7)
    }

    private var fieldBackground: Color {
        colorScheme == .dark ? .white.opacity(0.07) : .white.opacity(0.62)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(red: 0.11, green: 0.14, blue: 0.19).opacity(0.84) : .white.opacity(0.72)
    }

    private var activeBlue: Color {
        Color(red: 0.22, green: 0.56, blue: 0.97)
    }

    private var softRed: Color {
        Color(red: 0.86, green: 0.48, blue: 0.50)
    }

    private var nsPrimaryTextColor: NSColor {
        colorScheme == .dark
            ? NSColor(calibratedWhite: 0.96, alpha: 1.0)
            : NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.22, alpha: 1.0)
    }
}

private struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(22)
            .background(colorScheme == .dark ? .white.opacity(0.06) : .white.opacity(0.52))
            .background(.regularMaterial.opacity(colorScheme == .dark ? 0.35 : 0.75))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.55), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 24, x: 0, y: 14)
    }
}

private struct QueueRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: QueueItem
    let onCancel: () -> Void
    @State private var isHoveringStatus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.serviceLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(primaryText.opacity(0.86))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(buttonBackground)
                            .clipShape(Capsule())

                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Text(item.channel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Button {
                    if item.status.isActive {
                        onCancel()
                    }
                } label: {
                    Text(statusText)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(statusForeground)
                        .frame(minWidth: 88)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(statusBackground)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringStatus = hovering
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(trackColor)

                    if visibleProgress > 0 {
                        Capsule()
                            .fill(fillColor)
                            .frame(width: max(10, proxy.size.width * visibleProgress))
                            .overlay(alignment: .leading) {
                                if item.status == .downloading || item.status == .converting {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [.clear, .white.opacity(colorScheme == .dark ? 0.26 : 0.46), .clear],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(24, proxy.size.width * visibleProgress))
                                }
                            }
                    }
                }
            }
            .frame(height: 8)

            if let errorMessage = item.errorMessage, item.status == .failed {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(rowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(rowStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statusText: String {
        if item.status.isActive && isHoveringStatus {
            return "Cancel"
        }
        if item.status == .converting && item.progress >= 0.995 {
            return "Finalizing"
        }
        if item.status == .downloading || item.status == .converting {
            return "\(item.status.label) \(Int((item.progress * 100).rounded()))%"
        }
        return item.status.label
    }

    private var visibleProgress: CGFloat {
        switch item.status {
        case .queued, .resolving:
            return 0
        default:
            return CGFloat(min(max(item.progress, 0), 1))
        }
    }

    private var rowBackground: Color {
        switch item.status {
        case .failed, .aborted:
            return softRed.opacity(colorScheme == .dark ? 0.10 : 0.16)
        default:
            return colorScheme == .dark ? .white.opacity(0.05) : .white.opacity(0.48)
        }
    }

    private var rowStroke: Color {
        switch item.status {
        case .failed, .aborted:
            return softRed.opacity(0.28)
        default:
            return colorScheme == .dark ? .white.opacity(0.07) : .white.opacity(0.5)
        }
    }

    private var statusBackground: Color {
        if item.status.isActive && isHoveringStatus {
            return softRed.opacity(0.18)
        }
        switch item.status {
        case .failed, .aborted:
            return softRed.opacity(0.16)
        case .complete:
            return Color.green.opacity(0.18)
        default:
            return buttonBackground
        }
    }

    private var statusForeground: Color {
        if item.status.isActive && isHoveringStatus {
            return softRed
        }
        switch item.status {
        case .failed, .aborted:
            return softRed
        case .complete:
            return Color.green.opacity(0.85)
        default:
            return primaryText
        }
    }

    private var trackColor: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06)
    }

    private var fillColor: Color {
        switch item.status {
        case .converting:
            return Color(red: 0.56, green: 0.42, blue: 0.93)
        case .failed, .aborted:
            return softRed.opacity(0.72)
        case .complete:
            return Color.green.opacity(0.72)
        default:
            return Color(red: 0.22, green: 0.56, blue: 0.97)
        }
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.12, green: 0.16, blue: 0.22)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.34, green: 0.39, blue: 0.48)
    }

    private var buttonBackground: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.68)
    }

    private var softRed: Color {
        Color(red: 0.86, green: 0.48, blue: 0.50)
    }
}

private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 11
    var shakesPerUnit = 4
    var animatableData: CGFloat

    init(trigger: Int) {
        animatableData = CGFloat(trigger)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
            y: 0
        ))
    }
}

private struct AutoGrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var dynamicHeight: CGFloat
    let textColor: NSColor
    let font: NSFont

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView()
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.string = text
        textView.layoutManager?.allowsNonContiguousLayout = false

        scrollView.documentView = textView
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            updateHeight(for: textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        DispatchQueue.main.async {
            updateHeight(for: textView)
        }
    }

    private func updateHeight(for textView: NSTextView) {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        layoutManager.ensureLayout(for: container)
        let usedRect = layoutManager.usedRect(for: container)
        let newHeight = min(max(usedRect.height + 28, 104), 244)
        if abs(dynamicHeight - newHeight) > 1 {
            dynamicHeight = newHeight
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoGrowingTextEditor
        weak var textView: NSTextView?

        init(_ parent: AutoGrowingTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            parent.updateHeight(for: textView)
        }
    }
}
