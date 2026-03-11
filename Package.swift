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
            publicHeadersPath: ".",
            cSettings: [
                // Third-party library: silence CRT deprecation spam on Windows.
                .define("_CRT_SECURE_NO_WARNINGS", .when(platforms: [.windows]))
            ]
        ),
        .target(
            name: "Cstb_image",
            dependencies: [],
            path: "Sources/ThirdParty/Cstb_image",
            sources: ["stb_image.c"],
            publicHeadersPath: "."
        ),
        .target(
            name: "Cstb_truetype",
            dependencies: [],
            path: "Sources/ThirdParty/Cstb_truetype",
            sources: ["stb_truetype.c"],
            publicHeadersPath: "."
        ),
        .target(
            name: "Cvma",
            dependencies: ["Cvulkan"],
            path: "Sources/ThirdParty/Cvma",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(unsafeIncludeFlags)
            ],
            cxxSettings: [
                .unsafeFlags(unsafeIncludeFlags + ["-Wno-nullability-completeness"])
            ]
        ),
        .target(
            name: "Math",
            dependencies: [],
            path: "Sources/Math",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "Core",
            dependencies: ["Math"],
            path: "Sources/Core",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "Audio",
            dependencies: ["Platform"],
            path: "Sources/Audio",
            cSettings: [
                .unsafeFlags(unsafeIncludeFlags)
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "Platform",
            dependencies: ["Core", "Math", "CSDL3", "Cvulkan"],
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
            name: "Logging",
            dependencies: [],
            path: "Sources/Logging"
        ),
        .target(
            name: "Graphics",
            dependencies: ["Core", "Math", "Platform", "CSDL3", "Cvulkan", "Cvma", "Cgltf", "Cstb_image", "Cstb_truetype", "Logging"],
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
            dependencies: ["Core", "Math", "Graphics", "Cgltf", "Cstb_image"],
            path: "Sources/Assets",
            cSettings: [
                .unsafeFlags(unsafeIncludeFlags)
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "UI",
            dependencies: ["Core", "Math", "Graphics", "Cstb_truetype", "Cstb_image", "Logging"],
            path: "Sources/UI",
            cSettings: [
                .unsafeFlags(unsafeIncludeFlags)
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),

        .executableTarget(
            name: "DeckRPG",
            dependencies: ["Core", "Math", "Platform", "Audio", "Graphics", "Assets", "UI", "Logging"],
            path: "Sources/Runtime",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        )

    ],
    cxxLanguageStandard: .cxx17
)
