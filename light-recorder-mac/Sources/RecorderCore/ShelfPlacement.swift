import CoreGraphics

public enum ShelfPlacement {
    public enum Side { case left, right }

    public static func edge(at point: CGPoint, in screen: CGRect, threshold: CGFloat = 26) -> Side? {
        guard point.y >= screen.minY, point.y <= screen.maxY else { return nil }
        if point.x <= screen.minX + threshold { return .left }
        if point.x >= screen.maxX - threshold { return .right }
        return nil
    }

    public static func frame(size: CGSize, near anchor: CGPoint, in screen: CGRect, edge: Side? = nil) -> CGRect {
        let x: CGFloat
        switch edge {
        case .left: x = screen.minX
        case .right: x = screen.maxX - size.width
        case nil: x = max(screen.minX + 6, min(anchor.x - size.width / 2, screen.maxX - size.width - 6))
        }
        let y = max(screen.minY + 6, min(anchor.y - size.height / 2, screen.maxY - size.height - 6))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
