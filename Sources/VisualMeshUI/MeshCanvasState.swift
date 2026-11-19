import CoreGraphics
import Foundation
import Observation
import VisualMesh

/// View state for one canvas: viewport, selection, hover, and a connection
/// being drawn. It is driven by `MeshInteractionIntent`, so mouse, trackpad,
/// and spatial input all change it the same way.
@MainActor
@Observable
public final class MeshCanvasState {
    /// Magnification, clamped by the canvas style.
    public var zoom: CGFloat = 1
    /// Offset of the mesh origin from the canvas centre, in screen points.
    public var pan: CGSize = .zero

    public private(set) var selectedNodeIDs: Set<UUID> = []
    public private(set) var selectedEdgeID: UUID?
    public private(set) var hoverTarget: MeshInteractionTarget?
    /// The endpoint a connection started from, while one is being drawn.
    public private(set) var pendingConnection: GraphEndpoint?
    /// Set by `.openSubgraph`; a host decides how to present it.
    public private(set) var openSubgraphNodeID: UUID?

    /// Free end of the wire being drawn, in screen coordinates.
    var wireEnd: CGPoint?

    // Gesture bookkeeping that should not trigger view updates.
    @ObservationIgnored var pointer: CGPoint?
    @ObservationIgnored var drag: DragMode?
    @ObservationIgnored var zoomOrigin: (zoom: CGFloat, pan: CGSize)?

    enum DragMode {
        case pan(origin: CGSize)
        case nodes(origins: [UUID: CGPoint])
        case wire
        case idle
    }

    public init() {}

    public func isSelected(nodeID: UUID) -> Bool {
        selectedNodeIDs.contains(nodeID)
    }

    public func clearSelection() {
        selectedNodeIDs = []
        selectedEdgeID = nil
    }

    public func selectNodes(_ ids: Set<UUID>) {
        selectedNodeIDs = ids
        selectedEdgeID = nil
    }

    /// Applies a device-neutral intent. Returns the two endpoints when a
    /// `completeConnection` finishes a connection that was begun; the host
    /// decides whether and how to connect them.
    @discardableResult
    public func apply(_ intent: MeshInteractionIntent) -> (GraphEndpoint, GraphEndpoint)? {
        switch intent {
        case .hover(let target):
            if hoverTarget != target { hoverTarget = target }
        case .select(let target):
            switch target {
            case .node(let id):
                selectedNodeIDs = [id]
                selectedEdgeID = nil
            case .edge(let id):
                selectedNodeIDs = []
                selectedEdgeID = id
            case .port(let endpoint):
                selectedNodeIDs = [endpoint.nodeID]
                selectedEdgeID = nil
            }
        case .openSubgraph(let nodeID):
            openSubgraphNodeID = nodeID
        case .closeSubgraph:
            openSubgraphNodeID = nil
        case .beginConnection(let endpoint):
            pendingConnection = endpoint
        case .completeConnection(let endpoint):
            defer { pendingConnection = nil; wireEnd = nil }
            if let start = pendingConnection, start != endpoint {
                return (start, endpoint)
            }
        case .cancel:
            pendingConnection = nil
            wireEnd = nil
        }
        return nil
    }

    /// Removes selection and hover state that refers to deleted items.
    public func forget(nodeIDs: Set<UUID> = [], edgeIDs: Set<UUID> = []) {
        selectedNodeIDs.subtract(nodeIDs)
        if let edge = selectedEdgeID, edgeIDs.contains(edge) { selectedEdgeID = nil }
        switch hoverTarget {
        case .node(let id) where nodeIDs.contains(id),
             .edge(let id) where edgeIDs.contains(id):
            hoverTarget = nil
        case .port(let endpoint) where nodeIDs.contains(endpoint.nodeID):
            hoverTarget = nil
        default:
            break
        }
    }
}
