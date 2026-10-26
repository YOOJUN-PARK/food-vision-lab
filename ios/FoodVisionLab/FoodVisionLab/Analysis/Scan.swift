//
//  Scan.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/25/26.
//

import Foundation
import FoundationModels
import ImageIO
import MenuRecognition
import SubjectCutout
import SwiftData
import UIKit

@Model
final class Scan {
    static let directory = URL.applicationSupportDirectory.appendingPathComponent("Cutouts", isDirectory: true)

    var date = Date.now
    @Attribute(.externalStorage) var photo: Data
    @Attribute(.externalStorage) var thumbnail: Data?
    var folder: String
    var dishes: [Dish]
    var durations: [AnalysisModel: TimeInterval] = [:]
    var usages: [AnalysisModel: TokenUsage] = [:]

    init(photo: Data, cutouts: [Cutout]) {
        self.photo = photo
        folder = cutouts.first?.url.deletingLastPathComponent().lastPathComponent ?? ""
        dishes = cutouts.map { Dish(id: $0.id, number: $0.number, bounds: $0.bounds, cropBounds: $0.cropBounds) }
        thumbnail = CGImageSourceCreateWithData(photo as CFData, nil)
            .flatMap {
                CGImageSourceCreateThumbnailAtIndex($0, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1024
                ] as CFDictionary)
            }
            .flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.8) }
    }

    var title: String {
        date.formatted(.dateTime.month().day().weekday().hour().minute().locale(Locale(identifier: "ko_KR")))
    }

    var folderURL: URL { Self.directory.appendingPathComponent(folder, isDirectory: true) }

    var cutouts: [Cutout] { dishes.map(cutout) }

    func cutout(for dish: Dish) -> Cutout {
        Cutout(id: dish.id, number: dish.number, bounds: dish.bounds, cropBounds: dish.cropBounds, directory: folderURL)
    }
}

struct TokenUsage: Codable {
    var input = 0
    var cachedInput: Int?
    var output = 0

    mutating func add(_ usage: LanguageModelSession.Usage) {
        input += usage.input.totalTokenCount
        cachedInput = (cachedInput ?? 0) + usage.input.cachedTokenCount
        output += usage.output.totalTokenCount
    }
}

struct Dish: Codable, Identifiable {
    let id: UUID
    let number: Int
    let bounds: CGRect
    let cropBounds: CGRect
    var results: [AnalysisModel: Result] = [:]

    struct Result: Codable {
        var name: String?
        var alternatives: [String] = []
        var reason: String?
        var duration: TimeInterval
        var mode: MenuRecognitionMode?

        init(_ prediction: MenuPrediction, duration: TimeInterval, mode: MenuRecognitionMode? = nil) {
            switch prediction {
            case let .identified(match):
                name = match.name
                alternatives = match.alternatives
            case let .unidentified(reason):
                self.reason = reason
            }
            self.duration = duration
            self.mode = mode
        }
    }
}
