import CoreGraphics

public struct ShelfPresentation {
    public enum Appearance: Equatable {
        case hidden, ball, expanded, edge(ShelfPlacement.Side)
    }

    public private(set) var appearance: Appearance = .hidden
    private var isCapturing = false
    private var hasResult = false
    private var keepCollapsedWhenIdle = false

    public init() {}

    public mutating func setCaptureActive(_ active: Bool) {
        isCapturing = active
        if active && appearance == .hidden {
            appearance = .ball
        } else if !active && !hasResult && !keepCollapsedWhenIdle {
            appearance = .hidden
        }
    }

    public mutating func recordResult() { hasResult = true }

    public mutating func showShelf() {
        hasResult = true
        keepCollapsedWhenIdle = false
        appearance = .expanded
    }

    public mutating func open() {
        switch appearance {
        case .ball, .edge:
            keepCollapsedWhenIdle = false
            appearance = .expanded
        case .hidden, .expanded: break
        }
    }

    public mutating func dismiss() {
        if !isCapturing { hasResult = false }
        keepCollapsedWhenIdle = false
        appearance = isCapturing ? .ball : .hidden
    }

    public mutating func collapse(to edge: ShelfPlacement.Side) {
        guard appearance == .expanded else { return }
        keepCollapsedWhenIdle = true
        appearance = .edge(edge)
    }

    public mutating func drop(at edge: ShelfPlacement.Side?) {
        guard appearance != .hidden else { return }
        keepCollapsedWhenIdle = false
        if let edge {
            appearance = .edge(edge)
        } else if case .edge = appearance {
            appearance = .ball
        }
    }
}

public struct ShelfDrag {
    private let start: CGPoint
    private var hasDragged = false

    public init(start: CGPoint) { self.start = start }

    public mutating func translation(to point: CGPoint) -> CGPoint? {
        let offset = CGPoint(x: point.x - start.x, y: point.y - start.y)
        guard hasDragged || hypot(offset.x, offset.y) >= 4 else { return nil }
        hasDragged = true
        return offset
    }
}
