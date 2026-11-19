import Foundation
import Testing
import simd
import SpatialInput
import VisualMesh
@testable import VisualMeshSpatial
struct SpatialGraphInputTests {
    @Test func hoverDoesNotSelectAndPressSelectsOnce() {
        let id = UUID(), frame = UUID(), node = MeshInteractionTarget.node(UUID())
        var input = SpatialGraphInput()
        func sample(_ time: Double, _ pressed: Bool) -> SpatialAccessorySample {
            .init(deviceID: id, frameID: frame, timestamp: time, transform: matrix_identity_float4x4,
                  isTracked: true, primaryPressed: pressed)
        }
        #expect(input.handle(sample(1, false), hit: node) == [.hover(node)])
        #expect(input.handle(sample(2, true), hit: node) == [.hover(node), .select(node)])
        #expect(input.handle(sample(3, true), hit: node) == [.hover(node)])
        #expect(input.disconnect(deviceID: id) == .cancel)
    }
}
