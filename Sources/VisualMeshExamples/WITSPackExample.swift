import Foundation
import VisualMesh

public struct WITSComponent: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case resistor
        case pack
    }

    public var kind: Kind
    public var designator: String
    public var description: String

    public init(kind: Kind, designator: String, description: String) {
        self.kind = kind
        self.designator = designator
        self.description = description
    }
}

public struct WITSNet: Sendable, Equatable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

/// A small executable version of the RESSIP9 pattern recovered from `tc3.sf`.
/// The definition contains nine resistors once; U100 and U101 are references
/// with independent identities and wiring contexts.
public struct WITSHierarchyExample {
    public let library: MeshLibrary<WITSComponent, WITSNet>
    public let board: Mesh<WITSComponent, WITSNet>
    public let resistorPackDefinitionID: MeshDefinitionID

    @MainActor
    public static func make() throws -> WITSHierarchyExample {
        let library = MeshLibrary<WITSComponent, WITSNet>()
        let definition = try makeResistorPackDefinition()
        try library.addDefinition(definition)

        let board = Mesh<WITSComponent, WITSNet>()
        let u100 = try library.instantiate(
            definitionID: definition.id,
            designator: "U100",
            payload: WITSComponent(
                kind: .pack,
                designator: "U100",
                description: "RESSIP9 instance"
            )
        )
        let u101 = try library.instantiate(
            definitionID: definition.id,
            designator: "U101",
            payload: WITSComponent(
                kind: .pack,
                designator: "U101",
                description: "RESSIP9 instance"
            )
        )
        board.addNode(u100)
        board.addNode(u101)

        try board.connect(
            sourceNodeID: u100.id,
            sourcePortID: u100.ports[1].id,
            targetNodeID: u101.id,
            targetPortID: u101.ports[1].id,
            payload: WITSNet(name: "CARD-NET-1")
        )

        return WITSHierarchyExample(
            library: library,
            board: board,
            resistorPackDefinitionID: definition.id
        )
    }

    @MainActor
    public static func makeResistorPackDefinition()
        throws -> MeshDefinition<WITSComponent, WITSNet>
    {
        let interfacePorts = (1...10).map {
            GraphPort(name: "PACK-\($0)", direction: .bidirectional)
        }
        let definition = MeshDefinition<WITSComponent, WITSNet>(
            name: "RESSIP9",
            title: "Nine-resistor SIP",
            interfacePorts: interfacePorts
        )

        var resistors: [GraphNode<WITSComponent>] = []
        for number in 1...9 {
            let terminals = [
                GraphPort(name: "1", direction: .bidirectional),
                GraphPort(name: "2", direction: .bidirectional),
            ]
            let resistor = GraphNode(
                title: "R\(number)",
                payload: WITSComponent(
                    kind: .resistor,
                    designator: "R\(number)",
                    description: "51 OHMS 5% 2 WATTS"
                ),
                ports: terminals
            )
            definition.mesh.addNode(resistor)
            resistors.append(resistor)
        }

        // CONNECT: (PACK-1 R1-2 R2-2 ... R9-2)
        try definition.bind(
            boundaryPortID: interfacePorts[0].id,
            to: resistors.map {
                GraphEndpoint(nodeID: $0.id, portID: $0.ports[1].id)
            }
        )

        // CONNECT: (PACK-2 R1-1) ... (PACK-10 R9-1)
        for index in resistors.indices {
            try definition.bind(
                boundaryPortID: interfacePorts[index + 1].id,
                to: [
                    GraphEndpoint(
                        nodeID: resistors[index].id,
                        portID: resistors[index].ports[0].id
                    ),
                ]
            )
        }

        return definition
    }
}
