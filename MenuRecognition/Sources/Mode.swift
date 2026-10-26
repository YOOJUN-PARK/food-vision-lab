//
//  Mode.swift
//  MenuRecognition
//
//  Created by YOOJUN PARK on 10/26/26.
//

public enum MenuRecognitionMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case fast
    case balanced
    case accurate

    public var id: Self { self }

    public var name: String {
        switch self {
        case .fast: "빠름"
        case .balanced: "균형"
        case .accurate: "정확"
        }
    }
}
