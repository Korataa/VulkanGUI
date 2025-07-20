// swift-tools-version: 6.0

import PackageDescription

var unsafeIncludeFlags = [""]
#if os(Windows)
    unsafeIncludeFlags = ["-IZ:\\dev\\vcpkg\\installed\\x64-windows\\include"]
#else
    unsafeIncludeFlags = 
    [
        "-I/usr/include"
    ]
#endif

var unsafeLibFlags = [""]
#if os(Windows)
    unsafeLibFlags = 
    [
        "-LZ:\\dev\\vcpkg\\installed\\x64-windows\\lib",
        "-lSDL3",
        "-lvulkan-1"
    ]
#else
    unsafeLibFlags =
    [
        "-L/usr/lib",
        "-lSDL3",
        "-lvulkan"
    ]
#endif

let package = Package(
    name: "DeckRPG",
    products: [
        .executable(
            name: "DeckRPG",
            targets: ["DeckRPG"]
        )
    ],
    targets: [
        /*.target(name: "Platform", dependencies: ["CSDL3"]),
        .target(name: "Renderer", dependencies: ["Platform"]),
        .target(name: "Core", dependencies: ["Platform", "Renderer"]),
        .target(name: "Math", dependencies: []),*/      

        .systemLibrary(
            name: "CSDL3",
            path: "Sources/ThirdParty/CSDL3"
        ),
        .systemLibrary(
            name: "Cvulkan",
            path: "Sources/ThirdParty/Cvulkan"
        ),
        .target(
            name: "Cgltf",
            dependencies: [],
            path: "Sources/ThirdParty/Cgltf",
            sources: ["cgltf.c", "cgltf.h"],
            publicHeadersPath: "."
        ),
        .target(
            name: "Cvma",
            dependencies: ["Cvulkan"],
            path: "Sources/ThirdParty/Cvma",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-IZ:\\dev\\vcpkg\\installed\\x64-windows\\include"])
            ]
        ),
        .target(
            name: "Modules",
            dependencies: ["CSDL3", "Cvulkan", "Cvma", "Cgltf"],
            path: "Sources/Modules",
            cSettings: [
                .unsafeFlags(["-IZ:\\dev\\vcpkg\\installed\\x64-windows\\include"])
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            linkerSettings: [
                .unsafeFlags(unsafeLibFlags)
            ]
        ),
        .executableTarget(
            name: "DeckRPG",
            dependencies: ["Modules"],
            path: "Sources/Runtime",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        )

    ],
    cxxLanguageStandard: .cxx17
)
