import XCTest
@testable import OpenWhisperShared

final class KeychainStoreTests: XCTestCase {
    private let account = "test.keychain.\(UUID().uuidString)"

    override func tearDown() {
        KeychainStore.delete(account: account)
        UserDefaults.standard.removeObject(forKey: AppGroup.cloudApiKeyKey)
        UserDefaults(suiteName: AppGroup.identifier)?.removeObject(forKey: AppGroup.cloudApiKeyKey)
        super.tearDown()
    }

    func testSetAndReadRoundTrip() {
        XCTAssertTrue(KeychainStore.set("sk-or-test-value", account: account))
        XCTAssertEqual(KeychainStore.string(forAccount: account), "sk-or-test-value")
    }

    func testReadCachesValueInMemory() {
        XCTAssertTrue(KeychainStore.set("cached-value", account: account))
        // First read populates the cache; subsequent reads hit memory.
        XCTAssertEqual(KeychainStore.string(forAccount: account), "cached-value")
        XCTAssertEqual(KeychainStore.string(forAccount: account), "cached-value")
    }

    func testDeleteClearsCacheAndKeychain() {
        XCTAssertTrue(KeychainStore.set("to-delete", account: account))
        XCTAssertEqual(KeychainStore.string(forAccount: account), "to-delete")

        XCTAssertTrue(KeychainStore.delete(account: account))
        XCTAssertNil(KeychainStore.string(forAccount: account))
    }

    func testSetOverwritesAndInvalidatesCache() {
        XCTAssertTrue(KeychainStore.set("first", account: account))
        XCTAssertEqual(KeychainStore.string(forAccount: account), "first")

        XCTAssertTrue(KeychainStore.set("second", account: account))
        XCTAssertEqual(KeychainStore.string(forAccount: account), "second")
    }
}

final class OpenRouterApiKeyStoreTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppGroup.cloudApiKeyKey)
        UserDefaults(suiteName: AppGroup.identifier)?.removeObject(forKey: AppGroup.cloudApiKeyKey)
        // OpenRouterApiKeyStore stores under a private account; the migration
        // tests share the real keychain entry, so clear it (and the memory
        // cache) between tests to keep them isolated.
        KeychainStore.delete(account: "openrouter.apiKey")
        super.tearDown()
    }

    func testMigratesLegacyUserDefaultsValue() {
        UserDefaults.standard.set("sk-or-legacy", forKey: AppGroup.cloudApiKeyKey)
        XCTAssertEqual(OpenRouterApiKeyStore.value, "sk-or-legacy")
        XCTAssertTrue(OpenRouterApiKeyStore.hasValue)
    }

    func testMigratesLegacyAppGroupValue() {
        UserDefaults(suiteName: AppGroup.identifier)?.set("sk-or-group", forKey: AppGroup.cloudApiKeyKey)
        XCTAssertEqual(OpenRouterApiKeyStore.value, "sk-or-group")
    }

    func testSetStoresAndTrimsWhitespace() {
        OpenRouterApiKeyStore.set("  sk-or-trimmed  ")
        XCTAssertEqual(OpenRouterApiKeyStore.value, "sk-or-trimmed")
    }

    func testEmptySetDeletes() {
        OpenRouterApiKeyStore.set("sk-or-keep")
        XCTAssertTrue(OpenRouterApiKeyStore.hasValue)
        OpenRouterApiKeyStore.set("")
        XCTAssertFalse(OpenRouterApiKeyStore.hasValue)
        XCTAssertEqual(OpenRouterApiKeyStore.value, "")
    }
}

final class InstallIDTests: XCTestCase {
    func testIsStableAcrossReads() {
        let first = InstallID.value
        let second = InstallID.value
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    func testIsUUIDShaped() {
        let id = InstallID.value
        XCTAssertTrue(UUID(uuidString: id) != nil)
    }
}

final class AnalyticsPayloadTests: XCTestCase {
    func testEventEncodesExpectedFieldsOnly() throws {
        let event = UsageAnalytics.Event(
            feature: .formatAndTranslate,
            ok: true,
            latencyMs: 812,
            chars: 214,
            style: "formal",
            sourceLanguage: "pl",
            targetLanguage: "en"
        )
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["feature"] as? String, "formatAndTranslate")
        XCTAssertEqual(json["ok"] as? Bool, true)
        XCTAssertEqual(json["latencyMs"] as? Int, 812)
        XCTAssertEqual(json["chars"] as? Int, 214)
        XCTAssertEqual(json["style"] as? String, "formal")
        XCTAssertEqual(json["sourceLanguage"] as? String, "pl")
        XCTAssertEqual(json["targetLanguage"] as? String, "en")

        // Privacy guard: the payload must never carry transcript text.
        XCTAssertNil(json["text"])
        XCTAssertNil(json["transcript"])
        XCTAssertNil(json["content"])
        XCTAssertEqual(json.keys.count, 7)
    }

    func testFeatureRawValuesAreStable() {
        XCTAssertEqual(UsageAnalytics.Feature.format.rawValue, "format")
        XCTAssertEqual(UsageAnalytics.Feature.formatAndTranslate.rawValue, "formatAndTranslate")
        XCTAssertEqual(UsageAnalytics.Feature.translateOnly.rawValue, "translateOnly")
    }

    func testAnalyticsDefaultsToOff() {
        UserDefaults.standard.removeObject(forKey: AppGroup.usageAnalyticsEnabledKey)
        UserDefaults(suiteName: AppGroup.identifier)?.removeObject(forKey: AppGroup.usageAnalyticsEnabledKey)
        XCTAssertFalse(UsageAnalytics.isEnabled)
    }
}
