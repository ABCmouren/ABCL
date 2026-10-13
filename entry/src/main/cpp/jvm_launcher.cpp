/**
 * HMCL Native Bridge - JVM Launcher Implementation
 * The launch core is our own implementation: it assembles the classpath from
 * the version manifest, resolves the main class per mod loader, builds the
 * JVM options and invokes <mainClass>.main(). No third-party launcher class
 * or jar is loaded anywhere in the launch path.
 */

// 启动器版本（写入 -Dminecraft.launcher.version）
#define ABCL_VERSION "2.0.0"

#include "jvm_launcher.h"
#include "elf_loader.h"
#include "log.h"

#include <dlfcn.h>
#include <cstring>
#include <sstream>
#include <fstream>
#include <iostream>
#include <sys/stat.h>
#include <unistd.h>
#include <dirent.h>
#include <stdlib.h>
#include <stdio.h>

namespace hmcl {

JvmLauncher::JvmLauncher() {
    logInfo("JvmLauncher", "Created");
}

JvmLauncher::~JvmLauncher() {
    forceExit();
    if (m_jvm) {
        // Don't destroy JVM here - it may take time
        m_jvm = nullptr;
    }
    if (m_jvmLibHandle) {
        dlclose(m_jvmLibHandle);
        m_jvmLibHandle = nullptr;
    }
}

bool JvmLauncher::initRuntime(const std::string &javaHome) {
    logInfo("JvmLauncher", "Initializing runtime at: " + javaHome);
    
    // Verify javaHome exists
    struct stat st;
    std::string jvmLibPath = javaHome + "/lib/server/libjvm.so";
    if (stat(jvmLibPath.c_str(), &st) != 0) {
        std::string libPath2 = javaHome + "/lib/libjvm.so";
        if (stat(libPath2.c_str(), &st) != 0) {
            logError("JvmLauncher", "libjvm.so not found at: " + jvmLibPath);
            return false;
        }
    }
    
    m_javaHome = javaHome;
    
    // Set environment variables
    setenv("JAVA_HOME", javaHome.c_str(), 1);
    
    std::string libPath = javaHome + "/lib:" + javaHome + "/lib/server";
    std::string jreLibPath = javaHome + "/lib";
    
    // Preserve existing LD_LIBRARY_PATH
    const char *existing = getenv("LD_LIBRARY_PATH");
    if (existing) {
        libPath = libPath + ":" + existing;
    }
    setenv("LD_LIBRARY_PATH", libPath.c_str(), 1);
    
    logInfo("JvmLauncher", "JAVA_HOME=" + m_javaHome);
    logInfo("JvmLauncher", "LD_LIBRARY_PATH=" + libPath);
    
    return loadJvmLibrary(javaHome);
}

bool JvmLauncher::loadJvmLibrary(const std::string &javaHome) {
    // First try the custom ELF loader for JIT support
    std::string jvmPath = javaHome + "/lib/server/libjvm.so";
    
    // Try standard dlopen first
    m_jvmLibHandle = dlopen(jvmPath.c_str(), RTLD_NOW | RTLD_GLOBAL);
    if (!m_jvmLibHandle) {
        const char *err = dlerror();
        logWarn("JvmLauncher", "dlopen failed: " + std::string(err ? err : "unknown"));
        
        // Fallback: try loading from just lib/
        jvmPath = javaHome + "/lib/libjvm.so";
        m_jvmLibHandle = dlopen(jvmPath.c_str(), RTLD_NOW | RTLD_GLOBAL);
    }
    
    if (!m_jvmLibHandle) {
        const char *err = dlerror();
        logError("JvmLauncher", "Failed to load libjvm.so: " + std::string(err ? err : "unknown"));
        
        // Last resort: try the full javaHome path with subdirs
        std::vector<std::string> searchPaths = {
            "/lib/server/libjvm.so",
            "/lib/libjvm.so",
            "/jre/lib/server/libjvm.so",
            "/jre/lib/aarch64/server/libjvm.so"
        };
        
        for (const auto &suffix : searchPaths) {
            std::string path = javaHome + suffix;
            logInfo("JvmLauncher", "Trying: " + path);
            m_jvmLibHandle = dlopen(path.c_str(), RTLD_NOW | RTLD_GLOBAL);
            if (m_jvmLibHandle) {
                logInfo("JvmLauncher", "Found libjvm.so at: " + path);
                break;
            }
        }
    }
    
    if (!m_jvmLibHandle) {
        logError("JvmLauncher", "Could not load libjvm.so from any path");
        return false;
    }
    
    // Resolve JNI_CreateJavaVM
    m_jniCreateJavaVM = (JNI_CreateJavaVM_t)dlsym(m_jvmLibHandle, "JNI_CreateJavaVM");
    if (!m_jniCreateJavaVM) {
        logError("JvmLauncher", "Cannot find JNI_CreateJavaVM in libjvm.so");
        dlclose(m_jvmLibHandle);
        m_jvmLibHandle = nullptr;
        return false;
    }
    
    logInfo("JvmLauncher", "libjvm.so loaded successfully, JNI_CreateJavaVM resolved");
    return true;
}

bool JvmLauncher::checkJitAvailable() {
    return getElfLoader().isJitAvailable();
}

GpuInfo JvmLauncher::getGpuInfo() {
    GpuInfo info;
    info.name = "HarmonyOS Device GPU";
    info.vendor = "Huawei";
    info.version = "1.0";
    info.glVersion = "OpenGL ES 3.2";
    info.glslVersion = "OpenGL ES GLSL ES 3.20";
    info.maxTextureSize = 4096;
    info.supportsVulkan = false;
    
    // Try to get EGL GPU info
    void *eglLib = dlopen("libEGL.so", RTLD_NOW);
    if (eglLib) {
        typedef const char* (*EGLQueryString_t)(void*, int);
        EGLQueryString_t eglQueryString = (EGLQueryString_t)dlsym(eglLib, "eglQueryString");
        if (eglQueryString) {
            // We need EGLDisplay to query - for now return basic info
            logInfo("JvmLauncher", "EGL library loaded for GPU info");
        }
        dlclose(eglLib);
    }
    
    return info;
}

JavaVMOption* JvmLauncher::buildJvmOptions(const JvmOptions &opts, int &optCount) {
    // 组装 JVM 启动参数。
    //
    // 分两部分：
    //   1) 启动核心自己的参数 —— 内存、GC、目录、编码、原生库路径、
    //      以及 Minecraft / LWJGL / Forge 在 Linux 系内核上通用的开关。
    //      classpath 完全由引擎从版本清单解析出的依赖构成。
    //   2) 设备兼容层（vendored，来自 AMCL，GPL-3.0）—— 只有当它的 jar 确实
    //      存在时才启用。它通过替换系统类加载器做字节码变换，修正鸿蒙 GPU
    //      上的地形渲染。注意：一旦声明了 java.system.class.loader 却找不到
    //      那个类，JNI_CreateJavaVM 会直接失败，所以这里必须先探测文件。
    std::vector<JavaVMOption> options;

    auto addOpt = [&](const std::string &opt) {
        JavaVMOption vmOpt;
        vmOpt.optionString = strdup(opt.c_str());
        vmOpt.extraInfo = nullptr;
        options.push_back(vmOpt);
    };

    // ---- 设备兼容层是否存在 ----
    const std::string compatJar = opts.filesDir + "/amcl-launcher.jar";
    struct stat compatStat;
    const bool compatAvailable =
        opts.deviceCompat && (stat(compatJar.c_str(), &compatStat) == 0);
    if (opts.deviceCompat && !compatAvailable) {
        logWarn("JvmLauncher", "device compat jar not found: " + compatJar);
    }

    // ---- 内存 ----
    addOpt("-Xms" + std::to_string(opts.minMemory) + "m");
    addOpt("-Xmx" + std::to_string(opts.maxMemory) + "m");

    // ---- GC 与运行时 ----
    addOpt("-XX:+UnlockExperimentalVMOptions");
    addOpt("-XX:+UseG1GC");
    addOpt("-XX:+UnlockDiagnosticVMOptions");
    addOpt("-XX:-UseCompressedOops");
    addOpt("-XX:-UsePerfData");
    addOpt("-XX:+DisableAttachMechanism");
    addOpt("-XX:+DisablePrimordialThreadGuardPages");
    addOpt("-XX:ActiveProcessorCount=8");
    if (opts.jitEnabled) {
        addOpt("-XX:TieredStopAtLevel=1");
    }

    // ---- 基础属性 ----
    addOpt("-Djava.awt.headless=true");
    addOpt("-Dfile.encoding=UTF-8");
    addOpt("-Dsun.jnu.encoding=UTF-8");
    addOpt("-Djava.security.egd=file:/dev/./urandom");
    addOpt("-Dlog4j2.formatMsgNoLookups=true");

    // ---- 工作目录 ----
    addOpt("-Duser.dir=" + opts.gameDir);
    addOpt("-Duser.home=" + opts.gameDir);
    addOpt("-Djava.io.tmpdir=" + opts.filesDir + "/tmp");

    // ---- 本启动器自己的标识 ----
    addOpt("-Dabcl.platform=ohos");
    addOpt("-Dabcl.mc.dir=" + opts.gameDir);
    addOpt("-Dminecraft.launcher.brand=ABCL");
    addOpt("-Dminecraft.launcher.version=" + std::string(ABCL_VERSION));

    // ---- 原生库路径 ----
    std::string jreLib = m_javaHome + "/lib";
    addOpt("-Dsun.boot.library.path=" + jreLib);
    addOpt("-Djava.library.path=" + jreLib + ":" + opts.filesDir + "/natives");
    addOpt("-Djava.home=" + m_javaHome);

    // ---- LWJGL / GLFW ----
    addOpt("-Dorg.lwjgl.glfw.checkThread0=false");
    addOpt("-Dorg.lwjgl.shaderc.libname=shaderc");
    addOpt("-Dorg.lwjgl.spvc.libname=spirv-cross");
    addOpt("-Dorg.lwjgl.vulkan.libname=libvulkan.so");

    // ---- Forge / Mod 兼容 ----
    addOpt("-Dfml.earlyprogresswindow=false");
    addOpt("-Dforge.enableGameTest=false");
    addOpt("-Dsodium.checks.issue2561=false");

    if (opts.isFabric) {
        addOpt("-Dfabric.noGui=true");
    }
    if (!opts.gameLanguage.empty()) {
        addOpt("-Dabcl.gamelang=" + opts.gameLanguage);
    }

    // ---- 设备兼容层的开关 ----
    // amcl.platform.ohos=true 是兼容层启用字节码变换的前置条件
    // （见 AmclClassLoader 的 PLATFORM_COMPATIBILITY_ENABLED）。
    // 这里沿用它的属性名：兼容层是它的代码，按它的契约传参。
    if (compatAvailable) {
        addOpt("-Damcl.platform.ohos=true");
        addOpt("-Djava.system.class.loader=com.amcl.launcher.AmclClassLoader");
    }

    // ---- classpath ----
    std::string cp;
    if (compatAvailable) {
        cp = compatJar;
    }
    for (size_t i = 0; i < opts.classpath.size(); i++) {
        if (cp.length() > 0) {
            cp += ":";
        }
        cp += opts.classpath[i];
    }
    addOpt("-Djava.class.path=" + cp);
    logInfo("JvmLauncher", "classpath entries: " +
            std::to_string(opts.classpath.size() + (compatAvailable ? 1 : 0)));
    appendLog(compatAvailable
        ? "[ABCL] 设备兼容层：已启用（AmclClassLoader + 地形渲染适配）"
        : "[ABCL] 设备兼容层：未启用（未找到 amcl-launcher.jar）");

    // ---- 用户自定义 JVM 参数 ----
    if (!opts.customJvmArgs.empty()) {
        std::istringstream stream(opts.customJvmArgs);
        std::string arg;
        while (stream >> arg) {
            if (arg.length() > 0) {
                addOpt(arg);
            }
        }
    }

    optCount = (int)options.size();

    JavaVMOption *result = new JavaVMOption[options.size()];
    for (size_t i = 0; i < options.size(); i++) {
        result[i] = options[i];
    }

    return result;
}

bool JvmLauncher::createJvm(const JvmOptions &opts, JavaVMInitArgs &vmArgs) {
    logInfo("JvmLauncher", "Creating JVM...");
    
    int optCount;
    JavaVMOption *options = buildJvmOptions(opts, optCount);
    
    // Select JNI version based on javaHome path to support JDK 8/17/21
    jint jniVersion = JNI_VERSION_1_8;
    if (m_javaHome.find("jdk21") != std::string::npos ||
        m_javaHome.find("jdk-21") != std::string::npos) {
        jniVersion = JNI_VERSION_21;
    } else if (m_javaHome.find("jdk17") != std::string::npos ||
               m_javaHome.find("jdk-17") != std::string::npos) {
        jniVersion = JNI_VERSION_10;  // JDK 17 maps to JNI 10 (0x000A0000)
    }
    vmArgs.version = jniVersion;
    vmArgs.options = options;
    vmArgs.nOptions = optCount;
    vmArgs.ignoreUnrecognized = JNI_TRUE;
    
    jint result = m_jniCreateJavaVM(&m_jvm, &m_env, &vmArgs);
    
    // Clean up duplicated option strings (handled in try/catch normally)
    for (int i = 0; i < optCount; i++) {
        if (options[i].optionString) {
            free((void*)options[i].optionString);
        }
    }
    delete[] options;
    
    if (result != JNI_OK) {
        logError("JvmLauncher", "JNI_CreateJavaVM failed with error: " + std::to_string(result));
        m_jvm = nullptr;
        m_env = nullptr;
        return false;
    }
    
    logInfo("JvmLauncher", "JVM created successfully");
    return true;
}

std::string JvmLauncher::escapeJson(const std::string &s) {
    std::string result;
    result.reserve(s.length());
    for (char c : s) {
        switch (c) {
            case '"': result += "\\\""; break;
            case '\\': result += "\\\\"; break;
            case '\n': result += "\\n"; break;
            case '\r': result += "\\r"; break;
            case '\t': result += "\\t"; break;
            default: result += c;
        }
    }
    return result;
}

std::string JvmLauncher::buildLaunchConfigJson(const JvmOptions &opts) {
    // 设备兼容层的启动配置（9 个字段，对应它的 LaunchConfig.parse()）。
    // 只有兼容层读这个 JSON；本启动器的入口调用不走它。
    // 键名必须逐字一致。
    
    std::ostringstream json;
    json << "{";
    
    json << "\"mainClass\":\"" << escapeJson(opts.mainClass) << "\",";
    
    json << "\"classpath\":[";
    for (size_t i = 0; i < opts.classpath.size(); i++) {
        if (i > 0) json << ",";
        json << "\"" << escapeJson(opts.classpath[i]) << "\"";
    }
    json << "],";
    
    json << "\"mcArgs\":[";
    // Build standard Minecraft arguments
    std::vector<std::string> mcArgs;
    // Main MC args are passed to this array
    mcArgs = opts.mcArgs;
    for (size_t i = 0; i < mcArgs.size(); i++) {
        if (i > 0) json << ",";
        json << "\"" << escapeJson(mcArgs[i]) << "\"";
    }
    json << "],";
    
    json << "\"gameDir\":\"" << escapeJson(opts.gameDir) << "\",";
    json << "\"mcDir\":\"" << escapeJson(opts.mcDir) << "\",";
    json << "\"filesDir\":\"" << escapeJson(opts.filesDir) << "\",";
    json << "\"assetsDir\":\"" << escapeJson(opts.assetsDir) << "\",";
    json << "\"isForge\":" << (opts.isForge ? "true" : "false") << ",";
    json << "\"isFabric\":" << (opts.isFabric ? "true" : "false");
    
    json << "}";
    return json.str();
}


int JvmLauncher::invokeMainClass(const JvmOptions &opts) {
    logInfo("JvmLauncher", "Invoking main class: " + opts.mainClass);

    if (!m_env) {
        logError("JvmLauncher", "JNIEnv is null");
        return -1;
    }

    // ============================================================
    // 阶段 1：设备兼容层准备（vendored，来自 AMCL，GPL-3.0）
    //
    // 它把系统类加载器换成 AmclClassLoader 并做字节码变换，修正鸿蒙 GPU
    // 上的地形渲染（TerrainCompatibility / TerrainHeap / TerrainStaging /
    // TerrainRangeRetirement 等），另外做 Forge 的 fml.toml + splash.properties
    // 预处理与 context ClassLoader 设置。
    //
    // 只调它的 prepare()，不调它的 main() —— 入口调用在阶段 2 由我们自己完成。
    // 两者都必须在同一线程上，这是它的 ThreadLocal 契约。
    // ============================================================
    if (opts.deviceCompat) {
        const std::string cfg = buildLaunchConfigJson(opts);
        jclass compatCls = m_env->FindClass("com/amcl/launcher/AmclLauncher");
        if (compatCls == nullptr) {
            if (m_env->ExceptionCheck()) {
                m_env->ExceptionClear();
            }
            logWarn("JvmLauncher", "device compat layer not reachable");
            appendLog("[ABCL] 警告：设备兼容层不可用，按原版行为启动（地形渲染可能异常）");
        } else {
            jmethodID prepareM = m_env->GetStaticMethodID(
                compatCls, "prepare", "(Ljava/lang/String;)V");
            if (prepareM == nullptr) {
                if (m_env->ExceptionCheck()) {
                    m_env->ExceptionClear();
                }
                appendLog("[ABCL] 警告：设备兼容层缺少 prepare()，按原版行为启动");
            } else {
                jstring cfgArg = m_env->NewStringUTF(cfg.c_str());
                appendLog("[ABCL] 设备兼容层：prepare() 开始");
                m_env->CallStaticVoidMethod(compatCls, prepareM, cfgArg);
                if (m_env->ExceptionCheck()) {
                    m_env->ExceptionDescribe();
                    m_env->ExceptionClear();
                    logError("JvmLauncher", "compat prepare() failed");
                    appendLog("[ABCL] 警告：设备兼容层 prepare() 失败，继续启动"
                              "（地形渲染可能异常）");
                } else {
                    logInfo("JvmLauncher", "device compat layer prepared");
                    appendLog("[ABCL] 设备兼容层：prepare() 完成");
                }
                if (cfgArg != nullptr) {
                    m_env->DeleteLocalRef(cfgArg);
                }
            }
            m_env->DeleteLocalRef(compatCls);
        }
    }

    // ============================================================
    // 阶段 2：调用游戏入口（本启动器自己的启动核心）
    // ============================================================

    // JNI 的类名用 '/' 分隔
    std::string slashed;
    slashed.reserve(opts.mainClass.size());
    for (size_t i = 0; i < opts.mainClass.size(); i++) {
        char c = opts.mainClass[i];
        slashed += (c == '.') ? '/' : c;
    }

    appendLog("[ABCL] main class : " + opts.mainClass);
    appendLog("[ABCL] classpath  : " + std::to_string(opts.classpath.size()) + " entries");
    appendLog("[ABCL] game args  : " + std::to_string(opts.mcArgs.size()) + " args");

    // 从系统类加载器解析入口类。启用兼容层时它就是 AmclClassLoader，
    // 因此这里加载到的类已经过它的字节码变换。
    jclass mainCls = m_env->FindClass(slashed.c_str());
    if (mainCls == nullptr) {
        if (m_env->ExceptionCheck()) {
            m_env->ExceptionDescribe();
            m_env->ExceptionClear();
        }
        logError("JvmLauncher", "Cannot find main class: " + opts.mainClass);
        appendLog("[ABCL] ERROR: 找不到入口类 " + opts.mainClass);
        appendLog("[ABCL]        请确认该版本的依赖已下载完整（libraries + 版本 jar）");
        appendLog("[ABCL]        classpath 条目数：" + std::to_string(opts.classpath.size()));
        for (size_t i = 0; i < opts.classpath.size() && i < 40; i++) {
            appendLog("[ABCL]          - " + opts.classpath[i]);
        }
        return -1;
    }

    jmethodID mainMethod = m_env->GetStaticMethodID(mainCls, "main", "([Ljava/lang/String;)V");
    if (mainMethod == nullptr) {
        if (m_env->ExceptionCheck()) {
            m_env->ExceptionClear();
        }
        logError("JvmLauncher", "main(String[]) not found in " + opts.mainClass);
        appendLog("[ABCL] ERROR: " + opts.mainClass + " 没有 main(String[]) 方法");
        return -1;
    }

    jclass stringClass = m_env->FindClass("java/lang/String");
    if (stringClass == nullptr) {
        if (m_env->ExceptionCheck()) {
            m_env->ExceptionClear();
        }
        return -1;
    }

    jobjectArray argsArray = m_env->NewObjectArray((jsize)opts.mcArgs.size(), stringClass, nullptr);
    if (argsArray == nullptr) {
        if (m_env->ExceptionCheck()) {
            m_env->ExceptionClear();
        }
        return -1;
    }
    for (size_t i = 0; i < opts.mcArgs.size(); i++) {
        jstring argStr = m_env->NewStringUTF(opts.mcArgs[i].c_str());
        if (argStr == nullptr) {
            if (m_env->ExceptionCheck()) {
                m_env->ExceptionClear();
            }
            continue;
        }
        m_env->SetObjectArrayElement(argsArray, (jsize)i, argStr);
        m_env->DeleteLocalRef(argStr);
    }

    setLaunchStatus(LaunchStatus::RUNNING);
    appendLog("[ABCL] Starting Minecraft (" + opts.mainClass + ")...");
    logInfo("JvmLauncher", "Calling " + opts.mainClass + ".main()...");

    m_env->CallStaticVoidMethod(mainCls, mainMethod, argsArray);

    if (m_env->ExceptionCheck()) {
        m_env->ExceptionDescribe();
        m_env->ExceptionClear();
        logError("JvmLauncher", opts.mainClass + ".main() threw an exception");
        appendLog("[ABCL] ERROR: " + opts.mainClass + ".main() 抛出异常");
        return -1;
    }

    logInfo("JvmLauncher", opts.mainClass + ".main() returned");
    appendLog("[ABCL] Minecraft exited normally");
    return 0;
}

int JvmLauncher::launch(const JvmOptions &opts) {
    logInfo("JvmLauncher", "Launching Minecraft...");
    setLaunchStatus(LaunchStatus::LAUNCHING);
    
    appendLog("[ABCL] Launching " + opts.mainClass);
    appendLog("[ABCL] Game dir: " + opts.gameDir);
    appendLog("[ABCL] Java home: " + m_javaHome);
    appendLog("[ABCL] Forge: " + std::to_string(opts.isForge));
    appendLog("[ABCL] Fabric: " + std::to_string(opts.isFabric));
    appendLog("[ABCL] Memory: " + std::to_string(opts.minMemory) + "/" + std::to_string(opts.maxMemory) + "MB");
    appendLog("[ABCL] Classpath entries: " + std::to_string(opts.classpath.size()));
    
    // Step 1: Create JVM
    JavaVMInitArgs vmArgs;
    if (!createJvm(opts, vmArgs)) {
        setLaunchStatus(LaunchStatus::ERROR);
        appendLog("[ABCL] ERROR: Failed to create JVM");
        return -1;
    }
    
    setLaunchStatus(LaunchStatus::JVM_READY);
    
    // Step 2: Mark as RUNNING before blocking call
    // <mainClass>.main() blocks until the game window closes
    setLaunchStatus(LaunchStatus::RUNNING);
    appendLog("[ABCL] entering main loop (game is now RUNNING)");
    
    // Step 3: invoke the resolved Minecraft main class
    int result = invokeMainClass(opts);
    
    // <mainClass>.main() returned - game has exited
    if (result == 0) {
        setLaunchStatus(LaunchStatus::STOPPED);
    } else {
        setLaunchStatus(LaunchStatus::ERROR);
    }
    
    // Destroy JVM
    if (m_jvm) {
        m_jvm->DestroyJavaVM();
        m_jvm = nullptr;
        m_env = nullptr;
    }
    
    logInfo("JvmLauncher", "Launch completed with result: " + std::to_string(result));
    return result;
}

void JvmLauncher::stop() {
    if (m_status.load() == LaunchStatus::RUNNING) {
        setLaunchStatus(LaunchStatus::STOPPING);
        // Signal JVM to shut down
        if (m_jvm) {
            m_jvm->DetachCurrentThread();
        }
    }
}

void JvmLauncher::forceExit() {
    if (m_jvm) {
        logInfo("JvmLauncher", "Force exiting JVM");
        m_jvm->DestroyJavaVM();
        m_jvm = nullptr;
        m_env = nullptr;
    }
    setLaunchStatus(LaunchStatus::STOPPED);
}

std::string JvmLauncher::readLog() {
    std::lock_guard<std::mutex> lock(m_logMutex);
    std::string log = m_logBuffer;
    m_logBuffer.clear();
    return log;
}

void JvmLauncher::setLaunchStatus(LaunchStatus status) {
    m_status.store(status);
    if (m_statusCb) {
        m_statusCb(status);
    }
}

void JvmLauncher::appendLog(const std::string &line) {
    std::lock_guard<std::mutex> lock(m_logMutex);
    m_logBuffer += line + "\n";
    std::cout << line << std::endl;  // Also write to stdout
    if (m_logCb) {
        m_logCb(line);
    }
}

}  // namespace hmcl
