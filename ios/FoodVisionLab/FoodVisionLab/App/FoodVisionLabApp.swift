//
//  FoodVisionLabApp.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/23/26.
//

import SwiftData
import SwiftUI

@main
struct FoodVisionLabApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Scan.self)
    }
}
