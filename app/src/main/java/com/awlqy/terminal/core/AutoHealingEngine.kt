package com.awlqy.terminal.core

/**
 * محرّك الإصلاح الذكي.
 * يحلّل مخرجات الأخطاء ويولّد خطة إصلاح قابلة للتنفيذ.
 */
object AutoHealingEngine {

    data class HealPlan(
        val summary: String,
        val suggestion: String?,
        val autoRetryCommand: String?
    )

    private data class Rule(
        val regex: Regex,
        val summarize: (MatchResult) -> String,
        val suggestion: (MatchResult) -> String,
        val retry: (MatchResult) -> String?
    )

    private val rules: List<Rule> = listOf(

        Rule(
            Regex("ModuleNotFoundError: No module named '([A-Za-z0-9_\\-.]+)'"),
            { "مكتبة Python مفقودة: ${it.groupValues[1]}" },
            { "شغّل: python -m pip install ${it.groupValues[1]}" },
            { "python -m pip install --no-input ${it.groupValues[1]}" }
        ),

        Rule(
            Regex("ImportError: cannot import name '([A-Za-z0-9_\\-.]+)'"),
            { "استيراد فاشل: ${it.groupValues[1]}" },
            { "تحقق من الاسم، أو: python -m pip install --upgrade ${it.groupValues[1]}" },
            { null }
        ),

        Rule(
            Regex("Cannot find module '([^']+)'"),
            { "حزمة Node.js مفقودة: ${it.groupValues[1]}" },
            { "شغّل: npm install ${it.groupValues[1]}" },
            { "npm install ${it.groupValues[1]}" }
        ),

        Rule(
            Regex("([^\\s:]+): not found"),
            { "أمر غير معروف: ${it.groupValues[1]}" },
            { "ليس في PATH. ثبّته أو صحّح الاسم." },
            { null }
        ),

        Rule(
            Regex("command not found"),
            { "الأمر غير موجود في النظام" },
            { "تحقق من الإملاء أو ثبّت الحزمة المطلوبة." },
            { null }
        ),

        Rule(
            Regex("No such file or directory"),
            { "الملف أو المجلد غير موجود" },
            { "تحقق من المسار بـ ls ثم أعد المحاولة." },
            { null }
        ),

        Rule(
            Regex("Permission denied"),
            { "صلاحية مرفوضة" },
            { "جرّب: chmod +x <file> أو شغّل المسار المصرّح به." },
            { null }
        ),

        Rule(
            Regex("SyntaxError: (.+)"),
            { "خطأ بنيوي: ${it.groupValues[1]}" },
            { "راجع علامات الاقتباس، الأقواس، والمسافات البادئة." },
            { null }
        ),

        Rule(
            Regex("is a directory"),
            { "المسار مجلد وليس ملفاً" },
            { "استخدم ls لاستعراض المحتوى." },
            { null }
        ),

        Rule(
            Regex("No space left on device"),
            { "المساحة ممتلئة" },
            { "احذف ملفات cache: rm -rf \$HOME/.cache/*" },
            { "rm -rf \$HOME/.cache/* 2>/dev/null; echo cleaned" }
        ),

        Rule(
            Regex("Could not resolve host|Cannot resolve host|Network is unreachable"),
            { "تعذّر الوصول إلى الشبكة" },
            { "تحقق من الاتصال بالإنترنت." },
            { null }
        ),

        Rule(
            Regex("EACCES \\(Permission denied\\)"),
            { "صلاحية مرفوضة على الملف/المسار" },
            { "chmod +x أو غيّر مسار الكتابة." },
            { null }
        ),

        Rule(
            Regex("Killed"),
            { "تم إنهاء العملية (نفاد ذاكرة أو إشارة SIGKILL)" },
            { "جرّب أمراً أخف، أو زد الذاكرة المتاحة." },
            { null }
        ),

        Rule(
            Regex("git: command not found"),
            { "git غير مثبت" },
            { "ثبّت git عبر مدير الحزم أو استخدم نسخة مدمجة." },
            { null }
        ),

        Rule(
            Regex("fatal: not a git repository"),
            { "هذا المجلد ليس مستودع git" },
            { "شغّل: git init ثم أعد الأمر." },
            { "git init" }
        ),

        Rule(
            Regex("fatal: refusing to merge unrelated histories"),
            { "فروع git غير متصلة" },
            { "استخدم: git pull --allow-unrelated-histories" },
            { "git pull --allow-unrelated-histories" }
        ),

        Rule(
            Regex("error: failed to push some refs"),
            { "رفض git push" },
            { "شغّل: git pull --rebase ثم push." },
            { "git pull --rebase" }
        ),

        Rule(
            Regex("javac: not found|java: not found"),
            { "أدوات Java غير متوفرة" },
            { "ثبّت JDK أو استخدم مساراً بديلاً." },
            { null }
        ),

        Rule(
            Regex("pip: command not found|pip3: not found"),
            { "pip غير متوفر" },
            { "جرّب: python -m ensurepip ثم python -m pip install --upgrade pip" },
            { "python -m ensurepip && python -m pip install --upgrade pip" }
        ),

        Rule(
            Regex("npm: command not found"),
            { "npm غير متوفر" },
            { "ثبّت Node.js، أو استخدم node مباشرة." },
            { null }
        )
    )

    fun analyze(exitCode: Int, stdout: String, stderr: String): HealPlan? {
        if (exitCode == 0) return null
        val s = "$stderr\n$stdout"
        if (s.isBlank()) return null

        for (rule in rules) {
            val m = rule.regex.find(s) ?: continue
            return HealPlan(
                summary = rule.summarize(m),
                suggestion = rule.suggestion(m),
                autoRetryCommand = rule.retry(m)
            )
        }

        return HealPlan(
            summary = "فشل التنفيذ (exit=$exitCode)",
            suggestion = "راجع المخرجات، جرّب تشغيل الأمر يدوياً.",
            autoRetryCommand = null
        )
    }
}
