import Foundation
import Observation

public enum PortDirection: String, Codable, Sendable {
    case input
    case output
    /// A physical terminal or logical interface that can carry a signal in
    /// either direction. IEEE 1671 interfaces and WITS/TEDL terminals are not
    /// necessarily directed even though processing graphs usually are.
    case bidirectional

    public var canSource: Bool {
        self == .output || self == .bidirectional
    }

    public var canTarget: Bool {
        self == .input || self == .bidirectional
    }
}

public struct GraphPort: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var direction: PortDirection

    public init(id: UUID = UUID(), name: String, direction: PortDirection) {
        self.id = id
        self.name = name
        self.direction = direction
    }
}

@Observable
public final class GraphNode<Payload>: Identifiable {
    public let id: UUID
    public var title: String
    public var payload: Payload
    public var ports: [GraphPort]
    /// Present when this node is an instance of a reusable mesh definition.
    /// Atomic nodes leave it `nil`.
    public var subgraph: GraphSubgraphInstance?

    public init(
        id: UUID = UUID(),
        title: String,
        payload: Payload,
        ports: [GraphPort] = [],
        subgraph: GraphSubgraphInstance? = nil
    ) {
        self.id = id
        self.title = title
        self.payload = payload
        self.ports = ports
        self.subgraph = subgraph
    }
}

@Observable
public final class GraphEdge<Payload>: Identifiable {
    public let id: UUID
    public let sourceNodeID: UUID
    public let sourcePortID: UUID
    public let targetNodeID: UUID
    public let targetPortID: UUID
    public var payload: Payload

    public init(
        id: UUID = UUID(),
        sourceNodeID: UUID,
        sourcePortID: UUID,
        targetNodeID: UUID,
        targetPortID: UUID,
        payload: Payload
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.sourcePortID = sourcePortID
        self.targetNodeID = targetNodeID
        self.targetPortID = targetPortID
        self.payload = payload
    }
}

public enum MeshConnectionError: Error, Equatable {
    case sourceNodeMissing
    case targetNodeMissing
    case sourcePortMissing
    case targetPortMissing
    case incompatiblePortDirections
    case duplicateConnection
}

@Observable
public final class Mesh<NodePayload, EdgePayload> {
    public private(set) var nodes: [GraphNode<NodePayload>] = []
    public private(set) var edges: [GraphEdge<EdgePayload>] = []

    public init() {}

    public func addNode(_ node: GraphNode<NodePayload>) {
        nodes.append(node)
    }

    @discardableResult
    public func connect(
        sourceNodeID: UUID,
        sourcePortID: UUID,
        targetNodeID: UUID,
        targetPortID: UUID,
        payload: EdgePayload
    ) throws -> GraphEdge<EdgePayload> {
        guard let sourceNode = nodes.first(where: { $0.id == sourceNodeID }) else {
            throw MeshConnectionError.sourceNodeMissing
        }
        guard let targetNode = nodes.first(where: { $0.id == targetNodeID }) else {
            throw MeshConnectionError.targetNodeMissing
        }
        guard let sourcePort = sourceNode.ports.first(where: { $0.id == sourcePortID }) else {
            throw MeshConnectionError.sourcePortMissing
        }
        guard let targetPort = targetNode.ports.first(where: { $0.id == targetPortID }) else {
            throw MeshConnectionError.targetPortMissing
        }
        guard sourcePort.direction.canSource, targetPort.direction.canTarget else {
            throw MeshConnectionError.incompatiblePortDirections
        }
        guard !edges.contains(where: {
            $0.sourcePortID == sourcePortID && $0.targetPortID == targetPortID
        }) else {
            throw MeshConnectionError.duplicateConnection
        }

        let edge = GraphEdge(
            sourceNodeID: sourceNodeID,
            sourcePortID: sourcePortID,
            targetNodeID: targetNodeID,
            targetPortID: targetPortID,
            payload: payload
        )
        edges.append(edge)
        return edge
    }

    public func removeEdge(id: UUID) {
        edges.removeAll { $0.id == id }
    }

    public func removeNode(id: UUID) {
        nodes.removeAll { $0.id == id }
        edges.removeAll { $0.sourceNodeID == id || $0.targetNodeID == id }
    }
}

// MARK: - Lookups and renderer-neutral connection planning

public extension GraphNode {
    func port(id: UUID) -> GraphPort? {
        ports.first { $0.id == id }
    }
}

public extension Mesh {
    func node(id: UUID) -> GraphNode<NodePayload>? {
        nodes.first { $0.id == id }
    }

    func edge(id: UUID) -> GraphEdge<EdgePayload>? {
        edges.first { $0.id == id }
    }

    func port(at endpoint: GraphEndpoint) -> GraphPort? {
        node(id: endpoint.nodeID)?.port(id: endpoint.portID)
    }

    /// Orders two endpoints picked by a user, in either order, into a
    /// source and target that `connect` accepts. Returns `nil` when neither
    /// order is valid. Renderers (2D, spatial, or none) share this rule.
    func orientedConnection(
        between first: GraphEndpoint,
        and second: GraphEndpoint
    ) -> (source: GraphEndpoint, target: GraphEndpoint)? {
        guard first != second,
              let a = port(at: first),
              let b = port(at: second) else { return nil }
        if a.direction.canSource, b.direction.canTarget {
            return (first, second)
        }
        if b.direction.canSource, a.direction.canTarget {
            return (second, first)
        }
        return nil
    }
}
