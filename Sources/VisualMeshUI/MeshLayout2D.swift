import CoreGraphics
import Foundation
import Observation

/// Where each node sits in one 2D presentation of a mesh.
///
/// Layout is deliberately separate from the graph: the same `Mesh` can have a
/// 2D layout here, a spatial layout in a 3D renderer, or none at all. Positions
/// are in mesh coordinates, with the origin at the centre of the canvas.
@Observable
public final class MeshLayout2D {
    public private(set) var positions: [UUID: CGPoint]

    public init(positions: [UUID: CGPoint] = [:]) {
        self.positions = positions
    }

    public func position(of nodeID: UUID) -> CGPoint {
        positions[nodeID] ?? .zero
    }

    public func setPosition(_ position: CGPoint, for nodeID: UUID) {
        positions[nodeID] = position
    }

    public func removePosition(for nodeID: UUID) {
        positions[nodeID] = nil
    }

    /// Drops positions for nodes that are no longer in the graph.
    public func prune(keeping nodeIDs: some Sequence<UUID>) {
        let keep = Set(nodeIDs)
        positions = positions.filter { keep.contains($0.key) }
    }
}

// MARK: - Serialization

public extension MeshLayout2D {
    struct Snapshot: Codable, Hashable, Sendable {
        public struct Entry: Codable, Hashable, Sendable {
            public var nodeID: UUID
            public var x: Double
            public var y: Double

            public init(nodeID: UUID, x: Double, y: Double) {
                self.nodeID = nodeID
                self.x = x
                self.y = y
            }
        }

        public var entries: [Entry]

        public init(entries: [Entry]) {
            self.entries = entries
        }
    }

    var snapshot: Snapshot {
        Snapshot(entries: positions
            .map { Snapshot.Entry(nodeID: $0.key, x: Double($0.value.x), y: Double($0.value.y)) }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString })
    }

    convenience init(snapshot: Snapshot) {
        self.init(positions: Dictionary(
            snapshot.entries.map { ($0.nodeID, CGPoint(x: $0.x, y: $0.y)) },
            uniquingKeysWith: { first, _ in first }
        ))
    }
}
