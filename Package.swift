// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VisualMesh",
    platforms: [.macOS(.v14), .iOS(.v18), .visionOS(.v1)],
    products: [
        .library(name: "VisualMesh", targets: ["VisualMesh"]),
        .library(name: "VisualMeshUI", targets: ["VisualMeshUI"]),
        .library(name: "VisualMeshExamples", targets: ["VisualMeshExamples"]),
    ],
    targets: [
        /// Platform-neutral graph, hierarchy, and interaction vocabulary.
        /// No SwiftUI, AppKit, or RealityKit.
        .target(name: "VisualMesh"),
        /// SwiftUI 2D editor over the core model (macOS, iPadOS, and visionOS).
        .target(name: "VisualMeshUI", dependencies: ["VisualMesh"]),
        .target(name: "VisualMeshExamples", dependencies: ["VisualMesh"]),
        .testTarget(
            name: "VisualMeshTests",
            dependencies: ["VisualMesh", "VisualMeshExamples"]
        ),
        .testTarget(
            name: "VisualMeshUITests",
            dependencies: ["VisualMeshUI", "VisualMesh"]
        ),
    ]
)
