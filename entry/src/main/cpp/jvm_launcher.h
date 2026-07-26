/**
 * HMCL Native Bridge - JVM Launcher
 * 
 * Initializes the Java Virtual Machine from a cross-compiled OpenJDK runtime
 * and launches Minecraft via the amcl-launcher.jar entry point.
 *
 * The launch flow:
 * 1. Locate JDK runtime (downloaded to app sandbox)
 * 2. Set up environment (JAVA_HOME, LD_LIBRARY_PATH, etc.)
 * 3. Load libjvm.so via custom ELF loader (JIT bypass)
 * 4. Call JNI_CreateJavaVM
 * 5. Load AmclLauncher main class
 * 6. Invoke AmclLauncher.main() with LaunchConfig JSON
 * 7. Monitor game process
 */

#ifndef HMCL_JVM_LAUNCHER_H
#define HMCL_JVM_LAUNCHER_H

#include <string>
#include <vector>
#include <functional>
#include <atomic>
#include <thread>
#include <jni.h>

namespace hmcl {

// Status of the JVM/game lifecycle
enum class LaunchStatus {
    IDLE,
    INITIALIZING,
    JVM_READY,
    LAUNCHING,
    RUNNING,
    STOPPING,
    STOPPED,
    ERROR
};

// GPU information
struct GpuInfo {
    std::string name;
    std::string vendor;
    std::string version;
    std::string glVersion;
    std::string glslVersion;
    int maxTextureSize = 0;
    bool supportsVulkan = false;
};

// JVM options
struct JvmOptions {
    std::string javaHome;       // Path to JDK runtime
    std::string gameDir;        // Game/Minecraft directory
    std::string mcDir;          // .minecraft directory
    std::string filesDir;       // App files directory
    std::string assetsDir;      // Assets directory
    std::string mainClass;      // Minecraft main class
    std::vector<std::string> classpath;  // Classpath entries
    std::vector<std::string> mcArgs;     // Minecraft arguments
    int minMemory = 512;        // -Xms in MB
    int maxMemory = 1024;       // -Xmx in MB
    bool isForge = false;
    bool isFabric = false;
    bool headlessAwt = true;    // Use headless AWT mode
    int width = 854;
    int height = 480;
    bool fullscreen = false;
    bool jitEnabled = true;     // Use JIT (requires ELF loader)
    std::string customJvmArgs;
    std::string gameLanguage;   // Game language override
};

// Callbacks for game lifecycle events
using StatusCallback = std::function<void(LaunchStatus)>;
using LogCallback = std::function<void(const std::string&)>;

/**
 * JVM Launcher - manages the JVM lifecycle for Minecraft
 */
class JvmLauncher {
public:
    JvmLauncher();
    ~JvmLauncher();

    /**
     * Initialize the JVM runtime
     * @param javaHome Path to the JDK runtime directory
     * @return true on success
     */
    bool initRuntime(const std::string &javaHome);

    /**
     * Check if JIT is available (writable+executable memory)
     */
    bool checkJitAvailable();

    /**
     * Get device GPU information
     */
    GpuInfo getGpuInfo();

    /**
     * Launch Minecraft with the given options
     * This call blocks while the game is running
     * @param opts JVM and game options
     * @return 0 on success, non-zero on failure
     */
    int launch(const JvmOptions &opts);

    /**
     * Request game shutdown
     */
    void stop();

    /**
     * Force exit the game process
     */
    void forceExit();

    /**
     * Get current launch status
     */
    LaunchStatus getStatus() const { return m_status.load(); }

    /**
     * Check if game is still running
     */
    bool isRunning() const { 
        return m_status.load() == LaunchStatus::RUNNING; 
    }

    /**
     * Read the game log buffer
     */
    std::string readLog();

    /**
     * Set lifecycle callbacks
     */
    void setStatusCallback(StatusCallback cb) { m_statusCb = cb; }
    void setLogCallback(LogCallback cb) { m_logCb = cb; }

private:
    std::atomic<LaunchStatus> m_status{LaunchStatus::IDLE};
    std::string m_javaHome;
    std::string m_logBuffer;
    std::mutex m_logMutex;

    StatusCallback m_statusCb;
    LogCallback m_logCb;

    // JVM handles
    JavaVM *m_jvm = nullptr;
    JNIEnv *m_env = nullptr;
    void *m_jvmLibHandle = nullptr;

    // Internal methods
    typedef jint (*JNI_CreateJavaVM_t)(JavaVM**, JNIEnv**, JavaVMInitArgs*);
    JNI_CreateJavaVM_t m_jniCreateJavaVM = nullptr;

    bool loadJvmLibrary(const std::string &javaHome);
    bool createJvm(const JvmOptions &opts, JavaVMInitArgs &vmArgs);
    JavaVMOption* buildJvmOptions(const JvmOptions &opts, int &optCount);
    int invokeMainClass(const JvmOptions &opts);
    std::string buildLaunchConfigJson(const JvmOptions &opts);
    std::string escapeJson(const std::string &s);
    void setLaunchStatus(LaunchStatus status);

    void appendLog(const std::string &line);
};

} // namespace hmcl

#endif // HMCL_JVM_LAUNCHER_H
