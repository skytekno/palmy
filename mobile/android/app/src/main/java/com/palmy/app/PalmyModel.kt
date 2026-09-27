package com.palmy.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import java.util.UUID
import kotlin.coroutines.coroutineContext

class PalmyModel(private val transport: PalmyTransport = API(BuildConfig.DEFAULT_API_URL)): ViewModel() {
    var identity by mutableStateOf<Identity?>(null); private set
    var pending by mutableStateOf<Identity?>(null); private set
    var profile by mutableStateOf(Profile("", ""))
    var summary by mutableStateOf<Summary?>(null); private set
    var wallets by mutableStateOf<List<Wallet>>(emptyList()); private set
    var entries by mutableStateOf<List<FinanceEntry>>(emptyList()); private set
    var cursor by mutableStateOf<String?>(null); private set
    var busy by mutableStateOf(false); private set
    var message by mutableStateOf(""); private set
    var error by mutableStateOf(false); private set
    var savedWallet by mutableIntStateOf(0); private set
    var savedEntry by mutableIntStateOf(0); private set
    private var opening: Identity? = null
    private var token: String? = null
    private var version = 1
    private var job: Job? = null
    private var generation = UUID.randomUUID()
    private data class Retry<T>(val input: T, val key: String = UUID.randomUUID().toString(), var committed: Boolean = false)
    private var walletRetry: Retry<String>? = null
    private var entryRetry: Retry<TransactionInput>? = null
    private data class Snapshot(val summary: Summary, val wallets: List<Wallet>, val entries: EntryPage)

    private fun run(action: suspend (UUID) -> Unit) {
        if (busy) return
        busy = true; error = false; message = ""
        val expected = generation
        job = viewModelScope.launch {
            try { action(expected) }
            catch (cancel: CancellationException) { throw cancel }
            catch (exception: Exception) { if (generation == expected) { message = exception.message ?: "Gagal memuat data. Coba lagi."; error = true } }
            finally { if (generation == expected) busy = false }
        }
    }
    private suspend fun ensureCurrent(expected: UUID) {
        coroutineContext.ensureActive()
        if (generation != expected) throw CancellationException("Session was replaced")
    }
    fun prepare() {
        if (busy || identity != null) return
        pending?.destroy(); pending = Identity.create()
    }
    fun cancelPrepare() { if (!busy) { pending?.destroy(); pending = null } }
    fun create() {
        if (busy || identity != null) return
        val candidate = pending ?: return
        val submittedProfile = profile
        generation = UUID.randomUUID()
        run { expected ->
            try { transport.register(candidate, submittedProfile) } catch (e: APIException) { if (e.status != 409) throw e }
            ensureCurrent(expected)
            open(candidate, expected)
            pending = null
        }
    }
    fun recover(key: String) {
        if (busy || identity != null) return
        generation = UUID.randomUUID()
        run { expected -> open(Identity.recover(key), expected) }
    }
    private suspend fun open(candidate: Identity, expected: UUID) {
        opening = candidate
        var session: Session? = null
        var accepted = false
        try {
            session = transport.authenticate(candidate)
            ensureCurrent(expected)
            val response = transport.profile(session.access_token)
            ensureCurrent(expected)
            check(response.account_id == candidate.accountID) { "Pemilik profil tidak cocok." }
            val decrypted = candidate.open(response.profile)
            val snapshot = loadSnapshot(session.access_token)
            ensureCurrent(expected)
            identity = candidate; token = session.access_token; profile = decrypted; version = response.version
            applySnapshot(snapshot)
            accepted = true
        } finally {
            if (opening === candidate) opening = null
            if (!accepted) {
                candidate.destroy()
                if (pending === candidate) pending = null
                session?.let { acquired -> revokeDetached(acquired.access_token) }
            }
        }
    }
    private suspend fun loadSnapshot(token: String) = coroutineScope {
        val s = async { transport.summary(token) }
        val w = async { transport.wallets(token) }
        val e = async { transport.entries(token) }
        Snapshot(s.await(), w.await(), e.await())
    }
    private fun applySnapshot(snapshot: Snapshot) {
        summary = snapshot.summary; wallets = snapshot.wallets; entries = snapshot.entries.data; cursor = snapshot.entries.next_cursor
    }
    private suspend fun refresh(expected: UUID) {
        val activeToken = token ?: return
        val snapshot = loadSnapshot(activeToken)
        ensureCurrent(expected)
        applySnapshot(snapshot)
        if (walletRetry?.committed == true) walletRetry = null
        if (entryRetry?.committed == true) entryRetry = null
    }
    fun reload() = run { expected -> refresh(expected) }
    fun more() {
        val before = cursor ?: return; val activeToken = token ?: return
        run { expected ->
            val page = transport.entries(activeToken, before)
            ensureCurrent(expected)
            entries += page.data; cursor = page.next_cursor
        }
    }
    fun wallet(input: String) {
        if (busy) return
        val activeToken = token ?: return; val name = input.trim()
        val retry = walletRetry?.takeIf { it.input == name } ?: Retry(name)
        walletRetry = retry
        run { expected ->
            transport.createWallet(name, activeToken, retry.key)
            ensureCurrent(expected)
            if (!retry.committed) { retry.committed = true; savedWallet += 1 }
            try { refresh(expected); message = "Dompet tersimpan." }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { ensureCurrent(expected); message = "Dompet tersimpan. Gagal memuat daftar terbaru; gunakan Muat ulang."; error = true }
        }
    }
    fun post(input: TransactionInput) {
        if (busy) return
        val activeToken = token ?: return
        val retry = entryRetry?.takeIf { it.input == input } ?: Retry(input)
        entryRetry = retry
        run { expected ->
            transport.post(input, activeToken, retry.key)
            ensureCurrent(expected)
            if (!retry.committed) { retry.committed = true; savedEntry += 1 }
            try { refresh(expected); message = "Transaksi tersimpan." }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { ensureCurrent(expected); message = "Transaksi tersimpan. Gagal memuat saldo terbaru; gunakan Muat ulang."; error = true }
        }
    }
    fun saveProfile() {
        val activeIdentity = identity ?: return; val activeToken = token ?: return
        run { expected ->
            val response = transport.saveProfile(profile, activeIdentity, version, activeToken)
            ensureCurrent(expected)
            version = response.version; message = "Profil terenkripsi tersimpan."
        }
    }
    fun reloadProfile() {
        val activeIdentity = identity ?: return; val activeToken = token ?: return
        run { expected ->
            val response = transport.profile(activeToken)
            ensureCurrent(expected)
            check(response.account_id == activeIdentity.accountID) { "Pemilik profil tidak cocok." }
            profile = activeIdentity.open(response.profile); version = response.version; message = "Profil terbaru dimuat."
        }
    }
    fun onBackground(changingConfigurations: Boolean) {
        // Unsubmitted onboarding must remain available while saving recovery in a password manager.
        if (!changingConfigurations && (identity != null || busy)) lock()
    }
    private fun revokeDetached(previous: String, expected: UUID? = null) {
        viewModelScope.launch {
            try { transport.revoke(previous) }
            catch (cancel: CancellationException) { throw cancel }
            catch (_: Exception) {
                if (expected != null && generation == expected && identity == null) message = "Terkunci di perangkat. Pencabutan sesi gagal; sesi server kedaluwarsa dalam 1 jam."
            }
        }
    }
    fun lock() {
        val previous = token
        job?.cancel(); generation = UUID.randomUUID()
        identity?.destroy(); identity = null; opening?.destroy(); opening = null; pending?.destroy(); pending = null; token = null
        profile = Profile("", ""); summary = null; wallets = emptyList(); entries = emptyList(); cursor = null
        walletRetry = null; entryRetry = null; savedWallet = 0; savedEntry = 0; busy = false; error = false
        message = "Aplikasi terkunci. Gunakan kunci pemulihan untuk membuka kembali."
        if (previous != null) revokeDetached(previous, generation)
    }
    override fun onCleared() {
        identity?.destroy(); opening?.destroy(); pending?.destroy()
        super.onCleared()
    }
}
