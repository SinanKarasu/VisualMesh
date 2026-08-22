import Foundation

/// A stable reference to something a VisualMesh presentation can hit-test.
///
/// Renderers are free to be two-dimensional, spatial, or non-visual. Input
/// devices deal in these semantic targets instead of view or RealityKit types.
public enum MeshInteractionTarget: Hashable, Sendable {
    case node(UUID)
    case port(GraphEndpoint)
    case edge(UUID)
}

/// Device-independent intentions understood by a VisualMesh presentation.
///
/// Mouse gestures, hand tracking, and a spatial stylus can all translate their
/// native events into this vocabulary without entering the graph model.
public enum MeshInteractionIntent: Hashable, Sendable {
    case hover(MeshInteractionTarget?)
    case select(MeshInteractionTarget)
    case openSubgraph(nodeID: UUID)
    case closeSubgraph
    case beginConnection(GraphEndpoint)
    case completeConnection(GraphEndpoint)
    case cancel
}
