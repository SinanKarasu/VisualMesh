import CoreGraphics
import Foundation
import Testing
import VisualMesh
@testable import VisualMeshUI

@Suite @MainActor
struct VisualMeshUITests {
    private func twoNodeMesh() -> (Mesh<String, Int>, GraphNode<String>, GraphNode<String>) {
        let mesh = Mesh<String, Int>()
        let a = GraphNode(title: "A", payload: "a", ports: [GraphPort(name: "Out", direction: .output)])
        let b = GraphNode(title: "B", payload: "b", ports: [GraphPort(name: "In", direction: .input)])
        mesh.addNode(a)
        mesh.addNode(b)
        return (mesh, a, b)
    }

    @Test func orientedConnectionAcceptsEitherPickOrder() {
        let (mesh, a, b) = twoNodeMesh()
        let out = GraphEndpoint(nodeID: a.id, portID: a.ports[0].id)
        let inp = GraphEndpoint(nodeID: b.id, portID: b.ports[0].id)

        #expect(mesh.orientedConnection(between: inp, and: out)?.source == out)
        #expect(mesh.orientedConnection(between: out, and: inp)?.target == inp)
        #expect(mesh.orientedConnection(between: out, and: out) == nil)
    }

    @Test func layoutSnapshotRoundTripsAndPrunes() throws {
        let id1 = UUID(), id2 = UUID()
        let layout = MeshLayout2D(positions: [id1: CGPoint(x: 10, y: -20), id2: CGPoint(x: 3, y: 4)])
        let data = try JSONEncoder().encode(layout.snapshot)
        let restored = MeshLayout2D(snapshot: try JSONDecoder().decode(MeshLayout2D.Snapshot.self, from: data))
        #expect(restored.position(of: id1) == CGPoint(x: 10, y: -20))

        restored.prune(keeping: [id2])
        #expect(restored.positions.keys.sorted { $0.uuidString < $1.uuidString } == [id2])
    }

    @Test func connectionIntentsPairBeginAndComplete() {
        let state = MeshCanvasState()
        let first = GraphEndpoint(nodeID: UUID(), portID: UUID())
        let second = GraphEndpoint(nodeID: UUID(), portID: UUID())

        state.apply(.beginConnection(first))
        #expect(state.pendingConnection == first)
        let pair = state.apply(.completeConnection(second))
        #expect(pair?.0 == first && pair?.1 == second)
        #expect(state.pendingConnection == nil)

        state.apply(.beginConnection(first))
        state.apply(.cancel)
        #expect(state.apply(.completeConnection(second)) == nil)
    }

    @Test func sceneHitTestsPortsBeforeNodesAndFollowsPanAndZoom() {
        let (mesh, a, b) = twoNodeMesh()
        let layout = MeshLayout2D(positions: [a.id: .zero, b.id: CGPoint(x: 400, y: 0)])
        let geometry = MeshCanvasGeometry(style: MeshCanvasStyle())
        let scene = MeshCanvasScene(mesh: mesh, layout: layout, geometry: geometry,
                                    origin: CGPoint(x: 200, y: 100), zoom: 2)

        #expect(scene.hitNode(CGPoint(x: 200, y: 100)) == a.id)
        let portCenter = scene.port(GraphEndpoint(nodeID: a.id, portID: a.ports[0].id))!.center
        #expect(scene.hitTarget(portCenter) == .port(GraphEndpoint(nodeID: a.id, portID: a.ports[0].id)))
        #expect(scene.meshPoint(scene.screen(CGPoint(x: 7, y: -3))) == CGPoint(x: 7, y: -3))
    }

    @Test func forgettingDeletedNodesClearsSelection() {
        let state = MeshCanvasState()
        let id = UUID()
        state.apply(.select(.node(id)))
        state.forget(nodeIDs: [id])
        #expect(state.selectedNodeIDs.isEmpty)
    }
}
