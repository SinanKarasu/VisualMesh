// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VisualMesh",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VisualMeshSpatial", targets: ["VisualMeshSpatial"]),
        .library(name: "VisualMesh", targets: ["VisualMesh"]),
        .library(name: "VisualMeshExamples", targets: ["VisualMeshExamples"]),
    ],
    dependencies: [.package(path: "../SpatialInput")],
    targets: [
        .target(name: "VisualMeshSpatial", dependencies: ["VisualMesh", .product(name: "SpatialInput", package: "SpatialInput")]),
        .testTarget(name: "VisualMeshSpatialTests", dependencies: ["VisualMeshSpatial", "VisualMesh", .product(name: "SpatialInput", package: "SpatialInput")]),
        .target(name: "VisualMesh"),
        .target(name: "VisualMeshExamples", dependencies: ["VisualMesh"]),
        .testTarget(
            name: "VisualMeshTests",
            dependencies: ["VisualMesh", "VisualMeshExamples"]
        ),
    ]
)
