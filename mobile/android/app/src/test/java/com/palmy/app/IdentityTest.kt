package com.palmy.app

import com.google.gson.Gson
import com.google.gson.JsonObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class IdentityTest {
    private fun vector(): JsonObject = Gson().fromJson(File(System.getProperty("palmy.repo"), "contracts/crypto-vectors.json").readText(), JsonObject::class.java)
    @Test fun sharedIndependentVector() {
        val v = vector(); val identity = Identity.recover(v["recovery_key"].asString)
        assertEquals(v["profile_key"].asString, Base64URL.encode(identity.derive("palmy:profile:v1")))
        assertEquals(v["signing_seed"].asString, Base64URL.encode(identity.derive("palmy:signing:v1")))
        assertEquals(v["public_key"].asString, identity.publicKey)
        val envelope = Gson().fromJson(v["envelope"], Envelope::class.java)
        assertEquals(v["plaintext"].asString, identity.openBytes(envelope).toString(Charsets.UTF_8))
        assertEquals(envelope.ciphertext, identity.sealBytes(v["plaintext"].asString.toByteArray(Charsets.UTF_8), Base64URL.decode(envelope.nonce)).ciphertext)
        assertEquals(v["registration_signature"].asString, identity.registrationSignature(envelope))
        val challenge = v["challenge"].asJsonObject
        assertEquals(v["authentication_signature"].asString, identity.challengeSignature(challenge["challenge_id"].asString, challenge["nonce"].asString))
    }
    @Test fun roundTripWrongOwnerTamperAndFreshNonce() {
        val identity = Identity.create(); val other = Identity.create()
        val profile = Profile("Nama Pribadi", "uji@example.invalid")
        val envelope = identity.seal(profile)
        assertEquals(profile, identity.open(envelope))
        assertThrows(Exception::class.java) { other.open(envelope) }
        assertNotEquals(envelope.nonce, identity.seal(profile).nonce)
        val bytes = Base64URL.decode(envelope.ciphertext); bytes[0] = (bytes[0].toInt() xor 1).toByte()
        assertThrows(Exception::class.java) { identity.open(envelope.copy(ciphertext = Base64URL.encode(bytes))) }
    }
    @Test fun strictRecovery() {
        val identity = Identity.create()
        assertEquals(identity.publicKey, Identity.recover(identity.recovery).publicKey)
        assertThrows(Exception::class.java) { Identity.recover(identity.recovery + "=") }
        assertThrows(Exception::class.java) { Identity.recover("palmy1.bad.AAAA") }
        assertThrows(Exception::class.java) { Identity.recover(identity.recovery.replaceRange(7 + 19, 7 + 20, "0")) }
    }
    @Test fun exactMoney() {
        listOf("0.01", "1234.56", "9999999999999999.99").forEach { assertTrue(it, Money.validPositive(it)) }
        listOf("0", "-1", "1.001", "1e3", "NaN", "1,00", "10000000000000000", "01").forEach { assertFalse(it, Money.validPositive(it)) }
        assertTrue(Money.display("1234.56").contains("1.234,56"))
    }
    @Test fun networkPolicy() {
        assertThrows(Exception::class.java) { API("http://untrusted.invalid/api/v1", true) }
        assertThrows(Exception::class.java) { API("http://127.0.0.1:8100/api/v1", false) }
        assertThrows(Exception::class.java) { API("https://secret@example.invalid/api/v1", false) }
    }
}
