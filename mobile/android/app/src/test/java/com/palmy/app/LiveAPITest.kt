package com.palmy.app

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.UUID

class LiveAPITest {
    @Test fun nativeCryptoAndFinanceOverHTTP() = runBlocking {
        val address = System.getenv("PALMY_TEST_API_URL")
        assumeTrue("Set PALMY_TEST_API_URL for disposable API integration", address != null)
        val base = address!!.trimEnd('/')
        val api = API(if (base.endsWith("/api/v1")) base else "$base/api/v1", true)
        val identity = Identity.create(); val profile = Profile("Native synthetic", "android@example.invalid")
        api.register(identity, profile)
        val session = api.authenticate(identity)
        val stored = api.profile(session.access_token)
        assertEquals(profile, identity.open(stored.profile))
        val edited = Profile("Native edited", "edited@example.invalid")
        val saved = api.saveProfile(edited, identity, stored.version, session.access_token)
        assertEquals(edited, identity.open(saved.profile)); assertEquals(stored.version + 1, saved.version)
        val walletKey = UUID.randomUUID().toString()
        api.createWallet("Native test", session.access_token, walletKey)
        api.createWallet("Native test", session.access_token, walletKey)
        val wallets = api.wallets(session.access_token); assertEquals(1, wallets.size)
        val input = TransactionInput(wallets.first().id, "income", "1234.56", "Uji", "Synthetic native test", "2026-09-27")
        val key = UUID.randomUUID().toString()
        api.post(input, session.access_token, key); api.post(input, session.access_token, key)
        assertEquals("1234.56", api.summary(session.access_token).balance)
        assertEquals(1, api.entries(session.access_token).data.size)
        api.revoke(session.access_token)
        try { api.profile(session.access_token); fail("Revoked session must fail") } catch (e: APIException) { assertEquals(401, e.status) }
        val recovered = Identity.recover(identity.recovery)
        val second = api.authenticate(recovered)
        assertEquals(edited, recovered.open(api.profile(second.access_token).profile))
        api.revoke(second.access_token)
    }
}
