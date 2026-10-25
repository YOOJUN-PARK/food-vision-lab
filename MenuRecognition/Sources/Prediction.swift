//
//  Prediction.swift
//  MenuRecognition
//
//  Created by YOOJUN PARK on 10/23/26.
//

import Foundation
import FoundationModels

@Generable(description: "The menu name of the item. Choose identified when you can name it, or unidentified with a short reason when you cannot tell what it is.")
public enum MenuPrediction: Sendable {
    case identified(Match)
    case unidentified(reason: String)

    @Generable
    public struct Match: Sendable {
        @Guide(description: "The most likely name a menu would use for the item.")
        public var name: String

        @Guide(description: "Up to three other plausible names, most likely first. Never repeat the name or list synonyms; leave it empty when there are none.", .count(0...3))
        public var alternatives: [String]

        public init(name: String, alternatives: [String]) {
            self.name = name
            self.alternatives = alternatives
        }
    }

    func removingDuplicateAlternatives() -> Self {
        guard case .identified(var match) = self else { return self }
        func key(_ name: String) -> String {
            name.filter { !$0.isWhitespace }.lowercased()
        }
        match.name = match.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var names: Set<String> = [key(match.name)]
        match.alternatives = Array(match.alternatives
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && names.insert(key($0)).inserted }
            .prefix(3))
        return .identified(match)
    }
}
