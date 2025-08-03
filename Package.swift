// swift-tools-version: 6.0

import PackageDescription

var unsafeIncludeFlags = [""]
#if os(Windows)
    // Allow override via environment variable, fallback to vcpkg default
    let windowsIncludePath = ProcessInfo.processInfo.environment["VULKAN_SDK_INCLUDE"] ?? "Z:\\dev\\vcpkg\\installed\\x64-windows\\include"
    unsafeIncludeFlags = ["-I\(windowsIncludePath)"]
#else
    unsafeIncludeFlags = 
    [
        "-I/usr/include"
    ]
#endif

var unsafeLibFlags = [""]
#if os(Windows)
    // Allow override via environment variable, fallback to vcpkg default
    let windowsLibPath = ProcessInfo.processInfo.environment["VULKAN_SDK_LIB"] ?? "Z:\\dev\\vcpkg\\installed\\x64-windows\\lib"
    unsafeLibFlags = 
    [
        "-L\(windowsLibPath)",
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
            name: "Cstb_image",
            dependencies: [],
            path: "Sources/ThirdParty/Cstb_image",
            sources: ["stb_image.c"],
            publicHeadersPath: "."
        ),
        .target(
            name: "Cvma",
            dependencies: ["Cvulkan"],
            path: "Sources/ThirdParty/Cvma",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(unsafeIncludeFlags)
            ]
        ),
        .target(
            name: "Modules",
            dependencies: ["CSDL3", "Cvulkan", "Cvma", "Cgltf", "Cstb_image"],
            path: "Sources/Modules",
            cSettings: [
                .unsafeFlags(unsafeIncludeFlags)
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
