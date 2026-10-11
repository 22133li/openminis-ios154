import SwiftUI

/// Settings → Auto-Compact: the global automatic context-compaction
/// switch plus the user-defined context budget. The budget is a soft cap —
/// the effective window is always min(model window, group limit, budget).
struct AutoCompactSettingsView: View {
    @AppStorage("autoCompactOnThreshold") private var autoCompactEnabled = false
    @AppStorage("globalContextBudgetTokens") private var budgetTokens: Int = ContextBudgetStore.defaultBudgetTokens

    private static let tokenFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    static func tokenString(_ n: Int) -> String {
        let s = tokenFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
        return "\(s) Token"
    }

    private var triggerTokens: Int {
        Int(Double(budgetTokens) * ContextBudgetStore.compactTriggerFraction)
    }

    var body: some View {
        List {
            Section {
                Toggle("Enable Auto-Compact", isOn: $autoCompactEnabled)
            } footer: {
                Text("Auto-Compact is a global setting and can be turned off anytime.")
            }

            Section {
                NavigationLink {
                    AutoCompactBudgetPickerView(budgetTokens: $budgetTokens)
                } label: {
                    HStack {
                        Text("Context Budget")
                        Spacer()
                        Text(Self.tokenString(budgetTokens))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Context Budget")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Compact trigger (current model or budget): \(Self.tokenString(triggerTokens))")
                    Text("The weaker model / group limit wins; this budget never changes or raises a model's context window.")
                }
            }

            Section("How It Works") {
                Text("The budget is a soft target — fixed prompts and the current turn may push a compacted request over budget.")
                Text("Turning off Auto-Compact does not disable the existing near-window safety protection.")
                Text("Compaction uses history summaries and may lose detail; the original chat history is kept.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Auto-Compact")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Budget presets

private struct AutoCompactBudgetPickerView: View {
    @Binding var budgetTokens: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(ContextBudgetStore.budgetPresets, id: \.self) { preset in
            Button {
                budgetTokens = preset
                dismiss()
            } label: {
                HStack {
                    Text(AutoCompactSettingsView.tokenString(preset))
                        .foregroundStyle(.primary)
                    Spacer()
                    if preset == budgetTokens {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Context Budget")
        .navigationBarTitleDisplayMode(.inline)
    }
}
