import XCTest
import CryptoKit
@testable import PalmyCore

final class IdentityTests: XCTestCase {
    private func vector() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("contracts/crypto-vectors.json"))) as? [String: Any])
    }
    func testIndependentSharedVector() throws {
        let vector = try vector()
        let identity = try Identity(recovery: XCTUnwrap(vector["recovery_key"] as? String))
        XCTAssertEqual(identity.derive(info: "palmy:profile:v1").base64URL, vector["profile_key"] as? String)
        XCTAssertEqual(identity.derive(info: "palmy:signing:v1").base64URL, vector["signing_seed"] as? String)
        XCTAssertEqual(try identity.publicKey, vector["public_key"] as? String)
        let envelope = try JSONDecoder().decode(Envelope.self, from: JSONSerialization.data(withJSONObject: XCTUnwrap(vector["envelope"])))
        XCTAssertEqual(String(data: try identity.openBytes(envelope), encoding: .utf8), vector["plaintext"] as? String)
        let sealed = try identity.sealBytes(Data(try XCTUnwrap(vector["plaintext"] as? String).utf8), nonce: Data(base64URL: envelope.nonce))
        XCTAssertEqual(sealed.ciphertext, envelope.ciphertext)
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: XCTUnwrap(Data(base64URL: identity.publicKey)))
        let registration = Data(try XCTUnwrap(vector["registration_message"] as? String).utf8)
        XCTAssertTrue(publicKey.isValidSignature(try XCTUnwrap(Data(base64URL: XCTUnwrap(vector["registration_signature"] as? String))), for: registration))
        // CryptoKit intentionally randomizes Ed25519 signing. Verify interoperability, not byte equality.
        XCTAssertTrue(publicKey.isValidSignature(try XCTUnwrap(Data(base64URL: identity.registrationSignature(envelope))), for: registration))
        let challenge = try XCTUnwrap(vector["challenge"] as? [String: String])
        let authentication = Data(try XCTUnwrap(vector["authentication_message"] as? String).utf8)
        XCTAssertTrue(publicKey.isValidSignature(try XCTUnwrap(Data(base64URL: XCTUnwrap(vector["authentication_signature"] as? String))), for: authentication))
        XCTAssertTrue(publicKey.isValidSignature(try XCTUnwrap(Data(base64URL: identity.challengeSignature(id: XCTUnwrap(challenge["challenge_id"]), nonce: XCTUnwrap(challenge["nonce"])))), for: authentication))
    }
    func testTamperWrongOwnerAndFreshNonce() throws {
        let a = try Identity.create(); let b = try Identity.create()
        let profile = Profile(display_name: "Nama Pribadi", email: "uji@example.invalid")
        let envelope = try a.seal(profile)
        XCTAssertEqual(try a.open(envelope), profile)
        XCTAssertThrowsError(try b.open(envelope))
        XCTAssertNotEqual(try a.seal(profile).nonce, envelope.nonce)
        var bytes = try XCTUnwrap(Data(base64URL: envelope.ciphertext)); bytes[0] ^= 1
        XCTAssertThrowsError(try a.open(Envelope(nonce: envelope.nonce, ciphertext: bytes.base64URL)))
        XCTAssertFalse(envelope.ciphertext.contains("Nama Pribadi"))
    }
    func testRecoveryValidation() throws {
        let identity = try Identity.create()
        XCTAssertEqual(try Identity(recovery: identity.recovery).publicKey, try identity.publicKey)
        XCTAssertThrowsError(try Identity(recovery: identity.recovery + "="))
        XCTAssertThrowsError(try Identity(recovery: "palmy1.invalid.AAAA"))
    }
    func testExactMoney() {
        for value in ["0.01", "1234.56", "9999999999999999.99"] { XCTAssertTrue(Money.validPositive(value), value) }
        for value in ["0", "-1", "1.001", "1e2", "NaN", "1,00", "10000000000000000", "01"] { XCTAssertFalse(Money.validPositive(value), value) }
        XCTAssertTrue(Money.display("1234.56").contains("1.234,56"))
    }
    func testNetworkPolicy() throws {
        XCTAssertThrowsError(try API(baseURL: URL(string: "http://untrusted.invalid/api/v1")!))
        XCTAssertThrowsError(try API(baseURL: URL(string: "https://secret@example.invalid/api/v1")!))
        XCTAssertNoThrow(try API(baseURL: URL(string: "https://api.example.invalid/api/v1")!))
    }
}
