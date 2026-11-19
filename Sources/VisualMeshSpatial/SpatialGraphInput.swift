import Foundation
import VisualMesh
import SpatialInput

/// A host supplies its hit test; graph semantics do not depend on renderer coordinates.
public struct SpatialGraphInput: Sendable {
    private var gate = SpatialActivationGate()
    public init() {}
    public mutating func handle(_ sample: SpatialAccessorySample, hit: MeshInteractionTarget?) -> [MeshInteractionIntent] {
        let activate = gate.shouldActivate(sample)
        guard sample.isTracked else { return [.hover(nil), .cancel] }
        var result: [MeshInteractionIntent] = [.hover(hit)]
        if activate, let hit { result.append(.select(hit)) }
        return result
    }
    public mutating func disconnect(deviceID: UUID) -> MeshInteractionIntent {
        gate.remove(deviceID: deviceID)
        return .cancel
    }
}
