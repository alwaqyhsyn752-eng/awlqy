#include <jni.h>
#include <android/log.h>
#include <pty.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <string>

#define LOG_TAG "awlqy-pty"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {
[[noreturn]] void exec_shell() {
    const char *home = getenv("HOME");
    if (!home || !*home) home = "/data/local/tmp";
    if (chdir(home) != 0) chdir("/");
    const char *shell = getenv("AWLQY_SHELL");
    if (!shell || !*shell) shell = "/system/bin/sh";
    setenv("TERM",      "xterm-256color", 1);
    setenv("COLORTERM", "truecolor",      1);
    setenv("LANG",      "en_US.UTF-8",    1);
    setenv("LC_ALL",    "en_US.UTF-8",    1);
    execl(shell, shell, "-l", static_cast<char *>(nullptr));
    execl("/system/bin/sh", "sh", static_cast<char *>(nullptr));
    _exit(127);
}
}

extern "C" JNIEXPORT jintArray JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeOpen(
        JNIEnv *env, jclass, jint rows, jint cols,
        jstring jShell, jstring jCwd, jobjectArray jEnv) {

    const char *shell = jShell ? env->GetStringUTFChars(jShell, nullptr) : nullptr;
    const char *cwd   = jCwd   ? env->GetStringUTFChars(jCwd,   nullptr) : nullptr;
    if (shell && *shell) setenv("AWLQY_SHELL", shell, 1);
    if (cwd   && *cwd)   setenv("HOME",        cwd,   1);

    if (jEnv) {
        const jsize n = env->GetArrayLength(jEnv);
        for (jsize i = 0; i < n; ++i) {
            auto s = static_cast<jstring>(env->GetObjectArrayElement(jEnv, i));
            if (!s) continue;
            const char *c = env->GetStringUTFChars(s, nullptr);
            if (c) {
                const char *eq = strchr(c, '=');
                if (eq && eq != c) {
                    std::string key(c, static_cast<size_t>(eq - c));
                    setenv(key.c_str(), eq + 1, 1);
                }
                env->ReleaseStringUTFChars(s, c);
            }
            env->DeleteLocalRef(s);
        }
    }

    struct winsize ws{};
    ws.ws_row = rows > 0 ? (unsigned short)rows : 24;
    ws.ws_col = cols > 0 ? (unsigned short)cols : 80;

    int master = -1;
    pid_t pid = forkpty(&master, nullptr, nullptr, &ws);
    if (pid < 0) {
        LOGE("forkpty: %s", strerror(errno));
        if (shell) env->ReleaseStringUTFChars(jShell, shell);
        if (cwd)   env->ReleaseStringUTFChars(jCwd,   cwd);
        return nullptr;
    }
    if (pid == 0) exec_shell();

    int flags = fcntl(master, F_GETFL, 0);
    fcntl(master, F_SETFL, flags | O_NONBLOCK);

    if (shell) env->ReleaseStringUTFChars(jShell, shell);
    if (cwd)   env->ReleaseStringUTFChars(jCwd,   cwd);

    jintArray out = env->NewIntArray(2);
    jint vals[2] = { master, (jint)pid };
    env->SetIntArrayRegion(out, 0, 2, vals);
    return out;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeRead(
        JNIEnv *env, jclass, jint fd, jbyteArray buf, jint off, jint len) {
    if (fd < 0 || len <= 0) return -1;
    jbyte *data = env->GetByteArrayElements(buf, nullptr);
    ssize_t n = read(fd, data + off, (size_t)len);
    const int err = (n < 0) ? errno : 0;
    if (n > 0) { env->ReleaseByteArrayElements(buf, data, 0); return (jint)n; }
    env->ReleaseByteArrayElements(buf, data, JNI_ABORT);
    if (err == EAGAIN || err == EWOULDBLOCK) return 0;
    return -1;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeWrite(
        JNIEnv *env, jclass, jint fd, jbyteArray buf, jint off, jint len) {
    if (fd < 0 || len <= 0) return -1;
    jbyte *data = env->GetByteArrayElements(buf, nullptr);
    ssize_t total = 0;
    while (total < len) {
        ssize_t n = write(fd, data + off + total, (size_t)(len - total));
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) { usleep(500); continue; }
            break;
        }
        total += n;
    }
    env->ReleaseByteArrayElements(buf, data, JNI_ABORT);
    return (jint)total;
}

extern "C" JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeResize(
        JNIEnv *, jclass, jint fd, jint rows, jint cols) {
    if (fd < 0) return;
    struct winsize ws{};
    ws.ws_row = (unsigned short)rows;
    ws.ws_col = (unsigned short)cols;
    ioctl(fd, TIOCSWINSZ, &ws);
}

extern "C" JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeClose(JNIEnv *, jclass, jint fd) {
    if (fd >= 0) close(fd);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeWait(JNIEnv *, jclass, jint pid) {
    if (pid <= 0) return -1;
    int status = 0;
    while (waitpid((pid_t)pid, &status, 0) < 0 && errno == EINTR) {}
    if (WIFEXITED(status))   return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return status;
}

extern "C" JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeSignal(
        JNIEnv *, jclass, jint pid, jint sig) {
    if (pid > 0) kill((pid_t)pid, sig);
}

extern "C" JNIEXPORT void JNICALL
Java_com_awlqy_terminal_core_PtyBridge_nativeSignalGroup(
        JNIEnv *, jclass, jint pid, jint sig) {
    if (pid > 0) kill(-(pid_t)pid, sig);
}
