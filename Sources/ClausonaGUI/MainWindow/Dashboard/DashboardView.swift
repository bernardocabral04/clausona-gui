import Charts
import SwiftUI

struct DashboardView: View {
    let model: AppModel
    @Bindable var usage: UsageStore

    init(model: AppModel, usage: UsageStore) {
        self.model = model
        self._usage = Bindable(usage)
    }

    private struct Row: Identifiable {
        let name: String
        let totals: ProfileTotals
        let isActive: Bool
        var id: String { name }
    }

    private var rows: [Row] {
        usage.totalsByProfile()
            .map { Row(name: $0.key, totals: $0.value, isActive: $0.key == model.activeProfile) }
            .sorted { $0.totals.cost > $1.totals.cost }
    }

    var body: some View {
        let daily = usage.dailyCosts()
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Range", selection: $usage.range) {
                    ForEach(UsageRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Text("Total \(Formatting.cost(usage.grandTotalCost()))")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }

            if usage.loadFailed || usage.recordsByProfile.isEmpty {
                ContentUnavailableView(
                    "No usage data",
                    systemImage: "chart.bar.xaxis",
                    description: Text("clausona records usage as you run sessions."))
                    .frame(maxHeight: .infinity)
            } else if daily.isEmpty {
                ContentUnavailableView(
                    "No usage recorded in this range",
                    systemImage: "calendar.badge.minus")
                    .frame(maxHeight: .infinity)
            } else {
                Chart(daily) { entry in
                    BarMark(
                        x: .value("Day", entry.day, unit: .day),
                        y: .value("Cost", entry.cost))
                        .foregroundStyle(by: .value("Profile", entry.profile))
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let cost = value.as(Double.self) {
                                Text(Formatting.cost(cost))
                            }
                        }
                    }
                }
                .frame(minHeight: 200, maxHeight: 280)

                Table(rows) {
                    TableColumn("Profile") { row in
                        HStack(spacing: 4) {
                            Image(systemName: "arrowtriangle.right.fill")
                                .font(.system(size: 7))
                                .opacity(row.isActive ? 1 : 0)
                            Text(row.name)
                                .fontWeight(row.isActive ? .semibold : .regular)
                        }
                    }
                    TableColumn("Cost") { row in
                        Text(Formatting.cost(row.totals.cost)).monospacedDigit()
                    }
                    TableColumn("Input") { row in
                        Text(Formatting.tokens(row.totals.inputTokens)).monospacedDigit()
                    }
                    TableColumn("Output") { row in
                        Text(Formatting.tokens(row.totals.outputTokens)).monospacedDigit()
                    }
                }
            }
        }
        .padding()
        .navigationTitle("Dashboard")
    }
}
