package com.awlqy.terminal.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * مدير أتمتة الحسابات المتعددة.
 * - تسجيل حسابات (منصة، توكن، نقطة وصول).
 * - إرسال طلبات POST آمنة عبر HttpURLConnection.
 * - تشغيل سكربتات shell في الخلفية.
 * - سجل نتائج لكل عملية.
 */
object AutomationManager {

    data class Account(
        val id: String,
        val platform: String,
        val token: String,
        val endpoint: String
    )

    data class DispatchResult(
        val accountId: String,
        val httpCode: Int,
        val responseBody: String,
        val error: String?
    ) {
        val ok: Boolean get() = error == null && httpCode in 200..299
    }

    private val accounts = LinkedHashMap<String, Account>()
    private val log = ArrayDeque<String>()
    private const val MAX_LOG = 500

    @Synchronized
    fun register(account: Account) {
        accounts[account.id] = account
        record("register", account.id, "platform=${account.platform}")
    }

    @Synchronized
    fun remove(id: String): Boolean {
        val removed = accounts.remove(id) != null
        if (removed) record("remove", id, "ok")
        return removed
    }

    @Synchronized
    fun list(): List<Account> = accounts.values.toList()

    @Synchronized
    fun size(): Int = accounts.size

    @Synchronized
    private fun record(op: String, subject: String, detail: String) {
        val entry = "[$op] $subject · $detail"
        log.addLast(entry)
        while (log.size > MAX_LOG) log.removeFirst()
    }

    @Synchronized
    fun history(): List<String> = log.toList()

    suspend fun post(accountId: String, jsonPayload: String): DispatchResult = withContext(Dispatchers.IO) {
        val account = accounts[accountId]
            ?: return@withContext DispatchResult(accountId, -1, "", "الحساب غير مسجّل")
        try {
            val url = URL(account.endpoint)
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.connectTimeout = 20000
            conn.readTimeout = 45000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            conn.setRequestProperty("Authorization", "Bearer ${account.token}")
            conn.setRequestProperty("User-Agent", "awlqy-automation/1.0")

            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { w ->
                w.write(jsonPayload)
                w.flush()
            }

            val code = conn.responseCode
            val body = try {
                val stream = if (code in 200..299) conn.inputStream else conn.errorStream
                BufferedReader(InputStreamReader(stream)).use { it.readText() }
            } catch (_: Exception) { "" }

            conn.disconnect()
            record("post", accountId, "code=$code")
            DispatchResult(accountId, code, body, null)
        } catch (e: Exception) {
            record("post", accountId, "error=${e.message}")
            DispatchResult(accountId, -1, "", e.message ?: e.javaClass.simpleName)
        }
    }

    suspend fun postAll(jsonPayload: String): List<DispatchResult> = withContext(Dispatchers.IO) {
        val ids = accounts.keys.toList()
        val results = ArrayList<DispatchResult>(ids.size)
        for (id in ids) {
            results.add(post(id, jsonPayload))
        }
        results
    }

    suspend fun webhook(url: String, jsonPayload: String): DispatchResult = withContext(Dispatchers.IO) {
        try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.connectTimeout = 15000
            conn.readTimeout = 30000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            conn.setRequestProperty("User-Agent", "awlqy-automation/1.0")

            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { w ->
                w.write(jsonPayload)
                w.flush()
            }
            val code = conn.responseCode
            val body = try {
                val stream = if (code in 200..299) conn.inputStream else conn.errorStream
                BufferedReader(InputStreamReader(stream)).use { it.readText() }
            } catch (_: Exception) { "" }
            conn.disconnect()
            record("webhook", url, "code=$code")
            DispatchResult("webhook", code, body, null)
        } catch (e: Exception) {
            record("webhook", url, "error=${e.message}")
            DispatchResult("webhook", -1, "", e.message ?: e.javaClass.simpleName)
        }
    }

    /**
     * تشغيل سكربت shell في الخلفية دون حجب الواجهة.
     */
    suspend fun runScript(
        script: String,
        workDir: File,
        env: Map<String, String> = emptyMap()
    ): ShellResult = ShellExecutor.run(script, workDir, env)

    /**
     * بناء حمولة JSON موحّدة.
     */
    fun payload(action: String, fields: Map<String, String> = emptyMap()): String {
        val obj = JSONObject()
        obj.put("action", action)
        obj.put("ts", System.currentTimeMillis())
        val extras = JSONObject()
        for ((k, v) in fields) extras.put(k, v)
        obj.put("data", extras)
        return obj.toString()
    }
}
