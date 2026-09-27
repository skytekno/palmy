package com.palmy.app

import android.view.WindowManager
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

private class DeviceGate<T> {
    private val started = CountDownLatch(1)
    private lateinit var continuation: Continuation<T>
    suspend fun await(): T = suspendCoroutine { continuation = it; started.countDown() }
    fun awaitStarted() { assertTrue("Operation did not reach its controlled suspension", started.await(5, TimeUnit.SECONDS)) }
    fun finish(value: T) = continuation.resume(value)
}

private class DeviceTransport: PalmyTransport {
    var registrationGate: DeviceGate<Unit>? = null
    var authenticationGate: DeviceGate<Session>? = null
    val candidates = mutableListOf<Identity>()
    val revoked = mutableListOf<String>()
    var profileReads = 0
    private lateinit var encryptedProfile: ProfileResponse
    override suspend fun register(identity: Identity, profile: Profile) { registrationGate?.await() }
    override suspend fun authenticate(identity: Identity): Session {
        candidates += identity
        encryptedProfile = ProfileResponse(identity.accountID, identity.seal(Profile("Device owner", "")), 1)
        return authenticationGate?.await() ?: Session("device-session", "2099-01-01T00:00:00Z")
    }
    override suspend fun profile(token: String): ProfileResponse { profileReads++; return encryptedProfile }
    override suspend fun summary(token: String) = Summary("1234.56", "1234.56", "0.00", "IDR")
    override suspend fun wallets(token: String) = listOf(Wallet("wallet", "Device wallet", "1234.56", "IDR"))
    override suspend fun entries(token: String, before: String?) = EntryPage(emptyList(), null)
    override suspend fun revoke(token: String) { revoked += token }
    override suspend fun createWallet(name: String, token: String, key: String) = Unit
    override suspend fun post(input: TransactionInput, token: String, key: String) = Unit
    override suspend fun saveProfile(profile: Profile, identity: Identity, version: Int, token: String) =
        ProfileResponse(identity.accountID, identity.seal(profile), version + 1)
}

/** Real MainActivity, real ViewModel, real Android Main dispatcher; only HTTP is substituted. */
@RunWith(AndroidJUnit4::class)
class ActivityLifecycleTest {
    private lateinit var transport: DeviceTransport
    private lateinit var model: PalmyModel
    private fun idle() = InstrumentationRegistry.getInstrumentation().waitForIdleSync()
    @Before fun injectTransport() {
        transport = DeviceTransport()
        ApplicationProvider.getApplicationContext<LifecycleTestApplication>().modelFactory = {
            PalmyModel(transport).also { model = it }
        }
    }
    private fun assertLocked() {
        assertNull(model.identity); assertNull(model.pending); assertNull(model.summary)
        assertTrue(model.wallets.isEmpty()); assertTrue(model.entries.isEmpty()); assertFalse(model.busy)
        assertEquals(Profile("", ""), model.profile)
    }

    @Test fun onboardingKeySurvivesPasswordManagerBackgroundAndActivityRecreation() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var key: String
            lateinit var original: PalmyModel
            scenario.onActivity { activity ->
                assertTrue(activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0)
                original = model; model.profile = Profile("Draft", ""); model.prepare(); key = checkNotNull(model.pending).recovery
            }
            scenario.moveToState(Lifecycle.State.CREATED).moveToState(Lifecycle.State.RESUMED)
            scenario.recreate()
            scenario.onActivity { assertSame(original, model); assertEquals(key, checkNotNull(model.pending).recovery) }
        }
    }

    @Test fun actualOnStopCancelsRegistrationBeforeItCanAuthenticate() {
        val gate = DeviceGate<Unit>(); transport.registrationGate = gate
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var candidate: Identity
            scenario.onActivity { model.profile = Profile("Draft", ""); model.prepare(); candidate = checkNotNull(model.pending); model.create() }
            gate.awaitStarted()
            scenario.moveToState(Lifecycle.State.CREATED)
            assertLocked(); assertThrows(IllegalStateException::class.java) { candidate.derive("palmy:signing:v1") }
            gate.finish(Unit); idle()
            scenario.moveToState(Lifecycle.State.RESUMED)
            scenario.onActivity { assertLocked(); assertTrue(transport.candidates.isEmpty()) }
        }
    }

    @Test fun actualOnStopErasesRecoveryAndRevokesTheLateSession() {
        val gate = DeviceGate<Session>(); transport.authenticationGate = gate
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { model.recover(Identity.create().recovery) }
            gate.awaitStarted()
            scenario.moveToState(Lifecycle.State.CREATED)
            assertLocked()
            assertThrows(IllegalStateException::class.java) { transport.candidates.single().derive("palmy:profile:v1") }
            gate.finish(Session("late-device-session", "2099-01-01T00:00:00Z")); idle()
            scenario.moveToState(Lifecycle.State.RESUMED)
            scenario.onActivity { assertLocked(); assertEquals(0, transport.profileReads); assertEquals(listOf("late-device-session"), transport.revoked) }
        }
    }

    @Test fun signedInActivitySurvivesRotationButBackgroundReleasesAllPrivateState() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { model.recover(Identity.create().recovery) }; idle()
            lateinit var identity: Identity
            scenario.onActivity { identity = checkNotNull(model.identity); assertEquals("1234.56", model.summary?.balance) }
            scenario.recreate()
            scenario.onActivity { assertSame(identity, model.identity) }
            scenario.moveToState(Lifecycle.State.CREATED); idle()
            assertLocked(); assertThrows(IllegalStateException::class.java) { identity.derive("palmy:profile:v1") }
            assertEquals(listOf("device-session"), transport.revoked)
            scenario.moveToState(Lifecycle.State.RESUMED)
            scenario.onActivity { assertLocked() }
        }
    }
}
