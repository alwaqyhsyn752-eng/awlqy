package com.awlqy.terminal.core

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

object AutoUpdateManager {

    private const val OWNER = "alwaqyhsyn752-eng"
    private const val REPO = "awlqy"
    private const val API_URL = "https://api.github.com/repos/$OWNER/$REPO/releases/latest"
    private const val UA = "awlqy-updater-android"

    data class UpdateInfo(
        val tag: String,
        val notes: String,
        val apkUrl: String,
        val apkName: String,
        val hasUpdate: Boolean
    )

    fun checkLatest(ctx: Context, currentVersion: String): UpdateInfo? {
        var conn: HttpURLConnection? = null
        return try {
            val u = URL(API_URL)
            conn = u.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
            conn.setRequestProperty("User-Agent", UA)
            conn.setRequestProperty("Accept", "application/vnd.github+json")
            if (conn.responseCode != 200) return null

            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)
            val tag = json.optString("tag_name", "").trim()
            val notes = json.optString("body", "")
            val assets = json.optJSONArray("assets")

            var apkUrl = ""
            var apkName = "awlqy.apk"
            if (assets != null) {
                var i = 0
                while (i < assets.length()) {
                    val a = assets.getJSONObject(i)
                    val name = a.optString("name", "")
                    if (name.endsWith(".apk", ignoreCase = true)) {
                        apkUrl = a.optString("browser_download_url", "")
                        apkName = name
                        break
                    }
                    i++
                }
            }

            val latest = tag.trimStart('v', 'V')
            val current = currentVersion.trimStart('v', 'V')
            val hasUpdate = apkUrl.isNotBlank() && compareVersions(latest, current) > 0

            UpdateInfo(tag.ifBlank { "v?" }, notes, apkUrl, apkName, hasUpdate)
        } catch (_: Exception) {
            null
        } finally {
            try { conn?.disconnect() } catch (_: Exception) { }
        }
    }

    fun compareVersions(a: String, b: String): Int {
        val pa = a.split('.').map { s -> s.filter { it.isDigit() }.toIntOrNull() ?: 0 }
        val pb = b.split('.').map { s -> s.filter { it.isDigit() }.toIntOrNull() ?: 0 }
        val n = maxOf(pa.size, pb.size)
        for (i in 0 until n) {
            val x = pa.getOrElse(i) { 0 }
            val y = pb.getOrElse(i) { 0 }
            if (x != y) return if (x > y) 1 else -1
        }
        return 0
    }

    fun downloadApk(ctx: Context, info: UpdateInfo, onProgress: (Int) -> Unit): File? {
        val dest = File(ctx.cacheDir, info.apkName)
        if (dest.exists()) dest.delete()
        var conn: HttpURLConnection? = null
        return try {
            val u = URL(info.apkUrl)
            conn = u.openConnection() as HttpURLConnection
            conn.instanceFollowRedirects = true
            conn.connectTimeout = 20000
            conn.readTimeout = 60000
            conn.setRequestProperty("User-Agent", UA)
            val code = conn.responseCode
            if (code !in 200..299) return null

            val total = conn.contentLengthLong
            conn.inputStream.use { input ->
                dest.outputStream().use { output ->
                    val buf = ByteArray(64 * 1024)
                    var sum = 0L
                    var read = input.read(buf)
                    while (read > 0) {
                        output.write(buf, 0, read)
                        sum += read
                        if (total > 0) onProgress(((sum * 100L) / total).toInt())
                        read = input.read(buf)
                    }
                }
            }
            if (dest.length() < 1024L) return null
            dest
        } catch (_: Exception) {
            null
        } finally {
            try { conn?.disconnect() } catch (_: Exception) { }
        }
    }

    fun installApk(ctx: Context, apk: File): Boolean {
        return try {
            val uri: Uri = FileProvider.getUriForFile(
                ctx,
                "${ctx.packageName}.fileprovider",
                apk
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            ctx.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
