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

        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }

        File(filesDir, "home").mkdirs()
        File(filesDir, "usr").mkdirs()
        File(filesDir, "usr/bin").mkdirs()
        File(filesDir, "apk-work").mkdirs()
        File(filesDir, "logs").mkdirs()

        createNotificationChannel()
        Timber.i("awlqy booted — phase-1 — developer: حسين الخلاقي")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel),
                NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
            val mgr = getSystemService(NotificationManager::class.java)
            mgr?.createNotificationChannel(ch)
        }
    }

    companion object {
        const val CHANNEL_ID = "awlqy_session"
        const val DEVELOPER = "حسين الخلاقي"
    }
}
