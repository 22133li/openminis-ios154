import Foundation

/// Global context-budget settings behind Settings → Auto-Compact.
///
/// The budget is a soft cap: the effective window is always
/// min(model native window, group limit, global budget) — a budget can
/// never raise a model's context window.
enum ContextBudgetStore {
    static let budgetKey = "globalContextBudgetTokens"
    static let autoCompactKey = "autoCompactOnThreshold"
    static let defaultBudgetTokens = 256_000
    /// Fraction of the window at which auto-compact triggers (mirrors
    /// ContextPolicy's 0.85).
    static let compactTriggerFraction = 0.85

    static let budgetPresets = [32_000, 64_000, 128_000, 256_000, 512_000, 1_000_000]

    static var globalBudgetTokens: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: budgetKey)
            return v > 0 ? v : defaultBudgetTokens
        }
        set { UserDefaults.standard.set(max(1_000, newValue), forKey: budgetKey) }
    }

    /// Live read of the auto-compact switch. Settings can flip this while a
    /// chat session's view model is alive, so decision points read it here
    /// instead of the view model's cached @Published copy.
    static var autoCompactEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoCompactKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoCompactKey) }
    }

    static var compactTriggerTokens: Int {
        Int(Double(globalBudgetTokens) * compactTriggerFraction)
    }
}
