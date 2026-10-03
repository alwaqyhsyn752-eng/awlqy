package com.awlqy.terminal

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.GravityCompat
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentActivity
import androidx.viewpager2.adapter.FragmentStateAdapter
import com.awlqy.terminal.databinding.ActivityMainBinding
import com.awlqy.terminal.service.AwlqySessionService
import com.awlqy.terminal.ui.fragments.*
import com.google.android.material.tabs.TabLayoutMediator
import timber.log.Timber

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val terminalTabs = mutableListOf<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setSupportActionBar(binding.toolbar)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        binding.toolbar.setNavigationOnClickListener {
            binding.drawerLayout.openDrawer(GravityCompat.START)
        }

        setupViewPager()
        setupDrawer()

        binding.fabNewSession.setOnClickListener {
            addTerminalTab("session-${terminalTabs.size + 1}")
        }

        addTerminalTab("main")

        // شغّل الخدمة الأمامية
        startForegroundService(Intent(this, AwlqySessionService::class.java))
    }

    private fun setupViewPager() {
        binding.viewPager.adapter = TerminalPagerAdapter(this)
        TabLayoutMediator(binding.tabLayout, binding.viewPager) { tab, pos ->
            tab.text = terminalTabs.getOrElse(pos) { "؟" }
        }.attach()
    }

    private fun addTerminalTab(name: String) {
        terminalTabs.add(name)
        binding.viewPager.adapter?.notifyDataSetChanged()
        binding.viewPager.setCurrentItem(terminalTabs.size - 1, true)
    }

    private fun setupDrawer() {
        binding.navView.setNavigationItemSelectedListener { item ->
            when (item.itemId) {
                R.id.nav_terminal -> { /* الطرفية مرئية أساساً */ }
                R.id.nav_settings -> replaceContent(SettingsFragment())
                R.id.nav_help     -> replaceContent(HelpFragment())
                R.id.nav_code     -> replaceContent(CodeGuideFragment())
                R.id.nav_ascii    -> replaceContent(AsciiFragment())
                R.id.nav_pkg      -> replaceContent(PkgFragment())
                R.id.nav_apk      -> replaceContent(ApkFragment())
                R.id.nav_about    -> showAbout()
            }
            binding.drawerLayout.closeDrawer(GravityCompat.START)
            true
        }
    }

    private fun replaceContent(f: Fragment) {
        supportFragmentManager.beginTransaction()
            .replace(android.R.id.content, f)
            .addToBackStack(null)
            .commit()
    }

    private fun showAbout() {
        Toast.makeText(
            this,
            "awlqy v${BuildConfig.VERSION_NAME}\nالمطوّر: ${getString(R.string.developer_name)}",
            Toast.LENGTH_LONG
        ).show()
    }

    inner class TerminalPagerAdapter(activity: FragmentActivity) : FragmentStateAdapter(activity) {
        override fun getItemCount(): Int = terminalTabs.size
        override fun createFragment(position: Int): Fragment =
            TerminalFragment.newInstance(terminalTabs[position])
    }
}
