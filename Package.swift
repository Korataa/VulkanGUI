// swift-tools-version: 6.0

import PackageDescription

var unsafeIncludeFlags = [""]
#if os(Windows)
    // Vulkan from SDK, SDL3 from vcpkg
    let vulkanIncludePath = "C:\\VulkanSDK\\1.4.341.1\\Include"
    let vcpkgIncludePath = "C:\\vcpkg\\installed\\x64-windows\\include"
    unsafeIncludeFlags = ["-I\(vulkanIncludePath)", "-I\(vcpkgIncludePath)"]
#else
    unsafeIncludeFlags = 
    [
        "-I/usr/include"
    ]
#endif

var unsafeLibFlags = [""]
#if os(Windows)
    // SDL3 from vcpkg, Vulkan from SDK
    let vulkanLibPath = "C:\\VulkanSDK\\1.4.341.1\\Lib"
    let vcpkgLibPath = "C:\\vcpkg\\installed\\x64-windows\\lib"
    unsafeLibFlags = 
    [
        "-L\(vulkanLibPath)",
        "-L\(vcpkgLibPath)",
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
            name: "Core",
            dependencies: [],
            path: "Sources/Core",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "Audio",
            dependencies: ["Platform"],
            path: "Sources/Audio",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "Platform",
            dependencies: ["Core", "CSDL3", "Cvulkan"],
            path: "Sources/Platform",
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
        .target(
            name: "Graphics",
            dependencies: ["Core", "Platform", "CSDL3", "Cvulkan", "Cvma", "Cgltf", "Cstb_image"],
            path: "Sources/Graphics",
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
        .target(
            name: "Assets",
            dependencies: ["Core", "Graphics", "Cgltf", "Cstb_image"],
            path: "Sources/Assets",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),

        .executableTarget(
            name: "DeckRPG",
            dependencies: ["Core", "Platform", "Audio", "Graphics", "Assets"],
            path: "Sources/Runtime",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        )

    ],
    cxxLanguageStandard: .cxx17
)
