import Foundation

/// On this macOS generation the menu bar hosts status items inside Control
/// Center windows, and `NSPopover.show(relativeTo:of:)` places the popover
/// window with a constant offset from the real icon (verified with a minimal
/// stock-pattern reproducer — the misplacement is identical there). AppKit's
/// own `button.window` geometry IS correct, so we re-place the popover window
/// under the true button rect ourselves. Pure math, bottom-left coordinates,
/// unit-tested; applied only when the system got it wrong, so it is a no-op
/// once the OS bug is fixed.
public enum PopoverAnchor {
    public static let tolerance: CGFloat = 3

    public static func needsCorrection(popover: CGRect, buttonScreenRect: CGRect) -> Bool {
        abs(popover.midX - buttonScreenRect.midX) > tolerance
            || abs(popover.maxY - buttonScreenRect.minY) > tolerance
    }

    public static func correctedFrame(popover: CGRect, buttonScreenRect: CGRect, screen: CGRect) -> CGRect {
        var frame = popover
        frame.origin.x = buttonScreenRect.midX - frame.width / 2
        frame.origin.y = buttonScreenRect.minY - frame.height
        frame.origin.x = min(max(frame.origin.x, screen.minX), screen.maxX - frame.width)
        return frame
    }
}
