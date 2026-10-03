package com.awlqy.terminal.util

/**
 * مولّد لافتات ASCII ومؤثرات نصية للطرفية.
 */
object AsciiArt {

    fun banner(text: String, char: Char = '█'): String {
        val font = blockFont()
        val letters = text.uppercase().toCharArray()
        val rows = 7
        val sb = StringBuilder()
        for (r in 0 until rows) {
            for (c in letters) {
                val glyph = font[c] ?: continue
                sb.append(glyph[r].replace('#', char)).append(' ')
            }
            sb.append('\n')
        }
        return sb.toString()
    }

    fun frame(title: String, lines: List<String>, width: Int = 60): String {
        val sb = StringBuilder()
        sb.append('┌').append("─".repeat(width - 2)).append('┐').append('\n')
        val t = " $title "
        val left = (width - 2 - t.length) / 2
        sb.append('│').append(" ".repeat(left.coerceAtLeast(0)))
          .append(t)
          .append(" ".repeat((width - 2 - t.length - left).coerceAtLeast(0)))
          .append('│').append('\n')
        sb.append('├').append("─".repeat(width - 2)).append('┤').append('\n')
        lines.forEach { ln ->
            val pad = width - 4 - ln.length
            sb.append("│ ").append(ln)
              .append(" ".repeat(pad.coerceAtLeast(0))).append(" │").append('\n')
        }
        sb.append('└').append("─".repeat(width - 2)).append('┘')
        return sb.toString()
    }

    fun progress(pct: Int, width: Int = 30): String {
        val p = pct.coerceIn(0, 100)
        val filled = (p * width) / 100
        return "[${"█".repeat(filled)}${"░".repeat(width - filled)}] $p%"
    }

    private fun blockFont(): Map<Char, Array<String>> = mapOf(
        'A' to arrayOf("  ###  ", " ## ## ", "##   ##", "#######", "##   ##", "##   ##", "##   ##"),
        'B' to arrayOf("###### ", "##   ##", "##   ##", "###### ", "##   ##", "##   ##", "###### "),
        'C' to arrayOf("  #### ", " ##  ##", "##     ", "##     ", "##     ", " ##  ##", "  #### "),
        'D' to arrayOf("#####  ", "##  ## ", "##   ##", "##   ##", "##   ##", "##  ## ", "#####  "),
        'E' to arrayOf("#######", "##     ", "##     ", "#####  ", "##     ", "##     ", "#######"),
        'F' to arrayOf("#######", "##     ", "##     ", "#####  ", "##     ", "##     ", "##     "),
        'G' to arrayOf("  #### ", " ##  ##", "##     ", "##  ###", "##   ##", " ##  ##", "  #### "),
        'H' to arrayOf("##   ##", "##   ##", "##   ##", "#######", "##   ##", "##   ##", "##   ##"),
        'I' to arrayOf("#######", "  ###  ", "  ###  ", "  ###  ", "  ###  ", "  ###  ", "#######"),
        'J' to arrayOf("  #####", "    ## ", "    ## ", "    ## ", "##  ## ", " ## ## ", "  ###  "),
        'K' to arrayOf("##   ##", "##  ## ", "## ##  ", "####   ", "## ##  ", "##  ## ", "##   ##"),
        'L' to arrayOf("##     ", "##     ", "##     ", "##     ", "##     ", "##     ", "#######"),
        'M' to arrayOf("##   ##", "### ###", "#######", "## # ##", "##   ##", "##   ##", "##   ##"),
        'N' to arrayOf("##   ##", "###  ##", "#### ##", "## ####", "##  ###", "##   ##", "##   ##"),
        'O' to arrayOf("  ###  ", " ## ## ", "##   ##", "##   ##", "##   ##", " ## ## ", "  ###  "),
        'P' to arrayOf("###### ", "##   ##", "##   ##", "###### ", "##     ", "##     ", "##     "),
        'Q' to arrayOf("  ###  ", " ## ## ", "##   ##", "##   ##", "## # ##", " ## ## ", "  ### #"),
        'R' to arrayOf("###### ", "##   ##", "##   ##", "###### ", "## ##  ", "##  ## ", "##   ##"),
        'S' to arrayOf("  #### ", " ##  ##", "##     ", " ##### ", "     ##", "##  ## ", " ####  "),
        'T' to arrayOf("#######", "  ###  ", "  ###  ", "  ###  ", "  ###  ", "  ###  ", "  ###  "),
        'U' to arrayOf("##   ##", "##   ##", "##   ##", "##   ##", "##   ##", "##   ##", " ##### "),
        'V' to arrayOf("##   ##", "##   ##", "##   ##", "##   ##", " ## ## ", " ## ## ", "  ###  "),
        'W' to arrayOf("##   ##", "##   ##", "##   ##", "## # ##", "#######", "### ###", "##   ##"),
        'X' to arrayOf("##   ##", " ## ## ", "  ###  ", "  ###  ", "  ###  ", " ## ## ", "##   ##"),
        'Y' to arrayOf("##   ##", " ## ## ", "  ###  ", "  ###  ", "  ###  ", "  ###  ", "  ###  "),
        'Z' to arrayOf("#######", "     ##", "    ## ", "  ###  ", " ##    ", "##     ", "#######"),
        ' ' to arrayOf("       ", "       ", "       ", "       ", "       ", "       ", "       ")
    )
}
