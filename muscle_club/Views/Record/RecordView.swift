import SwiftUI
import Charts

struct RecordView: View {
    @EnvironmentObject private var store: GymStore
    @State private var period: Period = .week

    enum Period: String, CaseIterable, Identifiable, Hashable {
        case week = "週間"
        case month = "月間"
        var id: String { rawValue }
    }

    private var stats: [GymStore.PeriodStat] {
        switch period {
        case .week: store.dailyStats(forWeekOf: Date())
        case .month: store.monthlyStats(monthsBack: 6)
        }
    }

    private var comparison: [(member: Member, count: Int, minutes: Int)] {
        switch period {
        case .week: store.memberComparison(forWeekOf: Date())
        case .month: store.memberComparison(forMonthOf: Date())
        }
    }

    var body: some View {
        AppScrollContainer {
            ScreenTitleView(
                eyebrow: "RECORD",
                title: "記録",
                subtitle: "ジムにいた時間と回数を振り返れます。"
            )

            Picker("期間", selection: $period) {
                ForEach(Period.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            TrendCard(period: period, stats: stats)
            ComparisonCard(period: period, items: comparison, currentUserID: store.currentUser.id)
        }
    }
}

private struct TrendCard: View {
    let period: RecordView.Period
    let stats: [GymStore.PeriodStat]

    private var totalMinutes: Int { stats.reduce(0) { $0 + $1.minutes } }
    private var totalCount: Int { stats.reduce(0) { $0 + $1.count } }

    var body: some View {
        CardView(title: period == .week ? "THIS WEEK" : "LAST 6 MONTHS") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("滞在時間")
                            .font(.caption)
                            .foregroundStyle(AppPalette.textSecondary)
                        Text(formattedMinutes(totalMinutes))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(AppPalette.textPrimary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("回数")
                            .font(.caption)
                            .foregroundStyle(AppPalette.textSecondary)
                        Text("\(totalCount)回")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(AppPalette.accentSecondary)
                    }
                }

                Chart(stats) { stat in
                    BarMark(
                        x: .value("期間", stat.label),
                        y: .value("分", stat.minutes)
                    )
                    .foregroundStyle(AppPalette.accentSecondary.gradient)
                    .cornerRadius(6)
                }
                .frame(height: 180)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(AppPalette.textSecondary)
                    }
                }
            }
        }
    }

    private func formattedMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remaining = minutes % 60
        return hours > 0 ? "\(hours)時間\(remaining)分" : "\(remaining)分"
    }
}

private struct ComparisonCard: View {
    let period: RecordView.Period
    let items: [(member: Member, count: Int, minutes: Int)]
    let currentUserID: UUID

    private var hasData: Bool {
        items.contains { $0.minutes > 0 || $0.count > 0 }
    }

    var body: some View {
        CardView(title: "COMPARISON") {
            VStack(alignment: .leading, spacing: 12) {
                Text(period == .week ? "今週のメンバー比較" : "今月のメンバー比較")
                    .font(.headline)
                    .foregroundStyle(AppPalette.textPrimary)

                if !hasData {
                    Text("まだ記録がありません。")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.textSecondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.member.id) { index, item in
                            ComparisonRow(
                                rank: index + 1,
                                member: item.member,
                                count: item.count,
                                minutes: item.minutes,
                                isCurrentUser: item.member.id == currentUserID
                            )

                            if index < items.count - 1 {
                                Divider().overlay(Color.white.opacity(0.08))
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ComparisonRow: View {
    let rank: Int
    let member: Member
    let count: Int
    let minutes: Int
    let isCurrentUser: Bool

    private var minutesLabel: String {
        let hours = minutes / 60
        let remaining = minutes % 60
        return hours > 0 ? "\(hours)時間\(remaining)分" : "\(remaining)分"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline.weight(.bold))
                .foregroundStyle(rank <= 3 ? AppPalette.warning : AppPalette.textSecondary)
                .frame(width: 24)

            AvatarView(member: member, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(isCurrentUser ? "\(member.name) (あなた)" : member.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                    .lineLimit(1)
                Text("\(count)回")
                    .font(.caption)
                    .foregroundStyle(AppPalette.textSecondary)
            }

            Spacer()

            AppBadgeView(text: minutesLabel, tint: isCurrentUser ? AppPalette.accentSecondary : AppPalette.accent)
        }
        .padding(.vertical, 10)
    }
}

#Preview {
    RecordView()
        .environmentObject(GymStore())
}
