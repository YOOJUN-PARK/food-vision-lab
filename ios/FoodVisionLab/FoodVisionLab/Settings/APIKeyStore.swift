//
//  APIKeyStore.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/25/26.
//

import Foundation
import Security

enum APIProvider: String, CaseIterable, Identifiable {
    case claude = "Claude"

    var id: Self { self }
}

enum APIKeyStore {
    private static func query(for provider: APIProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.YOOJUN.FoodVisionLab.\(provider.rawValue)",
            kSecAttrAccount as String: "api-key"
        ]
    }

    static func read(_ provider: APIProvider) throws -> String? {
        var request = query(for: provider)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw Error.invalidData
        }
        return key
    }

    static func save(_ key: String, for provider: APIProvider) throws {
        let data = Data(key.utf8)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query(for: provider) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(for: provider)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    static func delete(_ provider: APIProvider) throws {
        let status = SecItemDelete(query(for: provider) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func check(_ status: OSStatus) throws {
        if status != errSecSuccess { throw Error.operationFailed(status) }
    }

    private enum Error: LocalizedError {
        case invalidData
        case operationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidData: "저장된 API 키를 읽지 못했습니다. 다시 저장해 주세요."
            case let .operationFailed(status): "API 키를 처리하지 못했습니다. 보안 오류: \(status)"
            }
        }
    }
}
