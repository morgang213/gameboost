import SwiftUI
import AppKit

struct ProfilesView: View {
    @ObservedObject var store = ProfileStore.shared
    @ObservedObject var state = AppState.shared
    @State private var editing: GameProfile?
    @State private var showEditor = false
    @State private var showLibrary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Game profiles").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    showLibrary = true
                } label: { Label("Scan for games", systemImage: "sparkle.magnifyingglass") }
                Button {
                    pickGameAndAdd()
                } label: { Label("Add game", systemImage: "plus") }
            }
            .padding(.horizontal, 14).padding(.top, 14)

            IntroText("Profiles bundle a boost with a game launch — add a game, choose what happens on launch (free RAM, DND, pause Spotlight, FPS overlay), and one click boosts + launches it. Auto-restore reverts your settings when the game quits.")
                .padding(.horizontal, 14).padding(.vertical, 8)

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
        .sheet(isPresented: $showLibrary) {
            GameLibrarySheet { showLibrary = false }
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
                    Toggle("Show Metal FPS overlay", isOn: $profile.metalHUD)
                        .help("Sets MTL_HUD_ENABLED=1 so Metal-based games show Apple's built-in FPS / frame-time HUD.")
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

struct GameLibrarySheet: View {
    @ObservedObject var store = ProfileStore.shared
    let onClose: () -> Void
    @State private var games: [DiscoveredGame] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Discovered games").font(.headline)
                Spacer()
                Button("Done") { onClose() }
            }
            Text("Found from your Steam library and game apps in Applications.")
                .font(.caption).foregroundColor(.secondary)

            if loading {
                HStack { ProgressView().controlSize(.small); Text("Scanning…").foregroundColor(.secondary) }
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if games.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 32)).foregroundColor(.secondary.opacity(0.5))
                    Text("No games detected").font(.subheadline)
                    Text("Steam games and apps tagged as Games will show up here. You can still add any app manually.")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200).padding()
            } else {
                ScrollView {
                    VStack(spacing: 8) { ForEach(games) { gameRow($0) } }
                }
                .frame(height: 320)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear(perform: scan)
    }

    private func scan() {
        loading = true
        DispatchQueue.global().async {
            let found = GameScanner.scan()
            DispatchQueue.main.async { games = found; loading = false }
        }
    }

    private func gameRow(_ g: DiscoveredGame) -> some View {
        let added = g.appPath != nil && store.profiles.contains { $0.appPath == g.appPath }
        return HStack(spacing: 10) {
            if let icon = g.icon {
                Image(nsImage: icon).resizable().frame(width: 30, height: 30)
            } else {
                Image(systemName: "gamecontroller").font(.system(size: 22)).foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(g.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(g.source).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if added {
                Label("Added", systemImage: "checkmark").font(.caption).foregroundColor(.secondary)
            } else if let path = g.appPath {
                Button("Add") { store.upsert(GameProfile.new(appPath: path, name: g.name)) }
            } else {
                Text("No app found").font(.caption2).foregroundColor(.secondary)
                    .help("Couldn't locate a launchable .app for this game.")
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .cornerRadius(8)
    }
}
