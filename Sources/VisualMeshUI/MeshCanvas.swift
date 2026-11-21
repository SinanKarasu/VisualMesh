import SwiftUI
import VisualMesh

/// Where a canvas context-menu command should act. Read `meshPoint` inside
/// the command's action: it resolves to the pointer location when the menu
/// was opened, or the centre of the visible canvas when there is no pointer
/// (for example with spatial input).
@MainActor
public struct MeshCanvasLocation {
    let resolve: () -> CGPoint

    /// The location in mesh coordinates.
    public var meshPoint: CGPoint { resolve() }
}

/// A pannable, zoomable 2D editor for any `Mesh`.
///
/// The canvas never mutates graph topology itself. It reports intents
/// (`onConnect`, `onDeleteSelection`) and lets the host apply them, so a host
/// with a live runtime (an audio engine, an instrument) stays in control.
/// Node positions live in a separate `MeshLayout2D`, which the canvas edits.
public struct MeshCanvas<NodePayload, EdgePayload, NodeContent: View>: View {
    private let mesh: Mesh<NodePayload, EdgePayload>
    private let layout: MeshLayout2D
    private let state: MeshCanvasState
    private let style: MeshCanvasStyle
    private let nodeContent: (GraphNode<NodePayload>) -> NodeContent

    private var tintForNode: (GraphNode<NodePayload>) -> Color = { _ in Color(white: 0.32) }
    private var tintForEdge: (GraphEdge<EdgePayload>) -> Color = { _ in .cyan }
    private var tintForPort: (GraphPort) -> Color = MeshCanvas.defaultPortTint
    private var nodeMenuBuilder: ((GraphNode<NodePayload>) -> AnyView)?
    private var edgeMenuBuilder: ((GraphEdge<EdgePayload>) -> AnyView)?
    private var canvasMenuBuilder: ((MeshCanvasLocation) -> AnyView)?
    private var edgeAccessoryBuilder: ((GraphEdge<EdgePayload>) -> AnyView?)?
    private var connectAction: ((GraphEndpoint, GraphEndpoint) -> Void)?
    private var deleteAction: ((Set<UUID>, UUID?) -> Void)?
    private var movedAction: ((Set<UUID>) -> Void)?
    private var isReadOnly = false
    private var gridVisible = true

    private let space = "VisualMeshUI.MeshCanvas"
    private var geometry: MeshCanvasGeometry { MeshCanvasGeometry(style: style) }

    public init(
        mesh: Mesh<NodePayload, EdgePayload>,
        layout: MeshLayout2D,
        state: MeshCanvasState,
        style: MeshCanvasStyle = MeshCanvasStyle(),
        @ViewBuilder nodeContent: @escaping (GraphNode<NodePayload>) -> NodeContent
    ) {
        self.mesh = mesh
        self.layout = layout
        self.state = state
        self.style = style
        self.nodeContent = nodeContent
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scene = MeshCanvasScene(
                mesh: mesh,
                layout: layout,
                geometry: geometry,
                origin: CGPoint(x: size.width / 2 + state.pan.width,
                                y: size.height / 2 + state.pan.height),
                zoom: state.zoom
            )

            ZStack(alignment: .topLeading) {
                background(scene: scene, size: size)
                ForEach(mesh.edges) { edge in
                    edgeView(edge, scene: scene)
                }
                pendingWire(scene: scene)
                ForEach(mesh.nodes) { node in
                    nodeView(node, scene: scene)
                }
                ForEach(mesh.edges) { edge in
                    accessoryView(edge, scene: scene)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(Rectangle())
            .coordinateSpace(name: space)
            .gesture(dragGesture(scene: scene))
            .simultaneousGesture(magnifyGesture)
            .onContinuousHover(coordinateSpace: .named(space)) { phase in
                switch phase {
                case .active(let location):
                    state.pointer = location
                    state.apply(.hover(scene.hitTarget(location)))
                case .ended:
                    state.pointer = nil
                    state.apply(.hover(nil))
                }
            }
            .focusable(!isReadOnly)
            .focusEffectDisabled()
            .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                guard !isReadOnly, let deleteAction,
                      !state.selectedNodeIDs.isEmpty || state.selectedEdgeID != nil
                else { return .ignored }
                deleteAction(state.selectedNodeIDs, state.selectedEdgeID)
                return .handled
            }
            .onKeyPress(.escape) {
                guard state.pendingConnection != nil else { return .ignored }
                state.apply(.cancel)
                state.drag = nil
                return .handled
            }
        }
    }

    // MARK: - Layers

    private func background(scene: MeshCanvasScene<NodePayload, EdgePayload>, size: CGSize) -> some View {
        ZStack {
            Rectangle().fill(Color.gray.opacity(0.06))
            if gridVisible {
                MeshGridView(spacing: style.gridSpacing * state.zoom, origin: scene.origin)
            }
        }
        .frame(width: size.width, height: size.height)
        .contextMenu {
            if !isReadOnly, let canvasMenuBuilder {
                canvasMenuBuilder(MeshCanvasLocation { [state] in
                    scene.meshPoint(state.pointer ?? CGPoint(x: size.width / 2, y: size.height / 2))
                })
            }
        }
    }

    @ViewBuilder
    private func edgeView(_ edge: GraphEdge<EdgePayload>,
                          scene: MeshCanvasScene<NodePayload, EdgePayload>) -> some View {
        if let wire = scene.wire(for: edge) {
            let path = Path { p in
                p.move(to: wire.start)
                p.addCurve(to: wire.end, control1: wire.control1, control2: wire.control2)
            }
            let selected = state.selectedEdgeID == edge.id
            let hovered = state.hoverTarget == .edge(edge.id)
            path
                .stroke(tintForEdge(edge).opacity(selected || hovered ? 1 : 0.8),
                        style: StrokeStyle(lineWidth: selected ? 4.5 : (hovered ? 3.5 : 2.5),
                                           lineCap: .round))
                .contentShape(path.strokedPath(StrokeStyle(lineWidth: 14)))
                .contextMenu {
                    if !isReadOnly, let edgeMenuBuilder { edgeMenuBuilder(edge) }
                }
                .accessibilityLabel("Connection")
        }
    }

    @ViewBuilder
    private func pendingWire(scene: MeshCanvasScene<NodePayload, EdgePayload>) -> some View {
        if let start = state.pendingConnection.flatMap(scene.port), let end = state.wireEnd {
            Path { p in
                p.move(to: start.center)
                p.addLine(to: end)
            }
            .stroke(Color.purple, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 4]))
            .allowsHitTesting(false)
        }
    }

    private func nodeView(_ node: GraphNode<NodePayload>,
                          scene: MeshCanvasScene<NodePayload, EdgePayload>) -> some View {
        var highlighted: UUID?
        if case .port(let endpoint) = state.hoverTarget, endpoint.nodeID == node.id {
            highlighted = endpoint.portID
        }
        let pending = state.pendingConnection?.nodeID == node.id ? state.pendingConnection?.portID : nil
        return MeshNodeChrome(
            node: node,
            geometry: geometry,
            tint: tintForNode(node),
            portTint: tintForPort,
            isSelected: state.isSelected(nodeID: node.id),
            highlightedPortID: highlighted,
            pendingPortID: pending,
            content: nodeContent(node)
        )
        .scaleEffect(state.zoom)
        .position(scene.nodeCenter(node))
        .contextMenu {
            if !isReadOnly, let nodeMenuBuilder { nodeMenuBuilder(node) }
        }
    }

    @ViewBuilder
    private func accessoryView(_ edge: GraphEdge<EdgePayload>,
                               scene: MeshCanvasScene<NodePayload, EdgePayload>) -> some View {
        if let wire = scene.wire(for: edge), let accessory = edgeAccessoryBuilder?(edge) {
            let mid = wire.point(at: 0.5)
            accessory.position(x: mid.x, y: mid.y - 64)
        }
    }

    // MARK: - Gestures

    private func dragGesture(scene: MeshCanvasScene<NodePayload, EdgePayload>) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                if state.drag == nil { beginDrag(at: value.startLocation, scene: scene) }
                switch state.drag {
                case .pan(let origin)?:
                    state.pan = CGSize(width: origin.width + value.translation.width,
                                       height: origin.height + value.translation.height)
                case .nodes(let origins)?:
                    for (id, origin) in origins {
                        var p = CGPoint(x: origin.x + value.translation.width / state.zoom,
                                        y: origin.y + value.translation.height / state.zoom)
                        if style.snapToGrid {
                            p.x = (p.x / style.gridSpacing).rounded() * style.gridSpacing
                            p.y = (p.y / style.gridSpacing).rounded() * style.gridSpacing
                        }
                        layout.setPosition(p, for: id)
                    }
                case .wire?:
                    state.wireEnd = value.location
                case .idle?, nil:
                    break
                }
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height) > 3
                switch state.drag {
                case .wire?:
                    if let end = scene.hitPort(value.location),
                       let picked = state.apply(.completeConnection(end)),
                       let oriented = mesh.orientedConnection(between: picked.0, and: picked.1) {
                        connectAction?(oriented.source, oriented.target)
                    } else {
                        state.apply(.cancel)
                    }
                case .nodes?:
                    if moved { movedAction?(state.selectedNodeIDs) }
                case .pan?:
                    if !moved {
                        if let edge = scene.hitEdge(value.location) {
                            state.apply(.select(.edge(edge)))
                        } else {
                            state.clearSelection()
                        }
                    }
                case .idle?, nil:
                    break
                }
                state.drag = nil
            }
    }

    private func beginDrag(at location: CGPoint, scene: MeshCanvasScene<NodePayload, EdgePayload>) {
        if !isReadOnly, connectAction != nil, let endpoint = scene.hitPort(location) {
            state.apply(.beginConnection(endpoint))
            state.wireEnd = location
            state.drag = .wire
        } else if let nodeID = scene.hitNode(location) {
            if !state.isSelected(nodeID: nodeID) { state.apply(.select(.node(nodeID))) }
            if isReadOnly {
                state.drag = .idle
            } else {
                state.drag = .nodes(origins: Dictionary(
                    uniqueKeysWithValues: state.selectedNodeIDs.map { ($0, layout.position(of: $0)) }
                ))
            }
        } else {
            state.drag = .pan(origin: state.pan)
        }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let origin = state.zoomOrigin ?? (state.zoom, state.pan)
                state.zoomOrigin = origin
                let zoom = min(max(origin.zoom * value.magnification, style.zoomRange.lowerBound),
                               style.zoomRange.upperBound)
                let k = zoom / origin.zoom
                state.zoom = zoom
                state.pan = CGSize(width: origin.pan.width * k, height: origin.pan.height * k)
            }
            .onEnded { _ in
                state.zoomOrigin = nil
            }
    }
}

// MARK: - Default node content

public extension MeshCanvas where NodeContent == Text {
    init(
        mesh: Mesh<NodePayload, EdgePayload>,
        layout: MeshLayout2D,
        state: MeshCanvasState,
        style: MeshCanvasStyle = MeshCanvasStyle()
    ) {
        self.init(mesh: mesh, layout: layout, state: state, style: style) { Text($0.title) }
    }
}

// MARK: - Configuration

public extension MeshCanvas {
    func nodeTint(_ tint: @escaping (GraphNode<NodePayload>) -> Color) -> Self {
        var copy = self
        copy.tintForNode = tint
        return copy
    }

    /// Colour of a port's dot, for example by its signal.
    func portTint(_ tint: @escaping (GraphPort) -> Color) -> Self {
        var copy = self
        copy.tintForPort = tint
        return copy
    }

    nonisolated static func defaultPortTint(_ port: GraphPort) -> Color {
        port.direction == .bidirectional ? .orange : .cyan
    }

    func edgeTint(_ tint: @escaping (GraphEdge<EdgePayload>) -> Color) -> Self {
        var copy = self
        copy.tintForEdge = tint
        return copy
    }

    func nodeContextMenu<Menu: View>(
        @ViewBuilder _ menu: @escaping (GraphNode<NodePayload>) -> Menu
    ) -> Self {
        var copy = self
        copy.nodeMenuBuilder = { AnyView(menu($0)) }
        return copy
    }

    func edgeContextMenu<Menu: View>(
        @ViewBuilder _ menu: @escaping (GraphEdge<EdgePayload>) -> Menu
    ) -> Self {
        var copy = self
        copy.edgeMenuBuilder = { AnyView(menu($0)) }
        return copy
    }

    /// Commands for empty canvas space, such as adding a node at the pointer.
    func canvasContextMenu<Menu: View>(
        @ViewBuilder _ menu: @escaping (MeshCanvasLocation) -> Menu
    ) -> Self {
        var copy = self
        copy.canvasMenuBuilder = { AnyView(menu($0)) }
        return copy
    }

    /// A view floated above the middle of an edge, or `nil` for none.
    func edgeAccessory<Accessory: View>(
        _ accessory: @escaping (GraphEdge<EdgePayload>) -> Accessory?
    ) -> Self {
        var copy = self
        copy.edgeAccessoryBuilder = { edge in accessory(edge).map { AnyView($0) } }
        return copy
    }

    /// Called with a correctly oriented source and target when the user draws
    /// a wire between two ports. Without it, wiring is disabled.
    func onConnect(_ action: @escaping (_ source: GraphEndpoint, _ target: GraphEndpoint) -> Void) -> Self {
        var copy = self
        copy.connectAction = action
        return copy
    }

    /// Called when the user presses Delete with nodes or an edge selected.
    func onDeleteSelection(_ action: @escaping (_ nodeIDs: Set<UUID>, _ edgeID: UUID?) -> Void) -> Self {
        var copy = self
        copy.deleteAction = action
        return copy
    }

    /// Called once when a node drag finishes.
    func onNodesMoved(_ action: @escaping (Set<UUID>) -> Void) -> Self {
        var copy = self
        copy.movedAction = action
        return copy
    }

    /// Disables wiring, moving, menus, and deletion. Panning, zooming, and
    /// selection still work.
    func readOnly(_ readOnly: Bool = true) -> Self {
        var copy = self
        copy.isReadOnly = readOnly
        return copy
    }

    func showsGrid(_ shows: Bool) -> Self {
        var copy = self
        copy.gridVisible = shows
        return copy
    }
}
