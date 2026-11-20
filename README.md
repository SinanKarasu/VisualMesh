# VisualMesh

A domain-neutral graph foundation for visual editors: typed ports,
reusable subgraph definitions with independently wired instances, and a
device-independent interaction vocabulary. It is shared by VisuSig (audio,
MIDI, DAW) and AtlasConcept (ATLAS / ATML test descriptions).

Platforms: macOS 14+, visionOS 1+.

## Products

| Product | Depends on | Contents |
| --- | --- | --- |
| `VisualMesh` | Foundation, Observation | `Mesh`, `GraphNode`, `GraphPort`, `GraphEdge`; `MeshDefinition` / `MeshLibrary` hierarchy; `MeshInteractionIntent`; signal telemetry and software instruments. No UI frameworks. |
| `VisualMeshUI` | `VisualMesh`, SwiftUI | `MeshCanvas` 2D editor, `MeshLayout2D`, `MeshCanvasState`, signal-instrument views. No AppKit. |
| `VisualMeshExamples` | `VisualMesh` | WITS PACK, ATE adapter, and ATLAS example graphs. |

## Boundaries

- **Topology is not layout.** A `Mesh` holds nodes, ports, and edges only.
  Positions live in a presentation's layout (`MeshLayout2D` for the 2D
  canvas), so a spatial renderer can lay out the same graph differently.
- **Payloads are the host's.** Node and edge payloads are generic. Keep them
  durable and serializable; keep live runtime objects (audio engines, Audio
  Units, instrument connections) in host adapters keyed by stable IDs.
- **The canvas reports, the host decides.** `MeshCanvas` edits layout and
  view state itself, but reports connections and deletions through
  `onConnect` and `onDeleteSelection`, so a host with a running engine applies
  graph edits in its own order.
- **Input is intent-based.** Mouse, trackpad, and spatial input all drive
  `MeshCanvasState` through `MeshInteractionIntent`.

## Using the canvas

```swift
import VisualMesh
import VisualMeshUI

MeshCanvas(mesh: mesh, layout: layout, state: canvasState) { node in
    Text(node.title)
}
.nodeTint { node in .indigo }
.onConnect { source, target in
    try? mesh.connect(sourceNodeID: source.nodeID, sourcePortID: source.portID,
                      targetNodeID: target.nodeID, targetPortID: target.portID,
                      payload: MyEdge())
}
.canvasContextMenu { location in
    Button("Add Node") { addNode(at: location.meshPoint) }
}
```

## Testing

```sh
swift test
```

## Acknowledgements

VisualMesh began with Warren Burton's tutorial
[Creating a Mind-Map UI in SwiftUI](https://forums.kodeco.com/t/creating-a-mind-map-ui-in-swiftui-raywenderlich-com/102548)
(raywenderlich.com, now Kodeco, March 2020). Its mesh of nodes and edges on a
pannable, zoomable surface, with the model kept separate from the views that
draw it, inspired VisuSig's first node editor in 2021–22.

That editor has since been replaced, and replacing it is where most of the
learning happened. What came out of it is what VisualMesh is now: a graph
generalized over any node and edge payload, with typed ports and reusable
definitions, and durable payloads kept apart from the live runtimes that act
on them. No code from the tutorial remains; the inspiration does.
