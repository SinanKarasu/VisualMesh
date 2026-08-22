import Foundation
import VisualMesh

public enum ATEAdapterPath: String, Sendable, CaseIterable {
    case lru
    case card
}

public struct TestSystemComponent: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case ate
        case patchPanelInterface
        case dtuFrontEnd
        case auxiliaryAdapter
        case route
        case uutAdapter
        case standardDTUFixture
        case loadBoard
    }

    public var kind: Kind
    public var name: String
    public var detail: String
    public var workflowStage: Int?

    public init(
        kind: Kind,
        name: String,
        detail: String,
        workflowStage: Int? = nil
    ) {
        self.kind = kind
        self.name = name
        self.detail = detail
        self.workflowStage = workflowStage
    }
}

public struct TestSystemRoute: Sendable, Equatable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

/// The first executable form of the TPS configuration workflow:
///
/// 1. Choose the ATE.
/// 2. Choose the standard auxiliary adapter.
/// 3. Design or choose the UUT adapter.
///
/// Each of the three boxes is an instance of a reusable definition. Switching
/// from an LRU path to a card path replaces only the two adapter definitions;
/// the ATS-182 definition and the top-level workflow remain unchanged.
public struct ATEAdapterHierarchyExample {
    public let path: ATEAdapterPath
    public let library: MeshLibrary<TestSystemComponent, TestSystemRoute>
    public let configuration: Mesh<TestSystemComponent, TestSystemRoute>
    public let ateDefinitionID: MeshDefinitionID
    public let auxiliaryDefinitionID: MeshDefinitionID
    public let uutAdapterDefinitionID: MeshDefinitionID

    @MainActor
    public static func make(path: ATEAdapterPath) throws -> ATEAdapterHierarchyExample {
        let library = MeshLibrary<TestSystemComponent, TestSystemRoute>()
        let ate = try makeATS182Definition()
        let auxiliary = try makeAuxiliaryDefinition(path: path)
        let uutAdapter = try makeUUTAdapterDefinition(path: path)

        try library.addDefinition(ate)
        try library.addDefinition(auxiliary)
        try library.addDefinition(uutAdapter)

        let configuration = Mesh<TestSystemComponent, TestSystemRoute>()
        let ateInstance = try library.instantiate(
            definitionID: ate.id,
            designator: "ATE-1",
            title: "ATS-182",
            payload: TestSystemComponent(
                kind: .ate,
                name: "ATS-182",
                detail: "Automatic test equipment",
                workflowStage: 1
            )
        )
        let auxiliaryInstance = try library.instantiate(
            definitionID: auxiliary.id,
            designator: "AUX-1",
            title: auxiliary.title,
            payload: TestSystemComponent(
                kind: .auxiliaryAdapter,
                name: auxiliary.title,
                detail: "Standard auxiliary adapter",
                workflowStage: 2
            )
        )
        let uutAdapterInstance = try library.instantiate(
            definitionID: uutAdapter.id,
            designator: "FIXTURE-1",
            title: uutAdapter.title,
            payload: TestSystemComponent(
                kind: .uutAdapter,
                name: uutAdapter.title,
                detail: "UUT interface customization",
                workflowStage: 3
            )
        )

        configuration.addNode(ateInstance)
        configuration.addNode(auxiliaryInstance)
        configuration.addNode(uutAdapterInstance)

        try configuration.connect(
            sourceNodeID: ateInstance.id,
            sourcePortID: ateInstance.ports[1].id,
            targetNodeID: auxiliaryInstance.id,
            targetPortID: auxiliaryInstance.ports[0].id,
            payload: TestSystemRoute(name: "ATE-TO-AUX")
        )
        try configuration.connect(
            sourceNodeID: auxiliaryInstance.id,
            sourcePortID: auxiliaryInstance.ports[1].id,
            targetNodeID: uutAdapterInstance.id,
            targetPortID: uutAdapterInstance.ports[0].id,
            payload: TestSystemRoute(name: "AUX-TO-UUT-ADAPTER")
        )

        return ATEAdapterHierarchyExample(
            path: path,
            library: library,
            configuration: configuration,
            ateDefinitionID: ate.id,
            auxiliaryDefinitionID: auxiliary.id,
            uutAdapterDefinitionID: uutAdapter.id
        )
    }

    @MainActor
    private static func makeATS182Definition()
        throws -> MeshDefinition<TestSystemComponent, TestSystemRoute>
    {
        let resources = GraphPort(name: "Station Resources", direction: .bidirectional)
        let adapterInterface = GraphPort(name: "Adapter Interface", direction: .bidirectional)
        let definition = MeshDefinition<TestSystemComponent, TestSystemRoute>(
            name: "ATS182",
            title: "ATS-182",
            interfacePorts: [resources, adapterInterface]
        )

        let patchPorts = [
            GraphPort(name: "Resources", direction: .bidirectional),
            GraphPort(name: "Switch Path", direction: .bidirectional),
        ]
        let patchPanel = GraphNode(
            title: "Patch Panel Interface",
            payload: TestSystemComponent(
                kind: .patchPanelInterface,
                name: "Patch Panel Interface",
                detail: "AMP patch panel and HP-9412 modular switching path"
            ),
            ports: patchPorts
        )
        let dtuPorts = [
            GraphPort(name: "Switch Path", direction: .bidirectional),
            GraphPort(name: "Adapter Interface", direction: .bidirectional),
        ]
        let dtu = GraphNode(
            title: "DTU Front End",
            payload: TestSystemComponent(
                kind: .dtuFrontEnd,
                name: "DTU Front End",
                detail: "Lower 180 pins; upper 120 pins; HP-9414 16x120 matrix"
            ),
            ports: dtuPorts
        )
        definition.mesh.addNode(patchPanel)
        definition.mesh.addNode(dtu)
        try definition.mesh.connect(
            sourceNodeID: patchPanel.id,
            sourcePortID: patchPorts[1].id,
            targetNodeID: dtu.id,
            targetPortID: dtuPorts[0].id,
            payload: TestSystemRoute(name: "MODULAR-SWITCH-TO-DTU")
        )
        try definition.bind(
            boundaryPortID: resources.id,
            to: [GraphEndpoint(nodeID: patchPanel.id, portID: patchPorts[0].id)]
        )
        try definition.bind(
            boundaryPortID: adapterInterface.id,
            to: [GraphEndpoint(nodeID: dtu.id, portID: dtuPorts[1].id)]
        )
        return definition
    }

    @MainActor
    private static func makeAuxiliaryDefinition(path: ATEAdapterPath)
        throws -> MeshDefinition<TestSystemComponent, TestSystemRoute>
    {
        let ateSide = GraphPort(name: "ATE Side", direction: .bidirectional)
        let fixtureSide = GraphPort(name: "UUT Adapter Side", direction: .bidirectional)
        let definitionName: String
        let title: String
        let detail: String

        switch path {
        case .lru:
            definitionName = "StandardJumperAdapter"
            title = "Standard Jumper Adapter"
            detail = "Routes patch-panel signals to the DTU and matrix for LRU testing"
        case .card:
            definitionName = "StandardAuxiliaryPatchPanelAdapter"
            title = "Standard Auxiliary Patch Panel Adapter"
            detail = "Routes station resources to the lower DTU connector for card testing"
        }

        let definition = MeshDefinition<TestSystemComponent, TestSystemRoute>(
            name: definitionName,
            title: title,
            interfacePorts: [ateSide, fixtureSide]
        )
        let routePorts = [
            GraphPort(name: "ATE Side", direction: .bidirectional),
            GraphPort(name: "Fixture Side", direction: .bidirectional),
        ]
        let route = GraphNode(
            title: "Standard Routing",
            payload: TestSystemComponent(kind: .route, name: title, detail: detail),
            ports: routePorts
        )
        definition.mesh.addNode(route)
        try definition.bind(
            boundaryPortID: ateSide.id,
            to: [GraphEndpoint(nodeID: route.id, portID: routePorts[0].id)]
        )
        try definition.bind(
            boundaryPortID: fixtureSide.id,
            to: [GraphEndpoint(nodeID: route.id, portID: routePorts[1].id)]
        )
        return definition
    }

    @MainActor
    private static func makeUUTAdapterDefinition(path: ATEAdapterPath)
        throws -> MeshDefinition<TestSystemComponent, TestSystemRoute>
    {
        let dtuSide = GraphPort(name: "DTU Boundary", direction: .bidirectional)
        let uutSide = GraphPort(name: "UUT Boundary", direction: .bidirectional)

        switch path {
        case .lru:
            let definition = MeshDefinition<TestSystemComponent, TestSystemRoute>(
                name: "LRUDTUAdapter",
                title: "UUT-specific DTU Adapter",
                interfacePorts: [dtuSide, uutSide]
            )
            let fixturePorts = [
                GraphPort(name: "DTU", direction: .bidirectional),
                GraphPort(name: "UUT", direction: .bidirectional),
            ]
            let fixture = GraphNode(
                title: "DTU Mating Fixture",
                payload: TestSystemComponent(
                    kind: .uutAdapter,
                    name: "DTU Mating Fixture",
                    detail: "UUT-specific wiring and connector boundary"
                ),
                ports: fixturePorts
            )
            definition.mesh.addNode(fixture)
            try definition.bind(
                boundaryPortID: dtuSide.id,
                to: [GraphEndpoint(nodeID: fixture.id, portID: fixturePorts[0].id)]
            )
            try definition.bind(
                boundaryPortID: uutSide.id,
                to: [GraphEndpoint(nodeID: fixture.id, portID: fixturePorts[1].id)]
            )
            return definition

        case .card:
            let definition = MeshDefinition<TestSystemComponent, TestSystemRoute>(
                name: "CardFixture",
                title: "Standard DTU Fixture + LoadBoard",
                interfacePorts: [dtuSide, uutSide]
            )
            let fixturePorts = [
                GraphPort(name: "DTU", direction: .bidirectional),
                GraphPort(name: "LoadBoard", direction: .bidirectional),
            ]
            let fixture = GraphNode(
                title: "Standard DTU Fixture",
                payload: TestSystemComponent(
                    kind: .standardDTUFixture,
                    name: "Standard DTU Fixture",
                    detail: "Reusable card-test fixture"
                ),
                ports: fixturePorts
            )
            let loadBoardPorts = [
                GraphPort(name: "Fixture", direction: .bidirectional),
                GraphPort(name: "Card", direction: .bidirectional),
            ]
            let loadBoard = GraphNode(
                title: "86-pin LoadBoard",
                payload: TestSystemComponent(
                    kind: .loadBoard,
                    name: "86-pin LoadBoard",
                    detail: "Custom components and wiring for the card under test"
                ),
                ports: loadBoardPorts
            )
            definition.mesh.addNode(fixture)
            definition.mesh.addNode(loadBoard)
            try definition.mesh.connect(
                sourceNodeID: fixture.id,
                sourcePortID: fixturePorts[1].id,
                targetNodeID: loadBoard.id,
                targetPortID: loadBoardPorts[0].id,
                payload: TestSystemRoute(name: "FIXTURE-TO-LOADBOARD")
            )
            try definition.bind(
                boundaryPortID: dtuSide.id,
                to: [GraphEndpoint(nodeID: fixture.id, portID: fixturePorts[0].id)]
            )
            try definition.bind(
                boundaryPortID: uutSide.id,
                to: [GraphEndpoint(nodeID: loadBoard.id, portID: loadBoardPorts[1].id)]
            )
            return definition
        }
    }
}
