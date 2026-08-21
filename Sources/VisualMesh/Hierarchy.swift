import Foundation
import Observation

/// The stable identity of a reusable subgraph definition.
///
/// This is the VisualMesh equivalent of a WITS PACK type such as `RESSIP9`, a
/// TEDL device model, or an IEEE 1671 description document referenced by an
/// instance document.
public struct MeshDefinitionID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        rawValue = UUID()
    }
}

/// A port on an internal node of a mesh definition.
public struct GraphEndpoint: Hashable, Codable, Sendable {
    public let nodeID: UUID
    public let portID: UUID

    public init(nodeID: UUID, portID: UUID) {
        self.nodeID = nodeID
        self.portID = portID
    }
}

/// Maps one declared interface port to the internal endpoints on its net.
///
/// `internalEndpoints` is deliberately plural. For example, `PACK-1` on the
/// historical RESSIP9 resistor pack maps to the second terminal of all nine
/// internal resistors.
public struct GraphBoundaryBinding: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID { boundaryPortID }
    public let boundaryPortID: UUID
    public var internalEndpoints: [GraphEndpoint]

    public init(boundaryPortID: UUID, internalEndpoints: [GraphEndpoint]) {
        self.boundaryPortID = boundaryPortID
        self.internalEndpoints = internalEndpoints
    }
}

/// Relates a port copied onto an instance node to the interface port declared
/// by its definition.
public struct GraphInstancePortBinding: Hashable, Codable, Sendable {
    public let definitionPortID: UUID
    public let instancePortID: UUID

    public init(definitionPortID: UUID, instancePortID: UUID) {
        self.definitionPortID = definitionPortID
        self.instancePortID = instancePortID
    }
}

/// The durable definition reference carried by a subgraph instance node.
public struct GraphSubgraphInstance: Hashable, Codable, Sendable {
    public let definitionID: MeshDefinitionID
    public var designator: String
    public let portBindings: [GraphInstancePortBinding]

    public init(
        definitionID: MeshDefinitionID,
        designator: String,
        portBindings: [GraphInstancePortBinding]
    ) {
        self.definitionID = definitionID
        self.designator = designator
        self.portBindings = portBindings
    }

    public func definitionPortID(forInstancePortID portID: UUID) -> UUID? {
        portBindings.first { $0.instancePortID == portID }?.definitionPortID
    }

    public func instancePortID(forDefinitionPortID portID: UUID) -> UUID? {
        portBindings.first { $0.definitionPortID == portID }?.instancePortID
    }
}

public enum MeshDefinitionError: Error, Equatable, CustomStringConvertible {
    case duplicateDefinitionID(MeshDefinitionID)
    case duplicateDefinitionName(String)
    case definitionMissing(MeshDefinitionID)
    case boundaryPortMissing(UUID)
    case boundaryPortAlreadyBound(UUID)
    case boundaryHasNoInternalEndpoints(UUID)
    case internalNodeMissing(UUID)
    case internalPortMissing(UUID)
    case unboundBoundaryPort(UUID)
    case childDefinitionMissing(MeshDefinitionID)
    case recursiveDefinition(MeshDefinitionID)

    public var description: String {
        switch self {
        case .duplicateDefinitionID(let id):
            return "Definition ID already exists: \(id.rawValue)"
        case .duplicateDefinitionName(let name):
            return "Definition name already exists: \(name)"
        case .definitionMissing(let id):
            return "Definition does not exist: \(id.rawValue)"
        case .boundaryPortMissing(let id):
            return "Boundary port does not exist: \(id)"
        case .boundaryPortAlreadyBound(let id):
            return "Boundary port is already bound: \(id)"
        case .boundaryHasNoInternalEndpoints(let id):
            return "Boundary port has no internal endpoints: \(id)"
        case .internalNodeMissing(let id):
            return "Internal node does not exist: \(id)"
        case .internalPortMissing(let id):
            return "Internal port does not exist: \(id)"
        case .unboundBoundaryPort(let id):
            return "Boundary port is not bound: \(id)"
        case .childDefinitionMissing(let id):
            return "Child definition does not exist: \(id.rawValue)"
        case .recursiveDefinition(let id):
            return "Definition recursively contains itself: \(id.rawValue)"
        }
    }
}

/// A reusable, named subgraph with a declared boundary.
///
/// The internal mesh is stored once. Parent meshes contain lightweight nodes
/// produced by `MeshLibrary.instantiate`, not copies of this mesh.
@Observable
public final class MeshDefinition<NodePayload, EdgePayload>: Identifiable {
    public let id: MeshDefinitionID
    public var name: String
    public var title: String
    public var interfacePorts: [GraphPort]
    public let mesh: Mesh<NodePayload, EdgePayload>
    public private(set) var boundaryBindings: [GraphBoundaryBinding]

    public init(
        id: MeshDefinitionID = MeshDefinitionID(),
        name: String,
        title: String? = nil,
        interfacePorts: [GraphPort],
        mesh: Mesh<NodePayload, EdgePayload> = Mesh(),
        boundaryBindings: [GraphBoundaryBinding] = []
    ) {
        self.id = id
        self.name = name
        self.title = title ?? name
        self.interfacePorts = interfacePorts
        self.mesh = mesh
        self.boundaryBindings = boundaryBindings
    }

    public func boundaryPort(id: UUID) -> GraphPort? {
        interfacePorts.first { $0.id == id }
    }

    public func binding(forBoundaryPortID portID: UUID) -> GraphBoundaryBinding? {
        boundaryBindings.first { $0.boundaryPortID == portID }
    }

    public func bind(boundaryPortID: UUID, to endpoints: [GraphEndpoint]) throws {
        guard boundaryPort(id: boundaryPortID) != nil else {
            throw MeshDefinitionError.boundaryPortMissing(boundaryPortID)
        }
        guard binding(forBoundaryPortID: boundaryPortID) == nil else {
            throw MeshDefinitionError.boundaryPortAlreadyBound(boundaryPortID)
        }
        guard !endpoints.isEmpty else {
            throw MeshDefinitionError.boundaryHasNoInternalEndpoints(boundaryPortID)
        }

        for endpoint in endpoints {
            guard let node = mesh.nodes.first(where: { $0.id == endpoint.nodeID }) else {
                throw MeshDefinitionError.internalNodeMissing(endpoint.nodeID)
            }
            guard node.ports.contains(where: { $0.id == endpoint.portID }) else {
                throw MeshDefinitionError.internalPortMissing(endpoint.portID)
            }
        }

        boundaryBindings.append(
            GraphBoundaryBinding(
                boundaryPortID: boundaryPortID,
                internalEndpoints: endpoints
            )
        )
    }

    public func validateBoundary() throws {
        for port in interfacePorts where binding(forBoundaryPortID: port.id) == nil {
            throw MeshDefinitionError.unboundBoundaryPort(port.id)
        }

        for binding in boundaryBindings {
            guard boundaryPort(id: binding.boundaryPortID) != nil else {
                throw MeshDefinitionError.boundaryPortMissing(binding.boundaryPortID)
            }
            guard !binding.internalEndpoints.isEmpty else {
                throw MeshDefinitionError.boundaryHasNoInternalEndpoints(binding.boundaryPortID)
            }
            for endpoint in binding.internalEndpoints {
                guard let node = mesh.nodes.first(where: { $0.id == endpoint.nodeID }) else {
                    throw MeshDefinitionError.internalNodeMissing(endpoint.nodeID)
                }
                guard node.ports.contains(where: { $0.id == endpoint.portID }) else {
                    throw MeshDefinitionError.internalPortMissing(endpoint.portID)
                }
            }
        }
    }
}

/// Registry for reusable definitions and the sole constructor for instances.
///
/// Keeping this operation in the library guarantees that every instance gets
/// fresh node/port identities while retaining a stable reference to its
/// definition ports.
@Observable
public final class MeshLibrary<NodePayload, EdgePayload> {
    public private(set) var definitions: [MeshDefinition<NodePayload, EdgePayload>] = []

    public init() {}

    public func addDefinition(_ definition: MeshDefinition<NodePayload, EdgePayload>) throws {
        guard !definitions.contains(where: { $0.id == definition.id }) else {
            throw MeshDefinitionError.duplicateDefinitionID(definition.id)
        }
        guard !definitions.contains(where: { $0.name == definition.name }) else {
            throw MeshDefinitionError.duplicateDefinitionName(definition.name)
        }
        try definition.validateBoundary()
        try validateChildReferences(in: definition)
        definitions.append(definition)
        do {
            try validateNoRecursion(from: definition.id, path: [])
        } catch {
            definitions.removeAll { $0.id == definition.id }
            throw error
        }
    }

    public func definition(id: MeshDefinitionID) -> MeshDefinition<NodePayload, EdgePayload>? {
        definitions.first { $0.id == id }
    }

    public func definition(named name: String) -> MeshDefinition<NodePayload, EdgePayload>? {
        definitions.first { $0.name == name }
    }

    public func definition(for node: GraphNode<NodePayload>) -> MeshDefinition<NodePayload, EdgePayload>? {
        guard let id = node.subgraph?.definitionID else { return nil }
        return definition(id: id)
    }

    public func instantiate(
        definitionID: MeshDefinitionID,
        designator: String,
        title: String? = nil,
        payload: NodePayload
    ) throws -> GraphNode<NodePayload> {
        guard let definition = definition(id: definitionID) else {
            throw MeshDefinitionError.definitionMissing(definitionID)
        }

        let instancePorts = definition.interfacePorts.map {
            GraphPort(name: $0.name, direction: $0.direction)
        }
        let portBindings = zip(definition.interfacePorts, instancePorts).map {
            GraphInstancePortBinding(
                definitionPortID: $0.id,
                instancePortID: $1.id
            )
        }
        let instance = GraphSubgraphInstance(
            definitionID: definitionID,
            designator: designator,
            portBindings: portBindings
        )
        return GraphNode(
            title: title ?? designator,
            payload: payload,
            ports: instancePorts,
            subgraph: instance
        )
    }

    /// Resolves an instance port all the way to the definition's internal net.
    public func boundaryBinding(
        forInstancePortID instancePortID: UUID,
        on node: GraphNode<NodePayload>
    ) -> GraphBoundaryBinding? {
        guard
            let instance = node.subgraph,
            let definitionPortID = instance.definitionPortID(forInstancePortID: instancePortID),
            let definition = definition(id: instance.definitionID)
        else {
            return nil
        }
        return definition.binding(forBoundaryPortID: definitionPortID)
    }

    private func validateChildReferences(
        in definition: MeshDefinition<NodePayload, EdgePayload>
    ) throws {
        for node in definition.mesh.nodes {
            guard let childID = node.subgraph?.definitionID else { continue }
            guard childID == definition.id || self.definition(id: childID) != nil else {
                throw MeshDefinitionError.childDefinitionMissing(childID)
            }
        }
    }

    private func validateNoRecursion(
        from definitionID: MeshDefinitionID,
        path: Set<MeshDefinitionID>
    ) throws {
        guard !path.contains(definitionID) else {
            throw MeshDefinitionError.recursiveDefinition(definitionID)
        }
        guard let definition = definition(id: definitionID) else { return }

        var nextPath = path
        nextPath.insert(definitionID)
        for node in definition.mesh.nodes {
            if let childID = node.subgraph?.definitionID {
                try validateNoRecursion(from: childID, path: nextPath)
            }
        }
    }
}
