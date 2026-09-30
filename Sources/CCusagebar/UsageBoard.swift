import AppKit
import SwiftUI

enum ConnectionHealth: Equatable {
    case ok
    case working
    case degraded
    case error
}

struct ProviderUsageState: Equatable {
    var snapshot: UsageSnapshot?
    var checkedAt: Date?
    var status: String
    var health: ConnectionHealth
}

final class UsageBoardModel: ObservableObject {
    @Published var activeProvider: UsageProvider
    @Published var showBoth = false
    @Published private(set) var states: [UsageProvider: ProviderUsageState]

    /// 메뉴 막대에 그릴 앱, 왼쪽부터. 자동 전환이면 앞에 띄운 앱 하나.
    var shownProviders: [UsageProvider] {
        Self.shownProviders(showBoth: showBoth, active: activeProvider) { self.states[$0]?.snapshot != nil }
    }

    /// "둘 다 표시"는 두 앱 모두 값을 받은 뒤에만 Codex, Claude 순으로 나란히 그린다.
    static func shownProviders(
        showBoth: Bool,
        active: UsageProvider,
        hasSnapshot: (UsageProvider) -> Bool
    ) -> [UsageProvider] {
        guard showBoth else { return [active] }
        let both = UsageProvider.allCases.filter(hasSnapshot)
        return both.count == UsageProvider.allCases.count ? both : [active]
    }

    init(activeProvider: UsageProvider) {
        self.activeProvider = activeProvider
        states = Dictionary(uniqueKeysWithValues: UsageProvider.allCases.map {
            ($0, ProviderUsageState(
                snapshot: nil,
                checkedAt: nil,
                status: "\($0.displayName) 연결 중…",
                health: .working
            ))
        })
    }

    func state(for provider: UsageProvider) -> ProviderUsageState {
        states[provider]!
    }

    func update(_ provider: UsageProvider, _ change: (inout ProviderUsageState) -> Void) {
        var state = states[provider]!
        change(&state)
        states[provider] = state
    }
}

// MARK: - Views

struct UsageBoardView: View {
    static let width: CGFloat = 600

    @ObservedObject var model: UsageBoardModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(alignment: .top, spacing: 10) {
                ForEach(UsageProvider.allCases, id: \.self) { provider in
                    ProviderCard(
                        provider: provider,
                        state: model.state(for: provider),
                        isActive: model.shownProviders.contains(provider),
                        now: context.date
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: Self.width)
        }
    }
}

private struct ProviderCard: View {
    let provider: UsageProvider
    let state: ProviderUsageState
    let isActive: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let snapshot = state.snapshot {
                summary(snapshot)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                        WindowRow(window: window, now: now)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("사용량 확인 중…")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            }

            Spacer(minLength: 0)
            Divider()
            footer
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isActive ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.08),
                              lineWidth: isActive ? 1.5 : 1)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            ProviderIconView(provider: provider)
            Text(provider.displayName)
                .font(.system(size: 14, weight: .semibold))
            if let plan = state.snapshot?.planType {
                Text(plan.capitalized)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            if isActive {
                Text("메뉴 막대 표시 중")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.accentColor)
            }
        }
    }

    private func summary(_ snapshot: UsageSnapshot) -> some View {
        let remaining = snapshot.overallRemainingPercent
        let limiting = snapshot.windows.min { $0.remainingPercent < $1.remainingPercent }
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(remaining)%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(UsageColor.level(remaining))
                Text("남음")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            if let limiting, snapshot.windows.count > 1 {
                Text("가장 적게 남은 \(limiting.label) 기준")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(UsageColor.health(state.health))
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
                Text(state.status)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if let checkedAt = state.checkedAt {
                    Text("확인 \(UsageFormat.time(checkedAt))")
                }
                if let fetchedAt = state.snapshot?.fetchedAt {
                    Text("값 기준 \(UsageFormat.time(fetchedAt))")
                }
            }
            .font(.system(size: 10))
            .monospacedDigit()
            .foregroundColor(.secondary.opacity(0.8))
        }
    }
}

private struct WindowRow: View {
    let window: UsageWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(window.remainingPercent)% 남음")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(UsageColor.level(window.remainingPercent))
                Text("· \(window.usedPercent)% 사용")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            RemainingBar(remainingPercent: window.remainingPercent)
            Text(resetText)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
    }

    private var resetText: String {
        guard let resetsAt = window.resetsAt else {
            return "초기화 시각 정보 없음"
        }
        return "\(UsageFormat.reset(resetsAt)) 초기화 · \(UsageFormat.relative(to: resetsAt, now: now))"
    }
}

private struct RemainingBar: View {
    let remainingPercent: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(UsageColor.level(remainingPercent))
                    .frame(width: proxy.size.width * CGFloat(remainingPercent) / 100)
            }
        }
        .frame(height: 6)
    }
}

private struct ProviderIconView: View {
    let provider: UsageProvider

    var body: some View {
        if let image = ProviderIconLoader.currentIcon(for: provider) {
            if provider == .claude {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .foregroundColor(UsageColor.claudeBrand)
                    .frame(width: 16, height: 16)
            } else {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
        }
    }
}

enum UsageColor {
    static let claudeBrand = Color(red: 0.85, green: 0.47, blue: 0.34)

    static func level(_ remainingPercent: Int) -> Color {
        switch remainingPercent {
        case 50...:
            return .green
        case 20..<50:
            return .orange
        default:
            return .red
        }
    }

    static func health(_ health: ConnectionHealth) -> Color {
        switch health {
        case .ok:
            return .green
        case .working:
            return .gray
        case .degraded:
            return .orange
        case .error:
            return .red
        }
    }
}

enum UsageFormat {
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func reset(_ date: Date) -> String {
        resetFormatter.string(from: date)
    }

    static func relative(to date: Date, now: Date) -> String {
        let minutes = Int(date.timeIntervalSince(now) / 60)
        guard minutes > 0 else { return "곧 초기화" }
        let days = minutes / 1_440
        let hours = (minutes % 1_440) / 60
        let mins = minutes % 60
        if days > 0 {
            return hours > 0 ? "\(days)일 \(hours)시간 후" : "\(days)일 후"
        }
        if hours > 0 {
            return mins > 0 ? "\(hours)시간 \(mins)분 후" : "\(hours)시간 후"
        }
        return "\(mins)분 후"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm:ss"
        return formatter
    }()

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 a h:mm"
        return formatter
    }()
}
