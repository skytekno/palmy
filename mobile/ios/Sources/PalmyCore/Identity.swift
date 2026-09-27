import CryptoKit
import Foundation
import Security

public enum IdentityError: Error, LocalizedError {
    case recovery, envelope, random
    public var errorDescription: String? {
        switch self {
        case .recovery: "Kunci pemulihan tidak valid."
        case .envelope: "Profil tidak dapat dibuka dengan kunci ini."
        case .random: "Perangkat tidak dapat membuat kunci aman."
        }
    }
}

public struct Profile: Codable, Sendable, Equatable {
    public var display_name: String
    public var email: String
    public init(display_name: String, email: String) { self.display_name = display_name; self.email = email }
}

public struct Envelope: Codable, Sendable {
    public let version: Int
    public let algorithm: String
    public let nonce: String
    public let ciphertext: String
    public init(version: Int = 1, algorithm: String = "A256GCM", nonce: String, ciphertext: String) {
        self.version = version; self.algorithm = algorithm; self.nonce = nonce; self.ciphertext = ciphertext
    }
}

extension Data {
    public var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    public init?(base64URL: String) {
        guard base64URL.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        let padded = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4 - base64URL.count % 4) % 4)
        guard let bytes = Data(base64Encoded: padded), bytes.base64URL == base64URL else { return nil }
        self = bytes
    }
}

/// Recovery and all derived secrets live in memory only. Nothing is written to UserDefaults or files.
public struct Identity: Sendable {
    public let accountID: String
    private let master: Data
    public init(accountID: String, master: Data) throws {
        guard let uuid = UUID(uuidString: accountID), uuid.uuidString.lowercased() == accountID,
              accountID[accountID.index(accountID.startIndex, offsetBy: 14)] == "4",
              "89ab".contains(accountID[accountID.index(accountID.startIndex, offsetBy: 19)]), master.count == 32 else { throw IdentityError.recovery }
        self.accountID = accountID; self.master = master
    }
    public static func create() throws -> Identity {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw IdentityError.random }
        return try Identity(accountID: UUID().uuidString.lowercased(), master: Data(bytes))
    }
    public init(recovery: String) throws {
        let parts = recovery.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "palmy1", let master = Data(base64URL: String(parts[2])) else { throw IdentityError.recovery }
        try self.init(accountID: String(parts[1]), master: master)
    }
    public var recovery: String { "palmy1.\(accountID).\(master.base64URL)" }
    public func derive(info: String) -> Data {
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: master), salt: Data("palmy:v1".utf8), info: Data(info.utf8), outputByteCount: 32)
        return key.withUnsafeBytes { Data($0) }
    }
    private var signingKey: Curve25519.Signing.PrivateKey { get throws { try Curve25519.Signing.PrivateKey(rawRepresentation: derive(info: "palmy:signing:v1")) } }
    public var publicKey: String { get throws { try signingKey.publicKey.rawRepresentation.base64URL } }
    public func sign(_ message: String) throws -> String { try signingKey.signature(for: Data(message.utf8)).base64URL }
    public func seal(_ profile: Profile) throws -> Envelope { try sealBytes(JSONEncoder().encode(profile)) }
    /// Explicit nonce is for published cross-client test vectors only. UI calls seal(profile).
    public func sealBytes(_ bytes: Data, nonce: Data? = nil) throws -> Envelope {
        let key = SymmetricKey(data: derive(info: "palmy:profile:v1"))
        let nonce = try nonce.map { try AES.GCM.Nonce(data: $0) } ?? AES.GCM.Nonce()
        let box = try AES.GCM.seal(bytes, using: key, nonce: nonce, authenticating: Data("palmy:profile:v1:\(accountID)".utf8))
        return Envelope(nonce: Data(nonce).base64URL, ciphertext: (box.ciphertext + box.tag).base64URL)
    }
    public func openBytes(_ envelope: Envelope) throws -> Data {
        guard envelope.version == 1, envelope.algorithm == "A256GCM", let nonce = Data(base64URL: envelope.nonce), nonce.count == 12,
              let combined = Data(base64URL: envelope.ciphertext), combined.count >= 16 else { throw IdentityError.envelope }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: combined.dropLast(16), tag: combined.suffix(16))
        return try AES.GCM.open(box, using: SymmetricKey(data: derive(info: "palmy:profile:v1")), authenticating: Data("palmy:profile:v1:\(accountID)".utf8))
    }
    public func open(_ envelope: Envelope) throws -> Profile { try JSONDecoder().decode(Profile.self, from: openBytes(envelope)) }
    public func registrationSignature(_ envelope: Envelope) throws -> String { try sign("palmy:register:v1:\(accountID):\(publicKey):\(envelope.nonce):\(envelope.ciphertext)") }
    public func challengeSignature(id: String, nonce: String) throws -> String { try sign("palmy:auth:v1:\(accountID):\(id):\(nonce)") }
}
