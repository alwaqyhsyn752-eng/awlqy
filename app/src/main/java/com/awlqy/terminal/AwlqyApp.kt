package com.awlqy.terminal

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import timber.log.Timber
import java.io.File

class AwlqyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) Timber.plant(Timber.DebugTree())

        // تهيئة بيئة التطبيق: مجلد home، tmp، usr
        val home = File(filesDir, "home").apply { mkdirs() }
        File(filesDir, "tmp").mkdirs()
        File(filesDir, "usr").mkdirs()
        File(filesDir, "usr/bin").mkdirs()
        System.setProperty("awlqy.home", home.absolutePath)

        createNotificationChannel()
        Timber.i("awlqy by حسين الخلاقي — ready. home=%s", home.absolutePath)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel_session),
                NotificationManager.IMPORTANCE_LOW
            )
            val mgr = getSystemService(NotificationManager::class.java)
            mgr.createNotificationChannel(ch)
        }
    }

    companion object { const val CHANNEL_ID = "awlqy_session" }
}
