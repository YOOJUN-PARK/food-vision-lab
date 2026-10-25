// swift-tools-version: 6.4
//
//  Package.swift
//  MenuRecognition
//
//  Created by YOOJUN PARK on 10/23/26.
//

import PackageDescription

let package = Package(
    name: "MenuRecognition",
    platforms: [.iOS("27.0")],
    products: [.library(name: "MenuRecognition", targets: ["MenuRecognition"])],
    targets: [
        .target(name: "MenuRecognition", path: "Sources"),
        .testTarget(name: "MenuRecognitionTests", dependencies: ["MenuRecognition"], path: "Tests")
    ]
)
