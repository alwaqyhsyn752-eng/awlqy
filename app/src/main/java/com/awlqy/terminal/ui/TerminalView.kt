package com.awlqy.terminal.ui

import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import com.awlqy.terminal.core.ArabicShaper
import kotlin.math.min

class TerminalView @JvmOverloads constructor(
    ctx: Context, attrs: AttributeSet? = null, def: Int = 0
) : View(ctx, attrs, def) {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.MONOSPACE
        textSize = 28f
        color = Color.parseColor("#E6EDF3")
    }
    private val bgPaint = Paint().apply { color = Color.parseColor("#0A0E14") }

    private val lines = ArrayDeque<String>()
    private val maxLines = 2000
    private var cols = 0
    private var rows = 0
    private var cursorVisible = true

    var rtlEnabled: Boolean = true
    var onInput: ((String) -> Unit)? = null
    var sizeListener: ((rows: Int, cols: Int) -> Unit)? = null

    init {
        setLayerType(LAYER_TYPE_HARDWARE, null)
    }

    fun append(text: String) {
        // تقسيم إلى أسطر معالجة CR/LF
        val normalized = text.replace("\r\n", "\n").replace('\r', '\n')
        for (line in normalized.split('\n')) {
            if (lines.isEmpty() || lastEndsWithNewline) {
                lines.addLast(line)
            } else {
                lines[lines.size - 1] = lines.last() + line
            }
            lastEndsWithNewline = false
        }
        if (normalized.endsWith('\n')) lastEndsWithNewline = true
        while (lines.size > maxLines) lines.removeFirst()
        postInvalidateOnAnimation()
    }

    private var lastEndsWithNewline = true

    fun clear() { lines.clear(); postInvalidateOnAnimation() }

    fun fullText(): String = lines.joinToString("\n")

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val fm = paint.fontMetrics
        val lineH = (fm.descent - fm.ascent)
        val charW = paint.measureText("M")
        cols = (w / charW).toInt().coerceAtLeast(20)
        rows = (h / lineH).toInt().coerceAtLeast(5)
        sizeListener?.invoke(rows, cols)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bgPaint)
        val fm = paint.fontMetrics
        val lineH = (fm.descent - fm.ascent) + 2f
        var y = -fm.ascent + 4f
        val visible = min(rows, lines.size)
        val start = lines.size - visible
        for (i in 0 until visible) {
            val raw = lines[start + i]
            val display = if (rtlEnabled && ArabicShaper.hasArabic(raw))
                ArabicShaper.shapeForTerminal(raw) else raw
            canvas.drawText(display, 6f, y, paint)
            y += lineH
        }
        // cursor blinking
        if (cursorVisible && lines.isNotEmpty()) {
            val last = lines.last()
            val w = paint.measureText(if (rtlEnabled) ArabicShaper.shapeForTerminal(last) else last)
            canvas.drawRect(6f + w, y - lineH + 4f, 6f + w + 3f, y + 2f, paint)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_DOWN) {
            cursorVisible = !cursorVisible
            postInvalidateOnAnimation()
            return true
        }
        return super.onTouchEvent(event)
    }
}
