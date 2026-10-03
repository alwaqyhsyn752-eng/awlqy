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
        File(filesDir, "tmp").mkdirs()
        File(filesDir, "usr").mkdirs()
        File(filesDir, "usr/bin").mkdirs()

        createNotificationChannel()

        Timber.i("awlqy phase-1 booted — developer: %s", DEVELOPER)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel_session),
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = getString(R.string.app_tagline)
                setShowBadge(false)
            }
            val mgr = getSystemService(NotificationManager::class.java)
            mgr.createNotificationChannel(channel)
        }
    }

    companion object {
        const val CHANNEL_ID = "awlqy_session"
        const val DEVELOPER = "حسين الخلاقي"
    }
}
