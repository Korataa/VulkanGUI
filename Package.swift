// swift-tools-version: 6.0

import PackageDescription
import Foundation

var unsafeIncludeFlags = [""]
#if os(Windows)
    // Vulkan from SDK, SDL3 from vcpkg
    let vulkanRoot = ProcessInfo.processInfo.environment["VULKAN_SDK"] ?? "C:\\VulkanSDK\\1.4.341.1"
    let vcpkgRoot = ProcessInfo.processInfo.environment["VCPKG_ROOT"] ?? "C:\\vcpkg"
    let vulkanIncludePath = "\(vulkanRoot)\\Include"
    let vcpkgIncludePath = "\(vcpkgRoot)\\installed\\x64-windows\\include"
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
    let vulkanLibPath = "\(vulkanRoot)\\Lib"
    let vcpkgLibPath = "\(vcpkgRoot)\\installed\\x64-windows\\lib"
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
    name: "DeckRPGUI",
    products: [
        .library(
            name: "DeckRPGUI",
            targets: ["DeckRPGUI"]
        ),
        .executable(
            name: "GUIExample",
            targets: ["GUIExample"]
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
            dependencies: ["Core", "Math", "Platform", "CSDL3", "Cvulkan", "Cvma", "Cstb_image", "Cstb_truetype", "Logging"],
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
            name: "UI",
            dependencies: ["Core", "Math", "Graphics", "Cstb_truetype", "Cstb_image", "Logging"],
            path: "Sources/UI",
            exclude: ["README.md"],
            cSettings: [
                .unsafeFlags(unsafeIncludeFlags)
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "DeckRPGUI",
            dependencies: ["Core", "Math", "Platform", "Graphics", "UI", "Logging"],
            path: "Sources/DeckRPGUI",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .executableTarget(
            name: "GUIExample",
            dependencies: ["DeckRPGUI"],
            path: "Examples/GUIExample"
        ),
        .testTarget(
            name: "GraphicsTests",
            dependencies: ["DeckRPGUI", "Graphics", "Core", "UI", "Platform", "CSDL3", "Cvulkan", "Cvma"],
            path: "Tests/GraphicsTests"
        )
    ],
    cxxLanguageStandard: .cxx17
)
