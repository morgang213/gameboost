import SwiftUI

struct GameSession: Codable, Identifiable {
    var id = UUID()
    let game: String
    let start: Date
    let end: Date
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

final class SessionStore: ObservableObject {
    static let shared = SessionStore()
    @Published private(set) var sessions: [GameSession] = []

    private let fileURL: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameBoost", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("sessions.json")
        load()
    }

    func add(game: String, start: Date, end: Date) {
        // Ignore accidental sub-30s blips (mis-launches, quick quits).
        guard end.timeIntervalSince(start) >= 30 else { return }
        sessions.append(GameSession(game: game, start: start, end: end))
        if sessions.count > 1000 { sessions.removeFirst(sessions.count - 1000) }
        save()
    }

    func clear() { sessions = []; save() }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([GameSession].self, from: data) else { return }
        sessions = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sessions) { try? data.write(to: fileURL) }
    }

    // MARK: Aggregates

    var totalTime: TimeInterval { sessions.reduce(0) { $0 + $1.duration } }

    var thisWeekTime: TimeInterval {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        return sessions.filter { $0.start >= cutoff }.reduce(0) { $0 + $1.duration }
    }

    /// Per-game totals, most-played first.
    var byGame: [(game: String, total: TimeInterval, sessions: Int)] {
        var totals: [String: (TimeInterval, Int)] = [:]
        for s in sessions {
            let cur = totals[s.game] ?? (0, 0)
            totals[s.game] = (cur.0 + s.duration, cur.1 + 1)
        }
        return totals.map { ($0.key, $0.value.0, $0.value.1) }
            .sorted { $0.1 > $1.1 }
    }

    var recent: [GameSession] { sessions.sorted { $0.start > $1.start } }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m" }
    return "\(total)s"
}

struct StatsView: View {
    @ObservedObject var store = SessionStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.sessions.isEmpty {
                    emptyState
                } else {
                    IntroText("Play time is logged automatically when you launch a game from a profile. Sessions under 30 seconds are ignored.")
                    HStack(spacing: 12) {
                        bigStat("Total played", formatDuration(store.totalTime), .purple)
                        bigStat("This week", formatDuration(store.thisWeekTime), .pink)
                        bigStat("Sessions", "\(store.sessions.count)", .cyan)
                    }
                    topGamesCard
                    recentCard
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
            Text("No play sessions yet").font(.headline)
            Text("Launch a game from a profile and GameBoost will log how long you play.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }

    private func bigStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .cornerRadius(10)
    }

    private var topGamesCard: some View {
        let games = store.byGame
        let maxTotal = games.map(\.total).max() ?? 1
        return card("Most played") {
            ForEach(games.prefix(8), id: \.game) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(row.game).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                        Text(formatDuration(row.total)).font(.caption.monospacedDigit()).foregroundColor(.secondary)
                    }
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * CGFloat(row.total / maxTotal)), height: 6)
                    }
                    .frame(height: 6)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var recentCard: some View {
        card("Recent sessions") {
            ForEach(store.recent.prefix(12)) { s in
                HStack {
                    Text(s.game).font(.system(size: 12)).lineLimit(1)
                    Spacer()
                    Text(formatDuration(s.duration)).font(.caption.monospacedDigit())
                    Text(s.start, style: .date).font(.caption2).foregroundColor(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .cornerRadius(10)
    }
}
