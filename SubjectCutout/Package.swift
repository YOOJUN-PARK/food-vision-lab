// swift-tools-version: 6.4
//
//  Package.swift
//  SubjectCutout
//
//  Created by YOOJUN PARK on 10/23/26.
//

import PackageDescription

let package = Package(
    name: "SubjectCutout",
    platforms: [.iOS("27.0")],
    products: [.library(name: "SubjectCutout", targets: ["SubjectCutout"])],
    targets: [
        .target(name: "SubjectCutout", path: "Sources"),
        .testTarget(name: "SubjectCutoutTests", dependencies: ["SubjectCutout"], path: "Tests")
    ]
)
