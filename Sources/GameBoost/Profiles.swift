import SwiftUI
import AppKit

struct ProfilesView: View {
    @ObservedObject var store = ProfileStore.shared
    @ObservedObject var state = AppState.shared
    @State private var editing: GameProfile?
    @State private var showEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Game profiles").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    pickGameAndAdd()
                } label: { Label("Add game", systemImage: "plus") }
            }
            .padding(14)

            if store.profiles.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(store.profiles) { profile in
                            profileRow(profile)
                        }
                    }
                    .padding(14)
                }
            }
            Spacer()
        }
        .sheet(isPresented: $showEditor) {
            if let editing {
                ProfileEditorView(profile: editing) { saved in
                    store.upsert(saved)
                    showEditor = false
                } onCancel: { showEditor = false }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
            Text("No game profiles yet").font(.headline)
            Text("Add a game to boost and launch it in one click.\nWhen it quits, GameBoost restores your settings.")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Add a game") { pickGameAndAdd() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func profileRow(_ profile: GameProfile) -> some View {
        HStack(spacing: 12) {
            if let icon = profile.icon {
                Image(nsImage: icon).resizable().frame(width: 38, height: 38)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .font(.system(size: 30)).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.system(size: 14, weight: .medium))
                Text(profile.summary).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button {
                AppState.shared.launchProfile(profile)
            } label: {
                Label("Launch", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.busy)

            Menu {
                Button("Edit…") { editing = profile; showEditor = true }
                Button("Delete", role: .destructive) { store.delete(profile) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .cornerRadius(10)
    }

    private func pickGameAndAdd() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose Game"
        if panel.runModal() == .OK, let url = panel.url {
            let name = url.deletingPathExtension().lastPathComponent
            editing = GameProfile.new(appPath: url.path, name: name)
            showEditor = true
        }
    }
}

struct ProfileEditorView: View {
    @State var profile: GameProfile
    let onSave: (GameProfile) -> Void
    let onCancel: () -> Void

    @State private var runningApps: [RunningApp] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let icon = profile.icon {
                    Image(nsImage: icon).resizable().frame(width: 44, height: 44)
                }
                VStack(alignment: .leading) {
                    TextField("Profile name", text: $profile.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                    Text(profile.appPath).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
            }

            GroupBox("When launching") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Free inactive memory (purge)", isOn: $profile.freeMemory)
                    Toggle("Pause Spotlight indexing", isOn: $profile.pauseSpotlight)
                    Toggle("Turn on Do Not Disturb", isOn: $profile.enableDND)
                    Divider()
                    Toggle("Auto-restore when the game quits", isOn: $profile.autoRestore)
                        .help("Resume Spotlight and turn off DND automatically when the game closes.")
                }
                .padding(6)
            }

            GroupBox("Quit these apps first") {
                if runningApps.isEmpty {
                    Text("No regular apps running.").font(.caption).foregroundColor(.secondary).padding(6)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(runningApps) { app in
                                if let bid = app.bundleID {
                                    Toggle(isOn: Binding(
                                        get: { profile.quitBundleIDs.contains(bid) },
                                        set: { on in
                                            if on { profile.quitBundleIDs.append(bid) }
                                            else { profile.quitBundleIDs.removeAll { $0 == bid } }
                                        })) {
                                        HStack(spacing: 6) {
                                            if let icon = app.icon {
                                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                                            }
                                            Text(app.name).font(.system(size: 12))
                                            Spacer()
                                            Text(String(format: "%.0f MB", app.memoryMB))
                                                .font(.caption2.monospacedDigit()).foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: 150)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                Button("Save") { onSave(profile) }
                    .buttonStyle(.borderedProminent)
                    .disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            runningApps = AppManager.runningApps().filter { $0.bundleID != nil && !AppManager.isProtected($0) }
        }
    }
}
