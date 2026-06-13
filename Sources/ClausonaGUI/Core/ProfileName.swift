public enum ProfileName {
    /// Mirrors clausona's accepted names; doubles as the shell-safety gate for handoffs.
    public static func isValid(_ name: String) -> Bool {
        !name.isEmpty && name.wholeMatch(of: /[a-z0-9-]+/) != nil
    }
}
