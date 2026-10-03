package com.awlqy.terminal.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * محرك بناء/تفكيك APK على الجهاز.
 * يعتمد على وجود: aapt2, d8, apktool, jadx, apksigner, zipalign
 * (يمكن تثبيتها عبر awlqy-pkg أو وضعها في usr/bin).
 */
class ApkBuilder(private val workDir: File) {

    private fun bin(name: String): String {
        val local = File(workDir, "../usr/bin/$name")
        return if (local.exists()) local.absolutePath else name
    }

    private suspend fun run(cmd: List<String>): Int = withContext(Dispatchers.IO) {
        try {
            val p = ProcessBuilder(cmd).directory(workDir).inheritIO().start()
            p.waitFor(30, TimeUnit.MINUTES)
            p.exitValue()
        } catch (t: Throwable) { Timber.e(t, "apk run fail"); -1 }
    }

    suspend fun decode(apk: File, outDir: File): Int {
        outDir.mkdirs()
        return run(listOf("sh", "-c",
            "${bin("apktool")} d -f -o '${outDir.absolutePath}' '${apk.absolutePath}'"))
    }

    suspend fun build(decodedDir: File, outApk: File): Int {
        return run(listOf("sh", "-c",
            "${bin("apktool")} b -o '${outApk.absolutePath}' '${decodedDir.absolutePath}'"))
    }

    suspend fun sign(apk: File, keystore: File, alias: String, pass: String): Int {
        return run(listOf("sh", "-c",
            "${bin("apksigner")} sign --ks '${keystore.absolutePath}' " +
            "--ks-key-alias '$alias' --ks-pass pass:'$pass' --key-pass pass:'$pass' '${apk.absolutePath}'"))
    }

    suspend fun zipalign(input: File, output: File): Int {
        return run(listOf("sh", "-c",
            "${bin("zipalign")} -f 4 '${input.absolutePath}' '${output.absolutePath}'"))
    }

    suspend fun decompileToJava(apk: File, outDir: File): Int {
        outDir.mkdirs()
        return run(listOf("sh", "-c",
            "${bin("jadx")} -d '${outDir.absolutePath}' '${apk.absolutePath}'"))
    }

    suspend fun aapt2Dump(apk: File): Int {
        return run(listOf("sh", "-c", "${bin("aapt2")} dump badging '${apk.absolutePath}'"))
    }

    suspend fun dexToSmali(decodedDir: File): Int {
        return run(listOf("sh", "-c",
            "${bin("d8")} --output '${decodedDir.absolutePath}/smali_out' " +
            "'${decodedDir.absolutePath}'/smali/**/*.smali"))
    }
}
