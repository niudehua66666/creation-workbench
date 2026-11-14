import CoreGraphics

public enum RecordingHUDPlacement {
    // The capture rectangle starts at the display's top left. AppKit uses a
    // bottom-left origin, and a secondary display can have a negative origin.
    public static func screenRect(for captureRect: CGRect, on screen: CGRect) -> CGRect {
        CGRect(x: screen.minX + captureRect.minX, y: screen.maxY - captureRect.maxY,
               width: captureRect.width, height: captureRect.height)
    }

    public static func countdownFrame(size: CGSize, in visible: CGRect, selection: CGRect?) -> CGRect {
        let target = selection ?? visible
        return fit(CGRect(x: target.midX - size.width / 2, y: target.midY - size.height / 2,
                          width: size.width, height: size.height), in: visible)
    }

    public static func controlsFrame(size: CGSize, in visible: CGRect, selection: CGRect?) -> CGRect {
        let gap: CGFloat = 10
        let defaultY = visible.minY + gap
        let x = (selection ?? visible).midX - size.width / 2
        var y = defaultY
        if let selection {
            let below = selection.minY - gap - size.height
            let above = selection.maxY + gap
            if below >= visible.minY + margin {
                y = below
            } else if above + size.height <= visible.maxY - margin {
                y = above
            } else {
                // A tall selection can occupy the entire screen. Keep the stop
                // button reachable on this display even when neither side fits.
                y = defaultY
            }
        }
        return fit(CGRect(x: x, y: y, width: size.width, height: size.height), in: visible)
    }

    private static let margin: CGFloat = 6

    private static func fit(_ frame: CGRect, in visible: CGRect) -> CGRect {
        let x = max(visible.minX + margin, min(frame.minX, visible.maxX - frame.width - margin))
        let y = max(visible.minY + margin, min(frame.minY, visible.maxY - frame.height - margin))
        return CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
    }
}
