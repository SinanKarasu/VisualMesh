import SwiftUI
import VisualMesh

struct MeshNodeChrome<NodePayload, Content: View>: View {
    let node: GraphNode<NodePayload>
    let geometry: MeshCanvasGeometry
    let tint: Color
    let portTint: (GraphPort) -> Color
    let isSelected: Bool
    let highlightedPortID: UUID?
    let pendingPortID: UUID?
    let content: Content

    var body: some View {
        let size = geometry.nodeSize(node)
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(tint)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [.clear, .black.opacity(0.3)],
                                             startPoint: .top, endPoint: .bottom))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.yellow : Color.white.opacity(0.35),
                                lineWidth: isSelected ? 2.5 : 1)
                )
                .overlay(
                    content
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                )
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                .frame(width: size.width, height: size.height)

            ForEach(node.ports) { port in
                MeshPortView(
                    port: port,
                    color: portTint(port),
                    diameter: geometry.style.portDiameter,
                    labelAbove: geometry.isTopPort(port),
                    isHighlighted: port.id == highlightedPortID,
                    isPending: port.id == pendingPortID
                )
                .offset(geometry.portOffset(port, in: node))
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct MeshPortView: View {
    let port: GraphPort
    let color: Color
    let diameter: CGFloat
    let labelAbove: Bool
    let isHighlighted: Bool
    let isPending: Bool

    var body: some View {
        Circle()
            .fill(color)
            .overlay(
                Circle().stroke(
                    isPending ? Color.red : (isHighlighted ? Color.yellow : Color.black.opacity(0.6)),
                    lineWidth: isPending || isHighlighted ? 3 : 1.5
                )
            )
            .frame(width: diameter, height: diameter)
            .overlay(alignment: labelAbove ? .top : .bottom) {
                Text(port.name)
                    .font(.system(size: 9, weight: .medium))
                    .fixedSize()
                    .offset(y: labelAbove ? -12 : 12)
            }
            .help(port.name)
            .accessibilityLabel("\(port.name) port")
    }
}

struct MeshGridView: View {
    let spacing: CGFloat
    let origin: CGPoint

    var body: some View {
        Canvas { context, size in
            guard spacing >= 4 else { return }
            var lines = Path()
            var x = origin.x.truncatingRemainder(dividingBy: spacing)
            if x < 0 { x += spacing }
            while x <= size.width {
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y = origin.y.truncatingRemainder(dividingBy: spacing)
            if y < 0 { y += spacing }
            while y <= size.height {
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(lines, with: .color(.gray.opacity(0.22)), lineWidth: 0.5)

            var axes = Path()
            axes.move(to: CGPoint(x: origin.x, y: 0))
            axes.addLine(to: CGPoint(x: origin.x, y: size.height))
            axes.move(to: CGPoint(x: 0, y: origin.y))
            axes.addLine(to: CGPoint(x: size.width, y: origin.y))
            context.stroke(axes, with: .color(.red.opacity(0.35)), lineWidth: 0.75)
        }
    }
}
