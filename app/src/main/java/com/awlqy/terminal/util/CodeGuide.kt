package com.awlqy.terminal.util

/**
 * دليل أكواد متعدد اللغات: قوالب + أمثلة + أفضل الممارسات.
 */
object CodeGuide {

    data class Lang(val id: String, val name: String, val hello: String, val template: String)

    val languages: List<Lang> = listOf(
        Lang("python", "Python",
            "print('مرحباً من awlqy')",
            """
def main():
    import sys
    args = sys.argv[1:]
    print("awlqy · Python ready", args)

if __name__ == "__main__":
    main()
            """.trimIndent()),
        Lang("bash", "Bash",
            "echo 'مرحباً من awlqy'",
            """
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
echo "awlqy · Bash ready"
for f in *; do echo "- ${'$'}f"; done
            """.trimIndent()),
        Lang("js", "JavaScript",
            "console.log('مرحباً من awlqy')",
            """
const name = "awlqy";
console.log(`${'$'}{name} · Node.js ready`);
export default function main() { return name; }
            """.trimIndent()),
        Lang("ts", "TypeScript",
            "const msg: string = 'مرحباً';\nconsole.log(msg);",
            """
interface App { name: string; version: string; }
const app: App = { name: "awlqy", version: "1.0.0" };
console.log(`${'$'}{app.name} v${'$'}{app.version}`);
            """.trimIndent()),
        Lang("cpp", "C++",
            "#include <iostream>\nint main(){ std::cout << \"مرحباً\\n\"; }",
            """
#include <iostream>
#include <string>
int main(int argc, char** argv) {
    std::string name = "awlqy";
    std::cout << name << " · C++ ready" << std::endl;
    return 0;
}
            """.trimIndent()),
        Lang("go", "Go",
            "package main\nimport \"fmt\"\nfunc main(){ fmt.Println(\"مرحباً\") }",
            """
package main
import "fmt"
func main() {
    fmt.Println("awlqy · Go ready")
}
            """.trimIndent()),
        Lang("rust", "Rust",
            "fn main(){ println!(\"مرحباً\"); }",
            """
fn main() {
    let name = "awlqy";
    println!("{} · Rust ready", name);
}
            """.trimIndent()),
        Lang("java", "Java",
            "public class M{ public static void main(String[] a){ System.out.println(\"مرحباً\"); }}",
            """
public class Main {
    public static void main(String[] args) {
        String name = "awlqy";
        System.out.println(name + " · Java ready");
    }
}
            """.trimIndent()),
        Lang("php", "PHP",
            "<?php echo 'مرحباً';",
            """
<?php
${'$'}name = "awlqy";
echo "${'$'}name · PHP ready\\n";
            """.trimIndent())
    )

    fun byId(id: String): Lang? = languages.firstOrNull { it.id == id }
    fun cheatSheet(): String = languages.joinToString("\n") { "- ${it.id}: ${it.hello}" }
}
