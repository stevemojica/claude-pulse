import SwiftUI

struct SettingsView: View {
    @ObservedObject var updateManager: UpdateManager
    @AppStorage("pollInterval") private var pollInterval: Double = 60
    @AppStorage("alert50") private var alert50 = true
    @AppStorage("alert75") private var alert75 = true
    @AppStorage("alert90") private var alert90 = true
    @AppStorage("alert95") private var alert95 = true
    @AppStorage("accentColorName") private var accentColorName = "green"
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("soundVolume") private var soundVolume: Double = 0.5
    @AppStorage("barPosition") private var barPosition = "bottom"
    @Environment(\.dismiss) private var dismiss

    private let colorOptions = ["green", "blue", "purple", "orange", "teal"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.system(size: 13, weight: .bold))

            // Poll interval
            VStack(alignment: .leading, spacing: 4) {
                Text("Poll Interval: \(Int(pollInterval))s")
                    .font(.system(size: 11, weight: .medium))
                Slider(value: $pollInterval, in: 30...300, step: 30)
                Text("Min 30s to avoid API rate limiting")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }

            Divider()

            // Alert thresholds
            VStack(alignment: .leading, spacing: 6) {
                Text("Alert Thresholds")
                    .font(.system(size: 11, weight: .medium))
                Toggle("50% — halfway", isOn: $alert50)
                Toggle("75% — elevated", isOn: $alert75)
                Toggle("90% — approaching limit", isOn: $alert90)
                Toggle("95% — near limit", isOn: $alert95)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Divider()

            // Sound settings
            VStack(alignment: .leading, spacing: 6) {
                Text("Sound Effects")
                    .font(.system(size: 11, weight: .medium))
                Toggle("Enable sounds", isOn: $soundEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                if soundEnabled {
                    HStack {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Slider(value: $soundVolume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Divider()

            // Color theme
            VStack(alignment: .leading, spacing: 6) {
                Text("Accent Color")
                    .font(.system(size: 11, weight: .medium))
                HStack(spacing: 8) {
                    ForEach(colorOptions, id: \.self) { name in
                        Circle()
                            .fill(colorFor(name))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle().stroke(.primary.opacity(accentColorName == name ? 0.8 : 0), lineWidth: 2)
                            )
                            .onTapGesture { accentColorName = name }
                    }
                }
            }

            Divider()

            // Updates
            VStack(alignment: .leading, spacing: 6) {
                Text("Updates")
                    .font(.system(size: 11, weight: .medium))
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version \(updateManager.currentVersion)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        if updateManager.updateAvailable, let version = updateManager.latestVersion {
                            Text("v\(version) available")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.blue)
                        }
                    }
                    Spacer()
                    if updateManager.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Check for Updates") {
                        updateManager.checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(updateManager.isChecking)
                }

                // Result message
                if updateManager.showResult, let message = updateManager.resultMessage {
                    HStack(spacing: 6) {
                        Image(systemName: updateManager.updateAvailable ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(updateManager.updateAvailable ? .blue : .green)
                            .font(.system(size: 11))
                        Text(message)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if updateManager.updateAvailable {
                            Button("Download") {
                                updateManager.openDownloadPage()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                        }
                        Button(action: { updateManager.showResult = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(
                        (updateManager.updateAvailable ? Color.blue : Color.green).opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
            }

            Divider()

            // Hotkey info
            VStack(alignment: .leading, spacing: 4) {
                Text("Keyboard Shortcut")
                    .font(.system(size: 11, weight: .medium))
                Text("⌘⇧P — Toggle command bar")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Bar position
            VStack(alignment: .leading, spacing: 6) {
                Text("Bar Position")
                    .font(.system(size: 11, weight: .medium))
                Picker("", selection: $barPosition) {
                    Text("Top (Notch area)").tag("top")
                    Text("Bottom").tag("bottom")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(barPosition == "top"
                    ? "Bar appears below the notch or menu bar"
                    : "Bar appears above the Dock")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 300, height: 600)
    }

    private func colorFor(_ name: String) -> Color {
        switch name {
        case "green":  return .green
        case "blue":   return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "teal":   return .teal
        default:       return .green
        }
    }
}
