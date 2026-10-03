package com.awlqy.terminal.core

import android.content.Context
import android.text.SpannableStringBuilder
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

object SessionManager {

    data class Session(
        val id: String,
        val name: String,
        var cwd: File,
        val buffer: SpannableStringBuilder = SpannableStringBuilder(),
        val history: MutableList<String> = ArrayList(),
        var historyIndex: Int = -1,
        @Volatile var busy: Boolean = false,
        var lastExit: Int = 0
    )

    interface Listener {
        fun onSessionChanged(id: String)
        fun onSessionsListChanged()
        fun onActiveChanged(id: String)
    }

    private val sessions = ArrayList<Session>()
    private val listeners = LinkedHashSet<Listener>()
    @Volatile private var activeId: String = ""
    @Volatile private var homeDir: File? = null

    fun attachHome(home: File) {
        homeDir = home
        if (!home.exists()) home.mkdirs()
    }

    fun addListener(l: Listener) { synchronized(listeners) { listeners.add(l) } }
    fun removeListener(l: Listener) { synchronized(listeners) { listeners.remove(l) } }

    fun home(): File = homeDir ?: File("/data/local/tmp")

    fun list(): List<Session> = synchronized(sessions) { sessions.toList() }

    fun active(): Session? = synchronized(sessions) {
        sessions.firstOrNull { it.id == activeId } ?: sessions.firstOrNull()
    }

    fun setActive(id: String) {
        if (activeId == id) return
        activeId = id
        notifyActive(id)
    }

    fun create(name: String? = null, cwd: File? = null): Session {
        val n = (name ?: "session-${System.currentTimeMillis() % 100000}").trim()
        val s = Session(
            id = UUID.randomUUID().toString().take(8),
            name = n,
            cwd = (cwd ?: home()).apply { mkdirs() }
        )
        synchronized(sessions) { sessions.add(s) }
        if (activeId.isEmpty()) activeId = s.id
        notifyList()
        notifyActive(activeId)
        return s
    }

    fun close(id: String) {
        synchronized(sessions) { sessions.removeAll { it.id == id } }
        if (activeId == id) activeId = sessions.firstOrNull()?.id ?: ""
        notifyList()
        notifyActive(activeId)
        persist()
    }

    fun append(sessionId: String, text: CharSequence) {
        val s = sessions.firstOrNull { it.id == sessionId } ?: return
        s.buffer.append(text)
        trimBuffer(s.buffer, 200_000)
        notifyChanged(sessionId)
    }

    private fun trimBuffer(b: SpannableStringBuilder, max: Int) {
        if (b.length <= max) return
        val cut = b.length - max
        val nl = b.indexOf("\n", cut)
        val drop = if (nl > 0) nl + 1 else cut
        b.delete(0, drop)
    }

    private fun notifyChanged(id: String) {
        val snapshot = ArrayList<Listener>(listeners)
        snapshot.forEach { it.onSessionChanged(id) }
    }
    private fun notifyList() {
        val snapshot = ArrayList<Listener>(listeners)
        snapshot.forEach { it.onSessionsListChanged() }
    }
    private fun notifyActive(id: String) {
        val snapshot = ArrayList<Listener>(listeners)
        snapshot.forEach { it.onActiveChanged(id) }
    }

    // ─── Persistence ──────────────────────────────────

    fun persist() {
        val ctx = appContext ?: return
        try {
            val root = JSONObject()
            val arr = JSONArray()
            for (s in sessions) {
                val o = JSONObject()
                o.put("id", s.id)
                o.put("name", s.name)
                o.put("cwd", s.cwd.absolutePath)
                o.put("buffer", s.buffer.toString())
                val h = JSONArray(); s.history.forEach { h.put(it) }; o.put("history", h)
                arr.put(o)
            }
            root.put("sessions", arr)
            root.put("active", activeId)
            ctx.openFileOutput("sessions.json", Context.MODE_PRIVATE)
                .use { it.write(root.toString().toByteArray()) }
        } catch (_: Exception) { }
    }

    fun restore(ctx: Context) {
        appContext = ctx.applicationContext
        try {
            val f = File(ctx.filesDir, "sessions.json")
            if (!f.exists()) return
            val root = JSONObject(f.readText())
            val arr = root.optJSONArray("sessions") ?: JSONArray()
            synchronized(sessions) {
                sessions.clear()
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val s = Session(
                        id = o.optString("id", UUID.randomUUID().toString().take(8)),
                        name = o.optString("name", "session"),
                        cwd = File(o.optString("cwd", home().absolutePath))
                    )
                    s.buffer.append(o.optString("buffer", ""))
                    val h = o.optJSONArray("history")
                    if (h != null) for (j in 0 until h.length()) s.history.add(h.getString(j))
                    sessions.add(s)
                }
            }
            activeId = root.optString("active", sessions.firstOrNull()?.id ?: "")
        } catch (_: Exception) { }
    }

    @Volatile private var appContext: Context? = null
}
