package com.palmy.app

import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Locale
import java.util.UUID
import java.util.concurrent.TimeUnit

data class Wallet(val id: String, val name: String, val balance: String, val currency: String)
data class FinanceEntry(val id: String, val wallet_id: String, val kind: String, val amount: String, val category: String, val description: String, val effective_on: String, val created_at: String)
data class Summary(val balance: String, val income: String, val expense: String, val currency: String)
data class ProfileResponse(val account_id: String, val profile: Envelope, val version: Int)
data class Challenge(val challenge_id: String, val nonce: String, val expires_at: String)
data class Session(val access_token: String, val expires_at: String)
data class EntryPage(val data: List<FinanceEntry>, val next_cursor: String?)
data class TransactionInput(val wallet_id: String, val kind: String, val amount: String, val category: String, val description: String, val effective_on: String)
class APIException(val status: Int, message: String): Exception(message)

interface PalmyTransport {
    suspend fun register(identity: Identity, profile: Profile)
    suspend fun authenticate(identity: Identity): Session
    suspend fun profile(token: String): ProfileResponse
    suspend fun saveProfile(profile: Profile, identity: Identity, version: Int, token: String): ProfileResponse
    suspend fun summary(token: String): Summary
    suspend fun wallets(token: String): List<Wallet>
    suspend fun entries(token: String, before: String? = null): EntryPage
    suspend fun createWallet(name: String, token: String, key: String)
    suspend fun post(input: TransactionInput, token: String, key: String)
    suspend fun revoke(token: String)
}

class API(private val baseURL: String, allowDevelopment: Boolean = BuildConfig.DEBUG): PalmyTransport {
    private val json = Gson()
    private val client = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS).followRedirects(false).followSslRedirects(false).build()
    init {
        val url = baseURL.toHttpUrl()
        require(url.username.isEmpty() && url.password.isEmpty() && url.query == null && url.fragment == null &&
            (url.isHttps || allowDevelopment && url.host in setOf("10.0.2.2", "127.0.0.1", "localhost"))) { "Gunakan URL API HTTPS yang tepercaya." }
    }
    private suspend fun request(path: String, method: String = "GET", body: Any? = null, token: String? = null, key: String? = null): String = withContext(Dispatchers.IO) {
        val request = Request.Builder().url(baseURL.trimEnd('/') + path).header("Accept", "application/json").header("Cache-Control", "no-store")
        if (token != null) request.header("Authorization", "Bearer $token")
        if (key != null) request.header("Idempotency-Key", key)
        request.method(method, if (body != null) json.toJson(body).toRequestBody("application/json".toMediaType()) else null)
        client.newCall(request.build()).execute().use { response ->
            val result = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                val problem = runCatching { json.fromJson(result, JsonObject::class.java).get("title")?.asString }.getOrNull()
                throw APIException(response.code, problem ?: "Permintaan gagal (${response.code}). Coba lagi.")
            }
            result
        }
    }
    private inline fun <reified T> wrapped(text: String): T = json.fromJson(json.fromJson(text, JsonObject::class.java).get("data"), object: TypeToken<T>() {}.type)
    override suspend fun register(identity: Identity, profile: Profile) {
        val envelope = identity.seal(profile)
        request("/accounts", "POST", mapOf("account_id" to identity.accountID, "public_key" to identity.publicKey, "profile" to envelope, "signature" to identity.registrationSignature(envelope)))
    }
    override suspend fun authenticate(identity: Identity): Session {
        val challenge: Challenge = wrapped(request("/auth/challenges", "POST", mapOf("account_id" to identity.accountID)))
        return wrapped(request("/auth/sessions", "POST", mapOf("account_id" to identity.accountID, "challenge_id" to challenge.challenge_id, "signature" to identity.challengeSignature(challenge.challenge_id, challenge.nonce))))
    }
    override suspend fun profile(token: String): ProfileResponse = wrapped(request("/profile", token = token))
    override suspend fun saveProfile(profile: Profile, identity: Identity, version: Int, token: String): ProfileResponse = wrapped(request("/profile", "PUT", mapOf("profile" to identity.seal(profile), "version" to version), token))
    override suspend fun summary(token: String): Summary = wrapped(request("/summary", token = token))
    override suspend fun wallets(token: String): List<Wallet> = wrapped(request("/wallets", token = token))
    override suspend fun entries(token: String, before: String?): EntryPage {
        if (before != null) UUID.fromString(before)
        return json.fromJson(request("/transactions?limit=25" + (before?.let { "&before=$it" } ?: ""), token = token), EntryPage::class.java)
    }
    override suspend fun createWallet(name: String, token: String, key: String) { request("/wallets", "POST", mapOf("name" to name), token, key) }
    override suspend fun post(input: TransactionInput, token: String, key: String) { request("/transactions", "POST", input, token, key) }
    override suspend fun revoke(token: String) { request("/auth/session", "DELETE", token = token) }
}

object Money {
    fun validPositive(text: String): Boolean = text.matches(Regex("^(0|[1-9][0-9]{0,15})(\\.[0-9]{1,2})?$")) && runCatching { BigDecimal(text) > BigDecimal.ZERO }.getOrDefault(false)
    fun display(text: String): String = runCatching {
        NumberFormat.getCurrencyInstance(Locale.forLanguageTag("id-ID")).apply { currency = java.util.Currency.getInstance("IDR"); minimumFractionDigits = 2; maximumFractionDigits = 2 }.format(BigDecimal(text))
    }.getOrDefault("—")
}
