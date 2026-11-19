import CoreGraphics
import Foundation
import VisualMesh

/// Sizes and behaviour of a `MeshCanvas`. All lengths are in mesh units
/// (points at zoom 1).
public struct MeshCanvasStyle: Sendable {
    public var minimumNodeSize = CGSize(width: 180, height: 60)
    public var portDiameter: CGFloat = 26
    public var portSpacing: CGFloat = 40
    public var gridSpacing: CGFloat = 30
    public var snapToGrid = false
    public var zoomRange: ClosedRange<CGFloat> = 0.25 ... 3

    public init() {}
}

/// Pure geometry shared by drawing and hit-testing.
///
/// Input ports sit above a node; output and bidirectional ports sit below it.
struct MeshCanvasGeometry {
    var style: MeshCanvasStyle

    func nodeSize<P>(_ node: GraphNode<P>) -> CGSize {
        let top = node.ports.filter(isTopPort).count
        let bottom = node.ports.count - top
        let width = max(style.minimumNodeSize.width,
                        CGFloat(max(top, bottom, 1)) * style.portSpacing + 60)
        return CGSize(width: width, height: style.minimumNodeSize.height)
    }

    func isTopPort(_ port: GraphPort) -> Bool {
        port.direction == .input
    }

    /// Offset of a port's centre from its node's centre, in mesh units.
    func portOffset<P>(_ port: GraphPort, in node: GraphNode<P>) -> CGSize {
        let top = isTopPort(port)
        let row = node.ports.filter { isTopPort($0) == top }
        let index = CGFloat(row.firstIndex { $0.id == port.id } ?? 0)
        let x = (index - CGFloat(row.count - 1) / 2) * style.portSpacing
        let y = (nodeSize(node).height / 2 + style.portDiameter / 2) * (top ? -1 : 1)
        return CGSize(width: x, height: y)
    }

    func portPosition<P>(_ port: GraphPort, in node: GraphNode<P>, at nodePosition: CGPoint) -> CGPoint {
        let offset = portOffset(port, in: node)
        return CGPoint(x: nodePosition.x + offset.width, y: nodePosition.y + offset.height)
    }

    /// Control points for a wire that leaves each port away from its node.
    func wireControlPoints(from start: CGPoint, startIsTop: Bool,
                           to end: CGPoint, endIsTop: Bool) -> (CGPoint, CGPoint) {
        let bend = max(abs(end.y - start.y) * 0.55, 60)
        let c1 = CGPoint(x: start.x, y: start.y + (startIsTop ? -bend : bend))
        let c2 = CGPoint(x: end.x, y: end.y + (endIsTop ? -bend : bend))
        return (c1, c2)
    }

    static func cubic(_ t: CGFloat, _ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p1.x,
                       y: a * p0.y + b * c1.y + c * c2.y + d * p1.y)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Distance from a point to a line segment.
    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(p, a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return distance(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }
}
