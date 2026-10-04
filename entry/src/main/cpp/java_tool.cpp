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
    std::string ld = serverDir + ":" + libDir;
    const char *oldLd = getenv("LD_LIBRARY_PATH");
    if (oldLd && oldLd[0]) {
        ld += ":";
        ld += oldLd;
    }
    setenv("LD_LIBRARY_PATH", ld.c_str(), 1);
    setenv("LC_ALL", "en_US.UTF-8", 1);

    std::string jvmPath = serverDir + "/libjvm.so";
    void *handle = dlopen(jvmPath.c_str(), RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        jvmPath = libDir + "/libjvm.so";
        handle = dlopen(jvmPath.c_str(), RTLD_NOW | RTLD_GLOBAL);
    }
    if (!handle) {
        fprintf(stderr, "[java_tool] dlopen libjvm.so failed: %s\n", dlerror() ? dlerror() : "unknown");
        return 70;
    }
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
