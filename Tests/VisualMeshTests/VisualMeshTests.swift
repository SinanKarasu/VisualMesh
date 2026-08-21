import Testing
@testable import VisualMesh
import VisualMeshExamples

@Suite @MainActor
struct VisualMeshTests {
    @Test func instrumentReceivesOnlyItsEdgesTelemetry() throws {
        let oscilloscope = VirtualOscilloscope(capacity: 2)
        let observedPayload = SignalEdgePayload()
        let otherPayload = SignalEdgePayload()
        observedPayload.attach(oscilloscope)

        observedPayload.publish(voltage: 1, frequency: 440)
        otherPayload.publish(voltage: 99, frequency: 880)
        observedPayload.publish(voltage: 2, frequency: 440)
        observedPayload.publish(voltage: 3, frequency: 440)

        #expect(oscilloscope.voltageHistory.map(\.voltage) == [2, 3])
    }

    @Test func connectionValidatesPortDirection() {
        let mesh = Mesh<String, SignalEdgePayload>()
        let input = GraphPort(name: "In", direction: .input)
        let output = GraphPort(name: "Out", direction: .output)
        let first = GraphNode(title: "First", payload: "", ports: [input])
        let second = GraphNode(title: "Second", payload: "", ports: [output])
        mesh.addNode(first)
        mesh.addNode(second)

        #expect(throws: MeshConnectionError.incompatiblePortDirections) {
            try mesh.connect(
                sourceNodeID: first.id,
                sourcePortID: input.id,
                targetNodeID: second.id,
                targetPortID: output.id,
                payload: SignalEdgePayload()
            )
        }
    }

    @Test func bidirectionalPhysicalPortsCanBeCombined() throws {
        let mesh = Mesh<String, String>()
        let firstPort = GraphPort(name: "Terminal 1", direction: .bidirectional)
        let secondPort = GraphPort(name: "Terminal 2", direction: .bidirectional)
        let first = GraphNode(title: "First", payload: "", ports: [firstPort])
        let second = GraphNode(title: "Second", payload: "", ports: [secondPort])
        mesh.addNode(first)
        mesh.addNode(second)

        let edge = try mesh.connect(
            sourceNodeID: first.id,
            sourcePortID: firstPort.id,
            targetNodeID: second.id,
            targetPortID: secondPort.id,
            payload: "NET-1"
        )

        #expect(edge.payload == "NET-1")
    }

    @Test func packDefinitionIsStoredOnceAndInstantiatedByReference() throws {
        let library = MeshLibrary<String, String>()
        let packPort = GraphPort(name: "PACK-1", direction: .bidirectional)
        let internalPort = GraphPort(name: "2", direction: .bidirectional)
        let resistor = GraphNode(title: "R1", payload: "51 OHMS", ports: [internalPort])
        let definition = MeshDefinition<String, String>(
            name: "RESSIP1",
            interfacePorts: [packPort]
        )
        definition.mesh.addNode(resistor)
        try definition.bind(
            boundaryPortID: packPort.id,
            to: [GraphEndpoint(nodeID: resistor.id, portID: internalPort.id)]
        )
        try library.addDefinition(definition)

        let u100 = try library.instantiate(
            definitionID: definition.id,
            designator: "U100",
            payload: "first"
        )
        let u101 = try library.instantiate(
            definitionID: definition.id,
            designator: "U101",
            payload: "second"
        )

        #expect(library.definitions.count == 1)
        #expect(definition.mesh.nodes.count == 1)
        #expect(u100.subgraph?.definitionID == definition.id)
        #expect(u101.subgraph?.definitionID == definition.id)
        #expect(u100.id != u101.id)
        #expect(u100.ports[0].id != u101.ports[0].id)
        #expect(
            library.boundaryBinding(forInstancePortID: u100.ports[0].id, on: u100)?
                .internalEndpoints == [GraphEndpoint(nodeID: resistor.id, portID: internalPort.id)]
        )
    }

    @Test func oneBoundaryPortMayExposeAnInternalNet() throws {
        let boundary = GraphPort(name: "PACK-1", direction: .bidirectional)
        let definition = MeshDefinition<String, String>(
            name: "COMMON",
            interfacePorts: [boundary]
        )
        var endpoints: [GraphEndpoint] = []

        for number in 1...9 {
            let port = GraphPort(name: "2", direction: .bidirectional)
            let node = GraphNode(title: "R\(number)", payload: "resistor", ports: [port])
            definition.mesh.addNode(node)
            endpoints.append(GraphEndpoint(nodeID: node.id, portID: port.id))
        }
        try definition.bind(boundaryPortID: boundary.id, to: endpoints)

        #expect(definition.binding(forBoundaryPortID: boundary.id)?.internalEndpoints.count == 9)
    }

    @Test func definitionsRejectUndeclaredBoundaries() {
        let definition = MeshDefinition<String, String>(
            name: "BROKEN",
            interfacePorts: [GraphPort(name: "A", direction: .bidirectional)]
        )

        #expect(throws: MeshDefinitionError.self) {
            try MeshLibrary<String, String>().addDefinition(definition)
        }
    }

    @Test func definitionsCanContainInstancesOfOtherDefinitions() throws {
        let library = MeshLibrary<String, String>()
        let childBoundary = GraphPort(name: "A", direction: .bidirectional)
        let childInternal = GraphPort(name: "1", direction: .bidirectional)
        let childNode = GraphNode(title: "R1", payload: "resistor", ports: [childInternal])
        let child = MeshDefinition<String, String>(
            name: "CHILD",
            interfacePorts: [childBoundary]
        )
        child.mesh.addNode(childNode)
        try child.bind(
            boundaryPortID: childBoundary.id,
            to: [GraphEndpoint(nodeID: childNode.id, portID: childInternal.id)]
        )
        try library.addDefinition(child)

        let childInstance = try library.instantiate(
            definitionID: child.id,
            designator: "U1",
            payload: "child instance"
        )
        let parentBoundary = GraphPort(name: "OUT", direction: .bidirectional)
        let parent = MeshDefinition<String, String>(
            name: "PARENT",
            interfacePorts: [parentBoundary]
        )
        parent.mesh.addNode(childInstance)
        try parent.bind(
            boundaryPortID: parentBoundary.id,
            to: [GraphEndpoint(nodeID: childInstance.id, portID: childInstance.ports[0].id)]
        )
        try library.addDefinition(parent)

        #expect(library.definitions.count == 2)
        #expect(library.definition(id: parent.id)?.mesh.nodes[0].subgraph?.definitionID == child.id)
    }

    @Test func recoveredRESSIP9HasTheOriginalBoundaryMap() throws {
        let example = try WITSHierarchyExample.make()
        let definition = try #require(
            example.library.definition(id: example.resistorPackDefinitionID)
        )
        let packOne = try #require(
            definition.interfacePorts.first { $0.name == "PACK-1" }
        )

        #expect(definition.mesh.nodes.count == 9)
        #expect(definition.interfacePorts.count == 10)
        #expect(definition.binding(forBoundaryPortID: packOne.id)?.internalEndpoints.count == 9)
        #expect(example.board.nodes.map { $0.subgraph?.designator } == ["U100", "U101"])
        #expect(example.board.edges.count == 1)
    }
}
