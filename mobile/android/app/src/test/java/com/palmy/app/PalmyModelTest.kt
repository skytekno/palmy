package com.palmy.app

import androidx.lifecycle.ViewModelStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.IOException
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

/** A deliberately cancellation-insensitive boundary models late HTTP completion after cancellation. */
private class Gate<T> {
    private var continuation: Continuation<T>? = null
    suspend fun await(): T = suspendCoroutine { continuation = it }
    fun succeed(value: T) { checkNotNull(continuation).resume(value); continuation = null }
    fun fail() { checkNotNull(continuation).resumeWithException(IOException("offline")); continuation = null }
}

private class FakeTransport: PalmyTransport {
    val authenticated = mutableListOf<Identity>()
    val profileRequests = mutableListOf<String>()
    val revoked = mutableListOf<String>()
    val walletKeys = mutableListOf<String>()
    val entryKeys = mutableListOf<String>()
    val committedWallets = mutableSetOf<String>()
    val committedEntries = mutableSetOf<String>()
    val profiles = mutableMapOf<String, ProfileResponse>()
    var register: suspend () -> Unit = {}
    var authentication: suspend (Identity, Session) -> Session = { _, session -> session }
    var revocation: suspend (String) -> Unit = {}
    var totals: suspend () -> Summary = { Summary("1234.56", "1500.00", "265.44", "IDR") }
    var posting: suspend () -> Unit = {}
    override suspend fun register(identity: Identity, profile: Profile) { register() }
    override suspend fun authenticate(identity: Identity): Session {
        authenticated += identity
        val session = Session("session-${authenticated.size}", "2099-01-01T00:00:00Z")
        profiles[session.access_token] = ProfileResponse(identity.accountID, identity.seal(Profile("Owner ${authenticated.size}", "private@example.invalid")), 1)
        return authentication(identity, session)
    }
    override suspend fun profile(token: String): ProfileResponse { profileRequests += token; return profiles.getValue(token) }
    override suspend fun saveProfile(profile: Profile, identity: Identity, version: Int, token: String) = ProfileResponse(identity.accountID, identity.seal(profile), version + 1)
    override suspend fun summary(token: String) = totals()
    override suspend fun wallets(token: String) = listOf(Wallet("wallet-id", "Daily", "1234.56", "IDR"))
    override suspend fun entries(token: String, before: String?) = EntryPage(listOf(FinanceEntry("entry-id", "wallet-id", "income", "1234.56", "Income", "Private finance", "2026-09-27", "2026-09-27T00:00:00Z")), "next-id")
    override suspend fun createWallet(name: String, token: String, key: String) { walletKeys += key; committedWallets += key }
    override suspend fun post(input: TransactionInput, token: String, key: String) { entryKeys += key; committedEntries += key; posting() }
    override suspend fun revoke(token: String) { revoked += token; revocation(token) }
}

@OptIn(ExperimentalCoroutinesApi::class)
class PalmyModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val stores = mutableListOf<ViewModelStore>()
    @Before fun mainDispatcher() { Dispatchers.setMain(dispatcher) }
    @After fun cleanup() { stores.forEach { it.clear() }; Dispatchers.resetMain() }
    private fun model(api: FakeTransport): PalmyModel = PalmyModel(api).also { model ->
        stores += ViewModelStore().also { it.put("test", model) }
    }
    private fun input(amount: String = "1234.56") = TransactionInput("wallet-id", "income", amount, "Income", "Test", "2026-09-27")
    private fun assertDestroyed(identity: Identity) { assertThrows(IllegalStateException::class.java) { identity.derive("palmy:profile:v1") } }
    private fun assertLocked(model: PalmyModel) {
        assertNull(model.identity); assertNull(model.pending); assertNull(model.summary)
        assertEquals(Profile("", ""), model.profile); assertTrue(model.wallets.isEmpty()); assertTrue(model.entries.isEmpty())
        assertNull(model.cursor); assertFalse(model.busy)
    }

    @Test fun unsubmittedRecoverySurvivesBackgroundAndConfigurationChanges() = runTest {
        val model = model(FakeTransport()); model.profile = Profile("Draft", ""); model.prepare()
        val pending = checkNotNull(model.pending); val key = pending.recovery
        model.onBackground(false); assertSame(pending, model.pending); assertEquals(key, pending.recovery)
        model.onBackground(true); assertSame(pending, model.pending)
        model.cancelPrepare(); assertNull(model.pending); assertDestroyed(pending)
    }

    @Test fun backgroundDuringRegistrationCancelsBeforeAuthenticationAndErasesCandidate() = runTest {
        val api = FakeTransport(); val gate = Gate<Unit>(); api.register = { gate.await() }
        val model = model(api); model.profile = Profile("Draft", "private"); model.prepare()
        val candidate = checkNotNull(model.pending)
        model.create(); runCurrent(); assertTrue(model.busy)
        model.onBackground(false); assertLocked(model); assertDestroyed(candidate)
        gate.succeed(Unit); advanceUntilIdle()
        assertLocked(model); assertTrue(api.authenticated.isEmpty())
    }

    @Test fun backgroundDuringRecoveryImmediatelyErasesCandidateAndRevokesLateSession() = runTest {
        val api = FakeTransport(); val gate = Gate<Session>(); api.authentication = { _, _ -> gate.await() }
        val model = model(api); model.recover(Identity.create().recovery); runCurrent()
        val candidate = api.authenticated.single()
        model.onBackground(false); assertLocked(model); assertDestroyed(candidate)
        gate.succeed(Session("late-session", "2099-01-01T00:00:00Z")); advanceUntilIdle()
        assertLocked(model); assertTrue(api.profileRequests.isEmpty()); assertEquals(listOf("late-session"), api.revoked)
    }

    @Test fun staleLoginCannotReplaceNewAccountOrClearItsBusyState() = runTest {
        val api = FakeTransport(); val oldGate = Gate<Session>(); val newGate = Gate<Session>()
        api.authentication = { _, session -> if (session.access_token == "session-1") oldGate.await() else newGate.await() }
        val model = model(api); model.recover(Identity.create().recovery); runCurrent()
        model.lock(); model.recover(Identity.create().recovery); runCurrent()
        val currentCandidate = api.authenticated.last()
        oldGate.succeed(Session("session-1", "2099-01-01T00:00:00Z")); runCurrent()
        assertTrue(model.busy); assertNull(model.identity); assertEquals(listOf("session-1"), api.revoked)
        newGate.succeed(Session("session-2", "2099-01-01T00:00:00Z")); advanceUntilIdle()
        assertSame(currentCandidate, model.identity); assertEquals("Owner 2", model.profile.display_name)
        assertEquals(listOf("session-2"), api.profileRequests); assertFalse(model.busy)
    }

    @Test fun staleRevocationFailureCannotOverwriteNewAuthenticationOrSignedInState() = runTest {
        val api = FakeTransport(); val revokeGate = Gate<Unit>(); api.revocation = { revokeGate.await() }
        val model = model(api); model.recover(Identity.create().recovery); advanceUntilIdle()
        model.lock(); runCurrent()
        val loginGate = Gate<Session>(); api.authentication = { _, _ -> loginGate.await() }
        model.recover(Identity.create().recovery); runCurrent()
        revokeGate.fail(); runCurrent()
        assertTrue(model.busy); assertEquals("", model.message); assertFalse(model.error)
        loginGate.succeed(Session("session-2", "2099-01-01T00:00:00Z")); advanceUntilIdle()
        assertEquals("Owner 2", model.profile.display_name); assertEquals("", model.message)
    }

    @Test fun staleLoginCompletionCannotReplaceAnAlreadyOpenedNewAccount() = runTest {
        val api = FakeTransport(); val oldGate = Gate<Session>()
        api.authentication = { _, session -> if (session.access_token == "session-1") oldGate.await() else session }
        val model = model(api); model.recover(Identity.create().recovery); runCurrent()
        model.lock(); model.recover(Identity.create().recovery); advanceUntilIdle()
        val current = checkNotNull(model.identity); val currentSummary = model.summary
        oldGate.succeed(Session("session-1", "2099-01-01T00:00:00Z")); advanceUntilIdle()
        assertSame(current, model.identity); assertEquals("Owner 2", model.profile.display_name)
        assertEquals(currentSummary, model.summary); assertFalse(model.busy)
        assertEquals(listOf("session-1"), api.revoked)
    }

    @Test fun staleRevocationFailureCannotChangeAnAlreadyOpenedNewAccount() = runTest {
        val api = FakeTransport(); val revokeGate = Gate<Unit>(); api.revocation = { revokeGate.await() }
        val model = model(api); model.recover(Identity.create().recovery); advanceUntilIdle()
        model.lock(); runCurrent(); model.recover(Identity.create().recovery); advanceUntilIdle()
        val current = checkNotNull(model.identity)
        revokeGate.fail(); advanceUntilIdle()
        assertSame(current, model.identity); assertEquals("Owner 2", model.profile.display_name)
        assertEquals("", model.message); assertFalse(model.error); assertFalse(model.busy)
    }

    @Test fun lockClearsAllPrivateStateBeforeInflightRefreshAndRevokeComplete() = runTest {
        val api = FakeTransport(); val model = model(api)
        model.recover(Identity.create().recovery); advanceUntilIdle()
        val identity = checkNotNull(model.identity); val refreshGate = Gate<Summary>(); val revokeGate = Gate<Unit>()
        api.totals = { refreshGate.await() }; api.revocation = { revokeGate.await() }
        model.reload(); runCurrent(); assertTrue(model.busy)
        model.lock(); assertLocked(model); assertDestroyed(identity)
        runCurrent(); assertEquals(listOf("session-1"), api.revoked)
        refreshGate.succeed(Summary("999.00", "999.00", "0.00", "IDR")); revokeGate.fail(); advanceUntilIdle()
        assertLocked(model); assertTrue(model.message.contains("Pencabutan sesi gagal"))
    }

    @Test fun configurationChangeDoesNotCancelActiveAuthentication() = runTest {
        val api = FakeTransport(); val gate = Gate<Session>(); api.authentication = { _, _ -> gate.await() }
        val model = model(api); model.recover(Identity.create().recovery); runCurrent()
        val candidate = api.authenticated.single()
        model.onBackground(true); assertTrue(model.busy)
        gate.succeed(Session("session-1", "2099-01-01T00:00:00Z")); advanceUntilIdle()
        assertSame(candidate, model.identity); assertTrue(api.revoked.isEmpty())
    }

    @Test fun committedTransactionAndFailedRefreshKeepTheSameKeyOnRetry() = runTest {
        val api = FakeTransport(); val model = model(api); model.recover(Identity.create().recovery); advanceUntilIdle()
        api.totals = { throw IOException("refresh failed") }
        model.post(input()); advanceUntilIdle()
        assertEquals(1, model.savedEntry); assertTrue(model.error); assertTrue(model.message.startsWith("Transaksi tersimpan."))
        val key = api.entryKeys.single()
        model.post(input()); advanceUntilIdle()
        assertEquals(listOf(key, key), api.entryKeys); assertEquals(1, api.committedEntries.size); assertEquals(1, model.savedEntry)
        api.totals = { Summary("1234.56", "1234.56", "0.00", "IDR") }
        model.reload(); advanceUntilIdle()
        model.post(input()); advanceUntilIdle()
        assertNotEquals(key, api.entryKeys.last()); assertEquals(2, model.savedEntry)
    }

    @Test fun committedWalletAndFailedRefreshKeepTheSameKeyOnRetry() = runTest {
        val api = FakeTransport(); val model = model(api); model.recover(Identity.create().recovery); advanceUntilIdle()
        api.totals = { throw IOException("refresh failed") }
        model.wallet(" Daily "); advanceUntilIdle(); val key = api.walletKeys.single()
        model.wallet("Daily"); advanceUntilIdle()
        assertEquals(listOf(key, key), api.walletKeys); assertEquals(1, api.committedWallets.size); assertEquals(1, model.savedWallet)
        assertTrue(model.message.startsWith("Dompet tersimpan.")); assertTrue(model.error)
    }

    @Test fun lostPostResponseAndBusyDuplicateDoNotReplaceTheRetryKey() = runTest {
        val api = FakeTransport(); val model = model(api); model.recover(Identity.create().recovery); advanceUntilIdle()
        val postGate = Gate<Unit>(); api.posting = { postGate.await() }
        model.post(input()); runCurrent(); val key = api.entryKeys.single()
        model.post(input("9.99")); assertEquals(listOf(key), api.entryKeys)
        postGate.fail(); advanceUntilIdle(); assertEquals(0, model.savedEntry)
        api.posting = {}; model.post(input()); advanceUntilIdle()
        assertEquals(listOf(key, key), api.entryKeys); assertEquals(1, api.committedEntries.size); assertEquals(1, model.savedEntry)
    }

    @Test fun backgroundDuringPostedWriteCannotRepopulateLockedState() = runTest {
        val api = FakeTransport(); val model = model(api); model.recover(Identity.create().recovery); advanceUntilIdle()
        val gate = Gate<Unit>(); api.posting = { gate.await() }
        model.post(input()); runCurrent(); assertEquals(1, api.committedEntries.size)
        model.onBackground(false); assertLocked(model)
        gate.succeed(Unit); advanceUntilIdle()
        assertLocked(model); assertEquals(0, model.savedEntry); assertFalse(model.error)
        assertEquals(listOf("session-1"), api.revoked)
    }

    @Test fun failedInitialSnapshotPublishesNoIdentityAndDestroysAndRevokesCandidate() = runTest {
        val api = FakeTransport(); api.totals = { throw IOException("offline") }; val model = model(api)
        model.recover(Identity.create().recovery); advanceUntilIdle()
        assertLocked(model); assertDestroyed(api.authenticated.single()); assertEquals(listOf("session-1"), api.revoked); assertTrue(model.error)
    }

    @Test fun viewModelDisposalErasesActiveAndUnsubmittedKeys() = runTest {
        val api = FakeTransport(); val active = model(api); active.recover(Identity.create().recovery); advanceUntilIdle()
        val identity = checkNotNull(active.identity)
        val draft = model(FakeTransport()); draft.prepare(); val pending = checkNotNull(draft.pending)
        stores.forEach { it.clear() }
        assertDestroyed(identity); assertDestroyed(pending)
    }
}
