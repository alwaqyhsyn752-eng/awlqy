package com.awlqy.terminal

import android.os.Bundle
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import timber.log.Timber

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(getColor(R.color.awlqy_bg))
            setPadding(48, 96, 48, 48)
        }

        val title = TextView(this).apply {
            text = getString(R.string.app_name)
            textSize = 42f
            setTextColor(getColor(R.color.awlqy_accent))
            gravity = Gravity.CENTER
        }

        val tagline = TextView(this).apply {
            text = getString(R.string.app_tagline)
            textSize = 14f
            setTextColor(getColor(R.color.awlqy_text_dim))
            gravity = Gravity.CENTER
            setPadding(0, 12, 0, 0)
        }

        val dev = TextView(this).apply {
            text = "${getString(R.string.developer_name)} — ${getString(R.string.developer_role)}"
            textSize = 16f
            setTextColor(getColor(R.color.awlqy_text))
            gravity = Gravity.CENTER
            setPadding(0, 48, 0, 0)
        }

        val phase = TextView(this).apply {
            text = "PHASE 1 · Skeleton Ready"
            textSize = 12f
            setTextColor(getColor(R.color.awlqy_text_dim))
            gravity = Gravity.CENTER
            setPadding(0, 24, 0, 0)
        }

        root.addView(title)
        root.addView(tagline)
        root.addView(dev)
        root.addView(phase)

        setContentView(root)

        Timber.i("MainActivity ready — waiting for Phase 2")
    }
}
