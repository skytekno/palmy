package com.palmy.app

import com.google.gson.Gson
import org.bouncycastle.crypto.digests.SHA256Digest
import org.bouncycastle.crypto.generators.HKDFBytesGenerator
import org.bouncycastle.crypto.params.HKDFParameters
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

data class Profile(val display_name: String, val email: String)
data class Envelope(val version: Int = 1, val algorithm: String = "A256GCM", val nonce: String, val ciphertext: String)

object Base64URL {
    fun encode(value: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(value)
    fun decode(value: String): ByteArray {
        require(value.matches(Regex("^[A-Za-z0-9_-]+$"))) { "Encoding tidak valid." }
        return Base64.getUrlDecoder().decode(value).also { require(encode(it) == value) { "Encoding tidak valid." } }
    }
}

/** No identity keys or sessions are stored in SharedPreferences, saved state, or files. */
class Identity private constructor(val accountID: String, private val master: ByteArray) {
    companion object {
        private val uuid = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        fun create() = Identity(UUID.randomUUID().toString(), ByteArray(32).also { SecureRandom().nextBytes(it) })
        fun recover(input: String): Identity {
            val parts = input.trim().split('.')
            require(parts.size == 3 && parts[0] == "palmy1" && uuid.matches(parts[1])) { "Kunci pemulihan tidak valid." }
            val master = Base64URL.decode(parts[2])
            require(master.size == 32) { "Kunci pemulihan tidak valid." }
            return Identity(parts[1], master)
        }
    }
    private var destroyed = false
    private fun requireActive() { check(!destroyed) { "Kunci sudah dilepas. Pulihkan akun untuk melanjutkan." } }
    val recovery get(): String { requireActive(); return "palmy1.$accountID.${Base64URL.encode(master)}" }
    fun derive(info: String): ByteArray = ByteArray(32).also {
        requireActive()
        val hkdf = HKDFBytesGenerator(SHA256Digest())
        hkdf.init(HKDFParameters(master, "palmy:v1".toByteArray(Charsets.UTF_8), info.toByteArray(Charsets.UTF_8)))
        hkdf.generateBytes(it, 0, it.size)
    }
    private fun signingKey() = Ed25519PrivateKeyParameters(derive("palmy:signing:v1"), 0)
    val publicKey: String get() = Base64URL.encode(signingKey().generatePublicKey().encoded)
    fun sign(message: String): String {
        val signer = Ed25519Signer(); signer.init(true, signingKey())
        val bytes = message.toByteArray(Charsets.UTF_8); signer.update(bytes, 0, bytes.size)
        return Base64URL.encode(signer.generateSignature())
    }
    fun seal(profile: Profile): Envelope = sealBytes(Gson().toJson(profile).toByteArray(Charsets.UTF_8))
    // Nonce argument supports published fixtures only. Production callers use seal(Profile).
    internal fun sealBytes(bytes: ByteArray, nonce: ByteArray = ByteArray(12).also { SecureRandom().nextBytes(it) }): Envelope {
        require(nonce.size == 12)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(derive("palmy:profile:v1"), "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD("palmy:profile:v1:$accountID".toByteArray(Charsets.UTF_8))
        return Envelope(nonce = Base64URL.encode(nonce), ciphertext = Base64URL.encode(cipher.doFinal(bytes)))
    }
    fun openBytes(envelope: Envelope): ByteArray {
        require(envelope.version == 1 && envelope.algorithm == "A256GCM") { "Versi profil tidak didukung." }
        val nonce = Base64URL.decode(envelope.nonce); val bytes = Base64URL.decode(envelope.ciphertext)
        require(nonce.size == 12 && bytes.size >= 16) { "Profil terenkripsi tidak valid." }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(derive("palmy:profile:v1"), "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD("palmy:profile:v1:$accountID".toByteArray(Charsets.UTF_8))
        return cipher.doFinal(bytes)
    }
    fun open(envelope: Envelope): Profile = Gson().fromJson(openBytes(envelope).toString(Charsets.UTF_8), Profile::class.java)
    fun registrationSignature(envelope: Envelope) = sign("palmy:register:v1:$accountID:$publicKey:${envelope.nonce}:${envelope.ciphertext}")
    fun challengeSignature(id: String, nonce: String) = sign("palmy:auth:v1:$accountID:$id:$nonce")
    fun destroy() { master.fill(0); destroyed = true }
}
