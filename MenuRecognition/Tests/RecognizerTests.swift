//
//  RecognizerTests.swift
//  MenuRecognition
//
//  Created by YOOJUN PARK on 10/23/26.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MenuRecognition

final class RecognizerTests: XCTestCase {
    func testRemovesRepeatedAndEmptyAlternativesWithoutReordering() {
        let prediction = MenuPrediction.identified(.init(
            name: " 김치 ",
            alternatives: ["김 치", " ", " 배추김치 ", "배추 김치", "겉절이", "백김치", "깍두기"]
        )).removingDuplicateAlternatives()

        guard case let .identified(match) = prediction else {
            return XCTFail("Expected identified")
        }
        XCTAssertEqual(match.name, "김치")
        XCTAssertEqual(match.alternatives, ["배추김치", "겉절이", "백김치"])
    }

    func testAllowsNoAlternativesAndPreservesUnidentifiedReason() {
        let identified = MenuPrediction.identified(.init(
            name: "밥", alternatives: ["밥", " 밥 "]
        )).removingDuplicateAlternatives()
        guard case let .identified(match) = identified else {
            return XCTFail("Expected identified")
        }
        XCTAssertTrue(match.alternatives.isEmpty)

        let reason = "사진이 흐려 음식 종류를 구분하기 어렵습니다."
        let unidentified = MenuPrediction.unidentified(reason: reason).removingDuplicateAlternatives()
        guard case let .unidentified(result) = unidentified else {
            return XCTFail("Expected unidentified")
        }
        XCTAssertEqual(result, reason)
    }

    func testImagePreparationLimitsSizeAndPreservesOriginal() throws {
        let url = try writeImage(width: 2048, height: 1024)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = try Data(contentsOf: url)

        let image = try MenuRecognizer.image(at: url)

        XCTAssertEqual(image.width, 1024)
        XCTAssertEqual(image.height, 512)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(pixels[3], 0)
        let center = (image.height / 2 * image.width + image.width / 2) * 4
        XCTAssertEqual(pixels[center + 3], 255)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testImagePreparationAppliesOrientationWithoutUpscaling() throws {
        let url = try writeImage(width: 80, height: 40, orientation: .right)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try MenuRecognizer.image(at: url)

        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 80)
    }

    func testRejectsMissingImagesBeforeUsingModel() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        do {
            _ = try await MenuRecognizer().recognize(imageURL: url)
            XCTFail("Expected invalidImage")
        } catch MenuRecognizer.Error.invalidImage {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancelledRequestDoesNotReadImagesOrUseModel() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await MenuRecognizer().recognize(imageURL: url)
        }
        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBatchMatchesReorderedResultsAndNormalizesAlternatives() throws {
        let first = UUID()
        let second = UUID()
        let batch = MenuRecognizer.BatchAnalysis(items: [
            .init(id: second.uuidString, analysis: .init(
                observation: "The photo is blurry.",
                prediction: .unidentified(reason: "음식의 형태를 구분하기 어렵습니다.")
            )),
            .init(id: first.uuidString, analysis: .init(
                observation: "Cabbage with red seasoning.",
                prediction: .identified(.init(name: " 김치 ", alternatives: ["김 치", "겉절이", "겉절이"]))
            ))
        ])

        let predictions = try batch.predictions(for: [first, second])

        XCTAssertEqual(predictions.count, 2)
        guard case let .identified(match) = predictions[first],
              case let .unidentified(reason) = predictions[second] else {
            return XCTFail("Expected results matched by identifier")
        }
        XCTAssertEqual(match.name, "김치")
        XCTAssertEqual(match.alternatives, ["겉절이"])
        XCTAssertEqual(reason, "음식의 형태를 구분하기 어렵습니다.")
    }

    func testBatchRejectsMissingDuplicateUnknownAndMalformedIdentifiers() {
        let first = UUID()
        let second = UUID()
        let invalidIdentifiers = [
            [first.uuidString],
            [first.uuidString, first.uuidString],
            [first.uuidString, UUID().uuidString],
            [first.uuidString, "invalid"]
        ]
        for identifiers in invalidIdentifiers {
            let batch = MenuRecognizer.BatchAnalysis(items: identifiers.map { id in
                .init(id: id, analysis: .init(
                    observation: "A bowl of rice.", prediction: .identified(.init(name: "밥", alternatives: []))
                ))
            })
            XCTAssertThrowsError(try batch.predictions(for: [first, second])) { error in
                guard case MenuRecognizer.Error.invalidResults = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testEmptyBatchDoesNotUseModel() async throws {
        let result = try await MenuRecognizer().recognize([])
        XCTAssertTrue(result.predictions.isEmpty)
        XCTAssertNil(result.usage)
    }

    func testBatchRejectsDuplicateInputsBeforeReadingImagesOrUsingModel() async {
        let id = UUID()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let input = MenuRecognizer.Input(id: id, imageURL: url)
        do {
            _ = try await MenuRecognizer().recognize([input, input])
            XCTFail("Expected duplicateInputs")
        } catch MenuRecognizer.Error.duplicateInputs {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancelledBatchDoesNotReadImagesOrUseModel() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await MenuRecognizer().recognize([.init(id: UUID(), imageURL: url)])
        }
        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func writeImage(
        width: Int, height: Int, orientation: CGImagePropertyOrientation = .up
    ) throws -> URL {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        let image = try XCTUnwrap(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyOrientation: orientation.rawValue
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
