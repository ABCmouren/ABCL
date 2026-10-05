#include "java_tool.h"
#include "log.h"
#include <jni.h>

#include <dlfcn.h>
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <cerrno>
#include <vector>
#include <string>
#include <sys/stat.h>

namespace hmcl {

namespace {

typedef jint (*CreateJavaVM_t)(JavaVM **, void **, void *);

/** 子进程：建 JVM 并调用 main */
int childRun(const std::string &javaHome,
             const std::string &classpath,
             const std::string &mainClass,
             const std::vector<std::string> &args,
             int xmxMb) {
    std::string libDir = javaHome + "/lib";
    std::string serverDir = libDir + "/server";

    setenv("JAVA_HOME", javaHome.c_str(), 1);
    // LD_LIBRARY_PATH 必须包含 libjvm.so 所在目录及其依赖（libjava.so、libjli.so、
    // libstdc++ 等）的目录，否则 dlopen 会报
    // "Error loading shared library …: No such file or directory" ——
    // 这条信息具有误导性，实际是依赖链里某个 .so 找不到，不是 libjvm.so 本身缺失。
    //
    // jdk8 的 libjvm 在 lib/aarch64/server/ 下，它依赖同级的
    // lib/aarch64/libjava.so、lib/aarch64/jli/*.so，
    // 所以要把架构目录也加进去。
    const char *archEnv[] = {"aarch64", "arm64-v8a", "x86_64", nullptr};
    std::vector<std::string> ldParts;
    ldParts.push_back(serverDir);
    ldParts.push_back(libDir);
    for (int i = 0; archEnv[i] != nullptr; i++) {
        std::string a = std::string(archEnv[i]);
        std::string archDir = libDir + "/" + a;
        struct stat st;
        if (stat(archDir.c_str(), &st) == 0) {
            ldParts.push_back(archDir);
            ldParts.push_back(archDir + "/server");
            ldParts.push_back(archDir + "/jli");
            // jdk8 还有一层 jre/lib
            ldParts.push_back(javaHome + "/jre/lib/" + a);
            ldParts.push_back(javaHome + "/jre/lib/" + a + "/server");
            ldParts.push_back(javaHome + "/jre/lib/" + a + "/jli");
        }
    }
    ldParts.push_back(javaHome + "/jre/lib");
    ldParts.push_back(javaHome + "/jre/lib/server");

    std::string ld;
    for (size_t i = 0; i < ldParts.size(); i++) {
        if (i > 0) {
            ld += ":";
        }
        ld += ldParts[i];
    }
    const char *oldLd = getenv("LD_LIBRARY_PATH");
    if (oldLd && oldLd[0]) {
        ld += ":";
        ld += oldLd;
    }
    setenv("LD_LIBRARY_PATH", ld.c_str(), 1);
    setenv("LC_ALL", "en_US.UTF-8", 1);

    // libjvm.so 的位置各版本不同，逐个尝试：
    //   jdk17/21 → lib/server/libjvm.so、lib/libjvm.so
    //   jdk8     → lib/aarch64/server/libjvm.so（带架构目录层级），
    //              且可能在 jdk8/lib 下，也可能在 jdk8/jre/lib 下
    // 原实现只试了前两种，jdk8 直接找不到（表现为 dlopen 失败返回 70）。
    const char *arches[] = {"aarch64", "arm64-v8a", "x86_64", nullptr};
    std::vector<std::string> candidates;
    candidates.push_back(serverDir + "/libjvm.so");
    candidates.push_back(libDir + "/libjvm.so");
    candidates.push_back(javaHome + "/jre/lib/server/libjvm.so");
    candidates.push_back(javaHome + "/jre/lib/libjvm.so");
    for (int i = 0; arches[i] != nullptr; i++) {
        std::string a = std::string(arches[i]);
        candidates.push_back(libDir + "/" + a + "/server/libjvm.so");
        candidates.push_back(javaHome + "/jre/lib/" + a + "/server/libjvm.so");
    }

    std::string jvmPath;
    void *handle = nullptr;
    // 先用 stat 过滤不存在的路径，减少无谓的 dlopen；
    // 但 stat 失败也不代表一定不存在（沙箱下偶发），
    // 所以过滤后若一个都没命中，再对全部候选裸试一次。
    std::vector<std::string> existing;
    for (size_t i = 0; i < candidates.size(); i++) {
        struct stat st;
        if (stat(candidates[i].c_str(), &st) == 0) {
            existing.push_back(candidates[i]);
        }
    }
    if (existing.empty()) {
        existing = candidates;
    }

    std::string lastError;
    for (size_t i = 0; i < existing.size(); i++) {
        handle = dlopen(existing[i].c_str(), RTLD_NOW | RTLD_GLOBAL);
        if (handle) {
            jvmPath = existing[i];
            break;
        }
        const char *err = dlerror();
        if (err != nullptr) {
            lastError = std::string(err);
        }
    }
    if (!handle) {
        fprintf(stderr, "[java_tool] dlopen libjvm.so failed under %s (%zu candidates)\n",
                javaHome.c_str(), existing.size());
        fprintf(stderr, "[java_tool]   last error: %s\n", lastError.c_str());
        for (size_t i = 0; i < existing.size(); i++) {
            fprintf(stderr, "[java_tool]   try: %s\n", existing[i].c_str());
        }
        // 架构不匹配是本项目最常见的失败原因：内置 JDK 全是 aarch64 的，
        // 在 x86 模拟器上 dlopen 必然失败（与 Forge processors 同一原因）。
        // 这里直接说明，避免把环境问题误判成路径问题。
        fprintf(stderr, "[java_tool]   提示：内置 JDK 为 aarch64；若当前是 x86 模拟器则无法加载，\n"
                        "[java_tool]   需在 arm64 真机上运行。\n");
        return 70;
    }
    fprintf(stderr, "[java_tool] libjvm loaded from %s\n", jvmPath.c_str());
    CreateJavaVM_t create = (CreateJavaVM_t) dlsym(handle, "JNI_CreateJavaVM");
    if (!create) {
        fprintf(stderr, "[java_tool] JNI_CreateJavaVM not found\n");
        return 70;
    }

    // 每个 processor 一个干净 classpath
    std::string cpOpt = "-Djava.class.path=" + classpath;
    std::string xmxOpt = "-Xmx" + std::to_string(xmxMb) + "m";
    std::string xmsOpt = "-Xms128m";

    const char *opts[] = {
        cpOpt.c_str(),
        xmxOpt.c_str(),
        xmsOpt.c_str(),
        "-XX:TieredStopAtLevel=1",
        "-Dfile.encoding=UTF-8",
        "-Dsun.jnu.encoding=UTF-8",
        "-Djava.awt.headless=true",
    };
    const int nOpts = (int) (sizeof(opts) / sizeof(opts[0]));

    JavaVMOption vmOptions[8];
    for (int i = 0; i < nOpts; i++) {
        vmOptions[i].optionString = const_cast<char *>(opts[i]);
        vmOptions[i].extraInfo = nullptr;
    }

    JavaVMInitArgs vmArgs;
    memset(&vmArgs, 0, sizeof(vmArgs));
    vmArgs.version = JNI_VERSION_1_8;
    vmArgs.nOptions = nOpts;
    vmArgs.options = vmOptions;
    vmArgs.ignoreUnrecognized = JNI_TRUE;

    JavaVM *jvm = nullptr;
    JNIEnv *env = nullptr;
    jint rc = create(&jvm, (void **) &env, &vmArgs);
    if (rc != JNI_OK || !env) {
        fprintf(stderr, "[java_tool] JNI_CreateJavaVM failed rc=%d\n", (int) rc);
        return 71;
    }

    jclass cls = env->FindClass(mainClass.c_str());
    // FindClass 需要斜杠形式
    if (!cls) {
        if (env->ExceptionCheck()) env->ExceptionClear();
        std::string slashed = mainClass;
        for (size_t i = 0; i < slashed.size(); i++) {
            if (slashed[i] == '.') slashed[i] = '/';
        }
        cls = env->FindClass(slashed.c_str());
    }
    if (!cls) {
        if (env->ExceptionCheck()) env->ExceptionDescribe();
        fprintf(stderr, "[java_tool] class not found: %s\n", mainClass.c_str());
        return 72;
    }

    jmethodID mainMethod = env->GetStaticMethodID(cls, "main", "([Ljava/lang/String;)V");
    if (!mainMethod) {
        if (env->ExceptionCheck()) env->ExceptionDescribe();
        fprintf(stderr, "[java_tool] main(String[]) not found in %s\n", mainClass.c_str());
        return 73;
    }

    jclass stringClass = env->FindClass("java/lang/String");
    jobjectArray argArray = env->NewObjectArray((jsize) args.size(), stringClass, nullptr);
    for (size_t i = 0; i < args.size(); i++) {
        jstring s = env->NewStringUTF(args[i].c_str());
        env->SetObjectArrayElement(argArray, (jsize) i, s);
        env->DeleteLocalRef(s);
    }

    env->CallStaticVoidMethod(cls, mainMethod, argArray);
    if (env->ExceptionCheck()) {
        env->ExceptionDescribe();
        env->ExceptionClear();
        return 74;
    }

    // 不调 DestroyJavaVM（可能被非守护线程挂住），产物已落盘
    return 0;
}

} // namespace

int runJavaTool(const std::string &javaHome,
                const std::string &classpath,
                const std::string &mainClass,
                const std::vector<std::string> &args,
                const std::string &workDir,
                const std::string &logFile,
                int xmxMb) {
    logInfo("java_tool", "fork run: main=" + mainClass + " cp=" + std::to_string(classpath.size()) + " chars");

    pid_t pid = fork();
    if (pid < 0) {
        logError("java_tool", "fork failed: " + std::string(strerror(errno)));
        return -1;
    }
    if (pid == 0) {
        if (!logFile.empty()) {
            int fd = open(logFile.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd >= 0) {
                dup2(fd, STDOUT_FILENO);
                dup2(fd, STDERR_FILENO);
                close(fd);
            }
        }
        if (!workDir.empty()) {
            if (chdir(workDir.c_str()) != 0) {
                fprintf(stderr, "[java_tool] chdir failed: %s\n", workDir.c_str());
            }
        }
        int rc = childRun(javaHome, classpath, mainClass, args, xmxMb);
        fflush(stdout);
        fflush(stderr);
        _exit(rc);
    }

    int status = 0;
    pid_t waited = waitpid(pid, &status, 0);
    while (waited < 0 && errno == EINTR) {
        waited = waitpid(pid, &status, 0);
    }
    if (waited < 0) {
        logError("java_tool", "waitpid failed: " + std::string(strerror(errno)));
        return -2;
    }
    if (WIFEXITED(status)) {
        int code = WEXITSTATUS(status);
        logInfo("java_tool", "child exit code=" + std::to_string(code));
        return code;
    }
    if (WIFSIGNALED(status)) {
        int sig = WTERMSIG(status);
        logError("java_tool", "child killed by signal " + std::to_string(sig));
        return -128 + sig;
    }
    return -2;
}

} // namespace hmcl
