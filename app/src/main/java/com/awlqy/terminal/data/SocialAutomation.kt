package com.awlqy.terminal.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import timber.log.Timber
import java.util.concurrent.TimeUnit

/**
 * إطار إدارة حسابات متعددة عبر API/Webhooks.
 * يدير جلسات مستقلة لكل حساب ويسمح بإرسال إجراءات متتابعة أو متوازية.
 */
class SocialAutomation {

    data class Account(
        val id: String,
        val platform: String,
        val token: String,
        val endpoint: String
    )

    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .build()

    private val accounts = mutableMapOf<String, Account>()
    private val json = "application/json; charset=utf-8".toMediaType()

    fun register(a: Account) { accounts[a.id] = a; Timber.i("registered %s", a.id) }
    fun list(): List<Account> = accounts.values.toList()
    fun remove(id: String) { accounts.remove(id) }

    suspend fun post(accountId: String, payloadJson: String): String? = withContext(Dispatchers.IO) {
        val a = accounts[accountId] ?: run { Timber.w("no account %s", accountId); return@withContext null }
        val req = Request.Builder()
            .url(a.endpoint)
            .addHeader("Authorization", "Bearer ${a.token}")
            .addHeader("Content-Type", "application/json")
            .post(payloadJson.toRequestBody(json))
            .build()
        try {
            client.newCall(req).execute().use { r ->
                r.body?.string().also { Timber.i("post %s -> %d", accountId, r.code) }
            }
        } catch (t: Throwable) { Timber.e(t, "post fail"); null }
    }

    suspend fun postToAll(payloadJson: String): Map<String, String?> = withContext(Dispatchers.IO) {
        accounts.keys.associateWith { id -> post(id, payloadJson) }
    }

    suspend fun webhook(url: String, payloadJson: String): String? = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url)
            .post(payloadJson.toRequestBody(json)).build()
        try { client.newCall(req).execute().use { it.body?.string() } }
        catch (t: Throwable) { Timber.e(t, "webhook fail"); null }
    }
}
