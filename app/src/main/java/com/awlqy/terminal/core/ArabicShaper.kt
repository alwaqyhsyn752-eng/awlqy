package com.awlqy.terminal.core

object ArabicShaper {
    init { System.loadLibrary("awlqy_engine") }
    external fun nativeShapeTerminal(src: String): String
    external fun nativeShapeLogical(src: String): String
    external fun nativeContainsArabic(src: String): Boolean
    external fun nativeHarfBuzzShape(text: String, fontPath: String, pixelSize: Int, rtl: Boolean): IntArray?
    external fun nativeHarfBuzzVersion(): String

    fun shapeForTerminal(input: String): String = nativeShapeTerminal(input)
    fun shapeLogical(input: String): String = nativeShapeLogical(input)
    fun hasArabic(input: String): Boolean = nativeContainsArabic(input)
}
