package com.awlqy.terminal.core

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

object SessionManager {

    class Session(
        val id: String,
        val name: String,
        var cwd: File
    ) {
        val buffer: StringBuilder = StringBuilder()
        val history: MutableList<String> = ArrayList()
        @Volatile var historyIndex: Int = -1
        @Volatile var busy: Boolean = false
        @Volatile var lastExit: Int = 0
    }

    interface Listener {
        fun onSessionChanged(id: String)
        fun onSessionsListChanged()
        fun onActiveChanged(id: String)
    }

    private val sessions = ArrayList<Session>()
    private val listeners = LinkedHashSet<Listener>()

    @Volatile private var activeId: String = ""
    @Volatile private var homeDir: File? = null
    @Volatile private var appContext: Context? = null

    fun attachHome(home: File) {
        homeDir = home
        if (!home.exists()) home.mkdirs()
    }

    fun attachContext(ctx: Context) {
        appContext = ctx.applicationContext
    }

    fun home(): File = homeDir ?: File("/data/local/tmp")

    @Synchronized fun addListener(l: Listener) { listeners.add(l) }
    @Synchronized fun removeListener(l: Listener) { listeners.remove(l) }

    @Synchronized fun list(): List<Session> = ArrayList(sessions)

    @Synchronized fun active(): Session? =
        sessions.firstOrNull { it.id == activeId } ?: sessions.firstOrNull()

    @Synchronized fun setActive(id: String) {
        if (activeId == id) return
        activeId = id
        notifyActive(id)
    }

    @Synchronized fun create(name: String? = null, cwd: File? = null): Session {
        val n = (name ?: "session-${System.currentTimeMillis() % 100000}").trim()
        val s = Session(
            id = UUID.randomUUID().toString().take(8),
            name = n,
            cwd = (cwd ?: home()).apply { mkdirs() }
        )
        sessions.add(s)
        if (activeId.isEmpty()) activeId = s.id
        notifyList()
        notifyActive(activeId)
        return s
    }

    @Synchronized fun close(id: String) {
        sessions.removeAll { it.id == id }
        if (activeId == id) activeId = sessions.firstOrNull()?.id ?: ""
        notifyList()
        notifyActive(activeId)
        persist()
    }

    @Synchronized fun append(sessionId: String, text: CharSequence) {
        val s = sessions.firstOrNull { it.id == sessionId } ?: return
        s.buffer.append(text)
        trim(s.buffer, 200_000)
        notifyChanged(sessionId)
    }

    private fun trim(b: StringBuilder, max: Int) {
        if (b.length <= max) return
        val cut = b.length - max
        val nl = b.indexOf("\n", cut)
        val drop = if (nl > 0) nl + 1 else cut
        b.delete(0, drop)
    }

    private fun notifyChanged(id: String) {
        val snap = ArrayList<Listener>(listeners)
        for (l in snap) try { l.onSessionChanged(id) } catch (_: Exception) { }
    }
    private fun notifyList() {
        val snap = ArrayList<Listener>(listeners)
        for (l in snap) try { l.onSessionsListChanged() } catch (_: Exception) { }
    }
    private fun notifyActive(id: String) {
        val snap = ArrayList<Listener>(listeners)
        for (l in snap) try { l.onActiveChanged(id) } catch (_: Exception) { }
    }

    // ─── Persistence ────────────────────────────────────

    fun persist() {
        val ctx = appContext ?: return
        try {
            val root = JSONObject()
            val arr = JSONArray()
            val snapshot = list()
            for (s in snapshot) {
                val o = JSONObject()
                o.put("id", s.id)
                o.put("name", s.name)
                o.put("cwd", s.cwd.absolutePath)
                o.put("buffer", s.buffer.toString())
                val h = JSONArray()
                for (item in s.history) h.put(item)
                o.put("history", h)
                arr.put(o)
            }
            root.put("sessions", arr)
            root.put("active", activeId)
            ctx.openFileOutput("sessions.json", Context.MODE_PRIVATE)
                .use { it.write(root.toString().toByteArray(Charsets.UTF_8)) }
        } catch (_: Exception) { }
    }

    fun restore(ctx: Context) {
        appContext = ctx.applicationContext
        try {
            val f = File(ctx.filesDir, "sessions.json")
            if (!f.exists()) return
            val root = JSONObject(f.readText())
            val arr = root.optJSONArray("sessions") ?: JSONArray()
            synchronized(this) {
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
                val act = root.optString("active", "")
                activeId = if (act.isNotEmpty()) act else (sessions.firstOrNull()?.id ?: "")
            }
        } catch (_: Exception) { }
    }
}
