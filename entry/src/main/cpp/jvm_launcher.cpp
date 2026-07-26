/**
 * HMCL Native Bridge - JVM Launcher Implementation
 * Based on reverse-engineered AMCL launch flow
 */

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
    // Build JVM arguments based on AMCL's patterns
    std::vector<JavaVMOption> options;
    
    auto addOpt = [&](const std::string &opt) {
        JavaVMOption vmOpt;
        vmOpt.optionString = strdup(opt.c_str());
        vmOpt.extraInfo = nullptr;
        options.push_back(vmOpt);
    };
    
    // Memory settings
    addOpt("-Xms" + std::to_string(opts.minMemory) + "m");
    addOpt("-Xmx" + std::to_string(opts.maxMemory) + "m");
    
    // GC settings (consistent with AMCL)
    addOpt("-XX:+UnlockExperimentalVMOptions");
    addOpt("-XX:+UseG1GC");
    addOpt("-XX:+UnlockDiagnosticVMOptions");
    addOpt("-XX:-UseCompressedOops");
    addOpt("-XX:-UsePerfData");
    addOpt("-XX:+DisableAttachMechanism");
    addOpt("-XX:+DisablePrimordialThreadGuardPages");
    addOpt("-XX:ActiveProcessorCount=8");
    if (opts.jitEnabled) {
        addOpt("-XX:TieredStopAtLevel=1");  // C1 compilation only for faster start
    }
    
    // Java system properties (matching AMCL)
    addOpt("-Djava.awt.headless=true");
    addOpt("-Djava.system.class.loader=com.amcl.launcher.AmclClassLoader");
    addOpt("-Damcl.platform.ohos=true");
    addOpt("-Dfile.encoding=UTF-8");
    addOpt("-Dsun.jnu.encoding=UTF-8");
    addOpt("-Djava.security.egd=file:/dev/./urandom");
    addOpt("-Dorg.lwjgl.glfw.checkThread0=false");
    addOpt("-Dlog4j2.formatMsgNoLookups=true");
    addOpt("-Dsodium.checks.issue2561=false");
    
    addOpt("-Damcl.mc.dir=" + opts.gameDir);
    addOpt("-Duser.dir=" + opts.gameDir);
    addOpt("-Duser.home=" + opts.gameDir);
    addOpt("-Djava.io.tmpdir=" + opts.filesDir + "/tmp");
    
    std::string jreLib = m_javaHome + "/lib";
    addOpt("-Dsun.boot.library.path=" + jreLib);
    addOpt("-Djava.library.path=" + jreLib + ":" + opts.filesDir + "/natives");
    addOpt("-Djava.home=" + m_javaHome);
    
    addOpt("-Dorg.lwjgl.shaderc.libname=shaderc");
    addOpt("-Dorg.lwjgl.spvc.libname=spirv-cross");
    addOpt("-Dorg.lwjgl.vulkan.libname=libvulkan.so");
    
    if (opts.isFabric) {
        addOpt("-Dfabric.noGui=true");
    }
    
    if (!opts.gameLanguage.empty()) {
        addOpt("-Damcl.gamelang=" + opts.gameLanguage);
    }
    
    // Set classpath for amcl-launcher.jar
    std::string cp = opts.filesDir + "/amcl-launcher.jar";
    for (const auto &entry : opts.classpath) {
        cp += ":" + entry;
    }
    addOpt("-Djava.class.path=" + cp);
    
    // Custom JVM args
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
    
    // Allocate array
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
    // Build the JSON config string that AmclLauncher expects
    // Format is reverse-engineered from AMCL's LaunchConfig parser
    
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
    
    // Build the launch config JSON
    std::string launchConfig = buildLaunchConfigJson(opts);
    appendLog("[HMCL] Launch config: " + launchConfig);
    std::cout << "[AmclLauncher] Launch config: " << launchConfig << std::endl;
    
    // Find AmclLauncher class
    jclass launcherClass = m_env->FindClass("com/amcl/launcher/AmclLauncher");
    if (!launcherClass) {
        if (m_env->ExceptionCheck()) {
            m_env->ExceptionClear();
        }
        logError("JvmLauncher", "Cannot find AmclLauncher class in classpath");
        appendLog("[HMCL] ERROR: AmclLauncher not found. Check amcl-launcher.jar in filesDir.");
        return -1;
    }
    
    // Find main method
    jmethodID mainMethod = m_env->GetStaticMethodID(launcherClass, "main", "([Ljava/lang/String;)V");
    if (!mainMethod) {
        if (m_env->ExceptionCheck()) {
            m_env->ExceptionClear();
        }
        logError("JvmLauncher", "Cannot find AmclLauncher.main method");
        return -1;
    }
    
    // Build args array
    jclass stringClass = m_env->FindClass("java/lang/String");
    jobjectArray argsArray = m_env->NewObjectArray(1, stringClass, nullptr);
    jstring configArg = m_env->NewStringUTF(launchConfig.c_str());
    m_env->SetObjectArrayElement(argsArray, 0, configArg);
    
    // Invoke AmclLauncher.main()
    logInfo("JvmLauncher", "Calling AmclLauncher.main()...");
    appendLog("[HMCL] Starting Minecraft via AmclLauncher...");
    
    m_env->CallStaticVoidMethod(launcherClass, mainMethod, argsArray);
    
    // Check for exceptions
    if (m_env->ExceptionCheck()) {
        m_env->ExceptionDescribe();  // Print to stderr
        m_env->ExceptionClear();
        logError("JvmLauncher", "AmclLauncher.main() threw an exception");
        appendLog("[HMCL] ERROR: AmclLauncher.main() threw an exception");
        return -1;
    }
    
    logInfo("JvmLauncher", "AmclLauncher.main() returned successfully");
    appendLog("[HMCL] Minecraft exited normally");
    
    return 0;
}

int JvmLauncher::launch(const JvmOptions &opts) {
    logInfo("JvmLauncher", "Launching Minecraft...");
    setLaunchStatus(LaunchStatus::LAUNCHING);
    
    appendLog("[HMCL] Launching " + opts.mainClass);
    appendLog("[HMCL] Game dir: " + opts.gameDir);
    appendLog("[HMCL] Java home: " + m_javaHome);
    appendLog("[HMCL] Forge: " + std::to_string(opts.isForge));
    appendLog("[HMCL] Fabric: " + std::to_string(opts.isFabric));
    appendLog("[HMCL] Memory: " + std::to_string(opts.minMemory) + "/" + std::to_string(opts.maxMemory) + "MB");
    appendLog("[HMCL] Classpath entries: " + std::to_string(opts.classpath.size()));
    
    // Step 1: Create JVM
    JavaVMInitArgs vmArgs;
    if (!createJvm(opts, vmArgs)) {
        setLaunchStatus(LaunchStatus::ERROR);
        appendLog("[HMCL] ERROR: Failed to create JVM");
        return -1;
    }
    
    setLaunchStatus(LaunchStatus::JVM_READY);
    
    // Step 2: Mark as RUNNING before blocking call
    // AmclLauncher.main() blocks until the game window closes
    setLaunchStatus(LaunchStatus::RUNNING);
    appendLog("[HMCL] AmclLauncher.main() starting (game is now RUNNING)");
    
    // Step 3: Invoke Minecraft main class via AmclLauncher
    int result = invokeMainClass(opts);
    
    // AmclLauncher.main() returned - game has exited
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
