import XCTest

final class ConfigModelTests: XCTestCase {
    private func makeValidConfig() -> ConfigModel {
        var config = ConfigModel()
        config.proxyServerAddress = "example.com"
        config.proxyServerPort = 8090
        config.bindAddress = "127.0.0.1"
        config.listenPort = 8089
        config.rsaPublicKey = "-----BEGIN PUBLIC KEY-----\nABC\n-----END PUBLIC KEY-----"
        config.cipher = "aes-256-ctr"
        config.timeout = 240
        config.workers = 2
        return config
    }

    func testValidConfigurationPassesValidation() {
        XCTAssertNil(makeValidConfig().validationError())
    }

    func testEmptyServerIsRejected() {
        var config = makeValidConfig()
        config.proxyServerAddress = "  "
        XCTAssertNotNil(config.validationError())
    }

    func testServerWithSchemeIsRejected() {
        var config = makeValidConfig()
        config.proxyServerAddress = "http://example.com"
        XCTAssertNotNil(config.validationError())
    }

    func testZeroPortsAreRejected() {
        var config = makeValidConfig()
        config.proxyServerPort = 0
        XCTAssertNotNil(config.validationError())

        config = makeValidConfig()
        config.listenPort = 0
        XCTAssertNotNil(config.validationError())
    }

    func testInvalidBindAddressIsRejected() {
        var config = makeValidConfig()
        config.bindAddress = "not-an-ip"
        XCTAssertNotNil(config.validationError())
    }

    func testLoopbackAndLocalhostBindAddressesAreAccepted() {
        var config = makeValidConfig()
        config.bindAddress = "0.0.0.0"
        XCTAssertNil(config.validationError())

        config.bindAddress = "::1"
        XCTAssertNil(config.validationError())

        config.bindAddress = "localhost"
        XCTAssertNil(config.validationError())
    }

    func testNonPEMPublicKeyIsRejected() {
        var config = makeValidConfig()
        config.rsaPublicKey = "not a PEM key"
        XCTAssertNotNil(config.validationError())
    }

    func testUnsupportedCipherIsRejected() {
        var config = makeValidConfig()
        config.cipher = "aes-999-ctr"
        XCTAssertNotNil(config.validationError())
    }

    func testOutOfRangeTimeoutAndWorkersAreRejected() {
        var config = makeValidConfig()
        config.timeout = 10
        XCTAssertNotNil(config.validationError())

        config = makeValidConfig()
        config.workers = 0
        XCTAssertNotNil(config.validationError())
    }

    func testNormalizationTrimsUserInput() {
        var config = makeValidConfig()
        config.proxyServerAddress = "  example.com  "
        config.bindAddress = "  127.0.0.1  "
        config.rsaPublicKey = "  -----BEGIN PUBLIC KEY-----\nABC\n-----END PUBLIC KEY-----  "

        let normalized = config.normalized()
        XCTAssertEqual(normalized.proxyServerAddress, "example.com")
        XCTAssertEqual(normalized.bindAddress, "127.0.0.1")
        XCTAssertTrue(normalized.rsaPublicKey.hasPrefix("-----BEGIN PUBLIC KEY-----"))
    }

    func testLANExposureDetection() {
        var config = makeValidConfig()

        config.bindAddress = "127.0.0.1"
        XCTAssertFalse(config.isExposingToLAN)

        config.bindAddress = "::1"
        XCTAssertFalse(config.isExposingToLAN)

        config.bindAddress = "localhost"
        XCTAssertFalse(config.isExposingToLAN)

        config.bindAddress = "0.0.0.0"
        XCTAssertTrue(config.isExposingToLAN)

        config.bindAddress = "192.168.1.10"
        XCTAssertTrue(config.isExposingToLAN)
    }

    func testMissingJSONFieldsUseDefaults() throws {
        let data = Data(#"{"proxy_server_address":"legacy.example"}"#.utf8)
        let config = try JSONDecoder().decode(ConfigModel.self, from: data)

        XCTAssertEqual(config.proxyServerAddress, "legacy.example")
        XCTAssertEqual(config.proxyServerPort, 443)
        XCTAssertEqual(config.bindAddress, "127.0.0.1")
        XCTAssertEqual(config.listenPort, 8089)
        XCTAssertEqual(config.cipher, "aes-256-ctr")
        XCTAssertEqual(config.timeout, 240)
        XCTAssertEqual(config.workers, 2)
        XCTAssertEqual(config.authKey, "")
    }
}
