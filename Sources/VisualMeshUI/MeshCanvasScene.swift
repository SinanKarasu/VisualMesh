import CoreGraphics
import Foundation
import VisualMesh

/// Screen-space view of a mesh for one frame: maps between mesh and screen
/// coordinates and performs hit tests. Shared by drawing and gestures so
/// they always agree.
@MainActor
struct MeshCanvasScene<NodePayload, EdgePayload> {
    let mesh: Mesh<NodePayload, EdgePayload>
    let layout: MeshLayout2D
    let geometry: MeshCanvasGeometry
    /// Screen position of the mesh origin.
    let origin: CGPoint
    let zoom: CGFloat

    struct Wire {
        var start: CGPoint
        var control1: CGPoint
        var control2: CGPoint
        var end: CGPoint

        func point(at t: CGFloat) -> CGPoint {
            MeshCanvasGeometry.cubic(t, start, control1, control2, end)
        }
    }

    func screen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x * zoom, y: origin.y + p.y * zoom)
    }

    func meshPoint(_ s: CGPoint) -> CGPoint {
        CGPoint(x: (s.x - origin.x) / zoom, y: (s.y - origin.y) / zoom)
    }

    func nodeCenter(_ node: GraphNode<NodePayload>) -> CGPoint {
        screen(layout.position(of: node.id))
    }

    /// Screen centre of a port and whether it sits on top of its node.
    func port(_ endpoint: GraphEndpoint) -> (center: CGPoint, isTop: Bool)? {
        guard let node = mesh.node(id: endpoint.nodeID),
              let port = node.port(id: endpoint.portID) else { return nil }
        let p = geometry.portPosition(port, in: node, at: layout.position(of: node.id))
        return (screen(p), geometry.isTopPort(port))
    }

    func wire(for edge: GraphEdge<EdgePayload>) -> Wire? {
        guard let a = port(GraphEndpoint(nodeID: edge.sourceNodeID, portID: edge.sourcePortID)),
              let b = port(GraphEndpoint(nodeID: edge.targetNodeID, portID: edge.targetPortID))
        else { return nil }
        let start = meshPoint(a.center), end = meshPoint(b.center)
        let (c1, c2) = geometry.wireControlPoints(from: start, startIsTop: a.isTop, to: end, endIsTop: b.isTop)
        return Wire(start: a.center, control1: screen(c1), control2: screen(c2), end: b.center)
    }

    // MARK: Hit testing (screen coordinates; topmost first)

    func hitPort(_ p: CGPoint) -> GraphEndpoint? {
        let radius = geometry.style.portDiameter * zoom / 2 + 4
        for node in mesh.nodes.reversed() {
            let position = layout.position(of: node.id)
            for port in node.ports {
                let center = screen(geometry.portPosition(port, in: node, at: position))
                if MeshCanvasGeometry.distance(center, p) <= radius {
                    return GraphEndpoint(nodeID: node.id, portID: port.id)
                }
            }
        }
        return nil
    }

    func hitNode(_ p: CGPoint) -> UUID? {
        for node in mesh.nodes.reversed() {
            let size = geometry.nodeSize(node)
            let c = nodeCenter(node)
            if abs(p.x - c.x) <= size.width * zoom / 2, abs(p.y - c.y) <= size.height * zoom / 2 {
                return node.id
            }
        }
        return nil
    }

    func hitEdge(_ p: CGPoint, tolerance: CGFloat = 7) -> UUID? {
        for edge in mesh.edges.reversed() {
            guard let wire = wire(for: edge) else { continue }
            var previous = wire.start
            for step in 1 ... 24 {
                let next = wire.point(at: CGFloat(step) / 24)
                if MeshCanvasGeometry.distance(p, toSegment: previous, next) <= tolerance {
                    return edge.id
                }
                previous = next
            }
        }
        return nil
    }

    func hitTarget(_ p: CGPoint) -> MeshInteractionTarget? {
        if let endpoint = hitPort(p) { return .port(endpoint) }
        if let node = hitNode(p) { return .node(node) }
        if let edge = hitEdge(p) { return .edge(edge) }
        return nil
    }
}
