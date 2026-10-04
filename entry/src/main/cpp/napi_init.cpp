/**
 * HMCL Native Bridge - NAPI Entry Point
 * 
 * Registers all native functions callable from ArkTS.
 * This is the main bridge between HMCL's ArkTS UI and the native JVM layer.
 *
 * Exported NAPI functions (mirroring AMCL's interface):
 * - jvmInit(javaHome: string): boolean
 * - jvmCheckJitAvailable(): boolean
 * - getGpuInfo(): GpuInfo
 * - mcLaunch(configJson: string): number
 * - mcGetStatus(): number
 * - mcIsRunning(): boolean
 * - mcForceExit(): void
 * - mcReadLog(): string
 * - registerXComponent(xComponentId: string): boolean
 * - inputSendCursorPos(x: number, y: number): void
 * - inputSendMouseButton(button: number, action: number, mods: number): void
 * - inputSendKey(key: number, scancode: number, action: number, mods: number): void
 * - inputSendChar(char: string): void
 * - inputSendScroll(x: number, y: number): void
 * - downloadEngineProbe(url: string): boolean
 */

#include <string>
#include <cstring>
#include <thread>
#include <cstdlib>
#include <napi/native_api.h>

#include "jvm_launcher.h"
#include "java_tool.h"
#include "elf_loader.h"
#include "input_bridge.h"
#include "log.h"

using namespace hmcl;

// Globals
static JvmLauncher *g_launcher = nullptr;
static std::thread *g_gameThread = nullptr;
static std::string g_filesDir;

// Helper: Convert napi_value to std::string
static std::string napiGetString(napi_env env, napi_value value) {
    size_t len = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    if (len == 0) return "";
    
    char *buf = new char[len + 1];
    napi_get_value_string_utf8(env, value, buf, len + 1, &len);
    buf[len] = '\0';
    std::string result(buf);
    delete[] buf;
    return result;
}

// Helper: Create napi string
static napi_value napiCreateString(napi_env env, const std::string &str) {
    napi_value result;
    napi_create_string_utf8(env, str.c_str(), str.length(), &result);
    return result;
}

// Helper: Create napi int32
static napi_value napiCreateInt32(napi_env env, int32_t val) {
    napi_value result;
    napi_create_int32(env, val, &result);
    return result;
}

// Helper: Create napi boolean
static napi_value napiCreateBool(napi_env env, bool val) {
    napi_value result;
    napi_get_boolean(env, val, &result);
    return result;
}

// ============================================================
// NAPI: jvmInit
// ============================================================
static napi_value JvmInit(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        return napiCreateBool(env, false);
    }
    
    std::string javaHome = napiGetString(env, args[0]);
    
    if (!g_launcher) {
        g_launcher = new JvmLauncher();
    }
    
    // Initialize ELF loader for JIT
    getElfLoader().initialize();
    
    bool result = g_launcher->initRuntime(javaHome);
    return napiCreateBool(env, result);
}

// ============================================================
// NAPI: jvmCheckJitAvailable
// ============================================================
static napi_value JvmCheckJitAvailable(napi_env env, napi_callback_info info) {
    bool available = getElfLoader().isJitAvailable();
    return napiCreateBool(env, available);
}

// ============================================================
// NAPI: getGpuInfo
// ============================================================
static napi_value GetGpuInfo(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_create_object(env, &result);
    
    if (!g_launcher) {
        g_launcher = new JvmLauncher();
    }
    
    GpuInfo gpuInfo = g_launcher->getGpuInfo();
    
    napi_value name;
    napi_create_string_utf8(env, gpuInfo.name.c_str(), gpuInfo.name.length(), &name);
    napi_set_named_property(env, result, "name", name);
    
    napi_value vendor;
    napi_create_string_utf8(env, gpuInfo.vendor.c_str(), gpuInfo.vendor.length(), &vendor);
    napi_set_named_property(env, result, "vendor", vendor);
    
    napi_value version;
    napi_create_string_utf8(env, gpuInfo.version.c_str(), gpuInfo.version.length(), &version);
    napi_set_named_property(env, result, "version", version);
    
    napi_value glVersion;
    napi_create_string_utf8(env, gpuInfo.glVersion.c_str(), gpuInfo.glVersion.length(), &glVersion);
    napi_set_named_property(env, result, "glVersion", glVersion);
    
    napi_value supportsVulkan;
    napi_get_boolean(env, gpuInfo.supportsVulkan, &supportsVulkan);
    napi_set_named_property(env, result, "supportsVulkan", supportsVulkan);
    
    return result;
}

// ============================================================
// NAPI: mcLaunch
// ============================================================
// Simple JSON parser helpers for flat objects
static std::string jsonGetString(const std::string &json, const std::string &key) {
    std::string search = "\"" + key + "\":\"";
    size_t pos = json.find(search);
    if (pos == std::string::npos) return "";
    pos += search.length();
    std::string result;
    while (pos < json.length() && json[pos] != '"') {
        if (json[pos] == '\\' && pos + 1 < json.length()) {
            pos++;
            if (json[pos] == 'n') result += '\n';
            else if (json[pos] == 't') result += '\t';
            else if (json[pos] == 'r') result += '\r';
            else result += json[pos];
        } else {
            result += json[pos];
        }
        pos++;
    }
    return result;
}

static int jsonGetInt(const std::string &json, const std::string &key, int def) {
    std::string search = "\"" + key + "\":";
    size_t pos = json.find(search);
    if (pos == std::string::npos) return def;
    pos += search.length();
    // Skip whitespace and optional negative sign
    while (pos < json.length() && json[pos] == ' ') pos++;
    bool neg = false;
    if (pos < json.length() && json[pos] == '-') { neg = true; pos++; }
    int val = 0;
    while (pos < json.length() && json[pos] >= '0' && json[pos] <= '9') {
        val = val * 10 + (json[pos] - '0');
        pos++;
    }
    return neg ? -val : val;
}

static bool jsonGetBool(const std::string &json, const std::string &key, bool def) {
    std::string search = "\"" + key + "\":";
    size_t pos = json.find(search);
    if (pos == std::string::npos) return def;
    pos += search.length();
    return json.compare(pos, 4, "true") == 0;
}

static std::vector<std::string> jsonGetStringArray(const std::string &json, const std::string &key) {
    std::vector<std::string> result;
    std::string search = "\"" + key + "\":[";
    size_t pos = json.find(search);
    if (pos == std::string::npos) return result;
    pos += search.length();
    while (pos < json.length() && json[pos] != ']') {
        // Skip non-quote chars (whitespace, commas)
        if (json[pos] == '"') {
            pos++;
            std::string val;
            while (pos < json.length() && json[pos] != '"') {
                if (json[pos] == '\\' && pos + 1 < json.length()) {
                    pos++;
                    if (json[pos] == 'n') val += '\n';
                    else val += json[pos];
                } else {
                    val += json[pos];
                }
                pos++;
            }
            result.push_back(val);
        }
        pos++;
    }
    return result;
}

static napi_value McLaunch(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1 || !g_launcher) {
        return napiCreateInt32(env, -1);
    }
    
    std::string configJson = napiGetString(env, args[0]);
    logInfo("NAPI", "mcLaunch called, JSON length: " + std::to_string(configJson.length()));
    
    // Parse the JSON config into JvmOptions
    JvmOptions opts;
    opts.javaHome     = jsonGetString(configJson, "javaHome");
    opts.gameDir      = jsonGetString(configJson, "gameDir");
    opts.mcDir        = jsonGetString(configJson, "mcDir");
    opts.filesDir     = jsonGetString(configJson, "filesDir");
    opts.assetsDir    = jsonGetString(configJson, "assetsDir");
    opts.mainClass    = jsonGetString(configJson, "mainClass");
    opts.minMemory    = jsonGetInt(configJson, "minMemory", 512);
    opts.maxMemory    = jsonGetInt(configJson, "maxMemory", 1024);
    opts.isForge      = jsonGetBool(configJson, "isForge", false);
    opts.isFabric     = jsonGetBool(configJson, "isFabric", false);
    opts.jitEnabled   = jsonGetBool(configJson, "jitEnabled", true);
    
    // Parse arrays
    opts.classpath    = jsonGetStringArray(configJson, "classpath");
    opts.mcArgs       = jsonGetStringArray(configJson, "mcArgs");
    
    // Fallbacks
    if (opts.javaHome.empty()) {
        opts.javaHome = g_filesDir + "/jdk_runtimes/jdk17";
    }
    if (opts.filesDir.empty()) {
        opts.filesDir = g_filesDir;
    }
    if (opts.gameDir.empty()) {
        opts.gameDir = g_filesDir + "/minecraft";
    }
    
    logInfo("NAPI", "Parsed config: javaHome=" + opts.javaHome + " mainClass=" + opts.mainClass
        + " mem=" + std::to_string(opts.minMemory) + "/" + std::to_string(opts.maxMemory)
        + " cp_entries=" + std::to_string(opts.classpath.size())
        + " mcArgs=" + std::to_string(opts.mcArgs.size()));
    
    // Launch on a separate thread
    if (g_gameThread && g_gameThread->joinable()) {
        g_gameThread->join();
        delete g_gameThread;
    }
    
    g_gameThread = new std::thread([opts]() {
        if (g_launcher) {
            g_launcher->launch(opts);
        }
    });
    
    return napiCreateInt32(env, 0);
}

// ============================================================
// NAPI: mcGetStatus
// ============================================================
static napi_value McGetStatus(napi_env env, napi_callback_info info) {
    if (!g_launcher) {
        return napiCreateInt32(env, 0);  // IDLE
    }
    return napiCreateInt32(env, static_cast<int32_t>(g_launcher->getStatus()));
}

// ============================================================
// NAPI: mcIsRunning
// ============================================================
static napi_value McIsRunning(napi_env env, napi_callback_info info) {
    if (!g_launcher) {
        return napiCreateBool(env, false);
    }
    return napiCreateBool(env, g_launcher->isRunning());
}

// ============================================================
// NAPI: mcForceExit
// ============================================================
static napi_value McForceExit(napi_env env, napi_callback_info info) {
    if (g_launcher) {
        g_launcher->forceExit();
    }
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// ============================================================
// NAPI: mcReadLog
// ============================================================
static napi_value McReadLog(napi_env env, napi_callback_info info) {
    if (!g_launcher) {
        napi_value empty;
        napi_create_string_utf8(env, "", 0, &empty);
        return empty;
    }
    return napiCreateString(env, g_launcher->readLog());
}

// ============================================================
// NAPI: setFilesDir
// ============================================================
static napi_value SetFilesDir(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc >= 1) {
        g_filesDir = napiGetString(env, args[0]);
    }
    
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// ============================================================
// NAPI: registerXComponent
// ============================================================
static std::string g_xComponentId;

static napi_value RegisterXComponent(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc >= 1) {
        g_xComponentId = napiGetString(env, args[0]);
        // Set environment variable for GLFW/LWJGL shim to discover the surface.
        // AMCL's GLFW stub reads this env var to call OH_NativeWindow_CreateNativeWindowFromSurfaceId().
        setenv("AMCL_SURFACE_ID", g_xComponentId.c_str(), 1);
        logInfo("NAPI", "XComponent registered via env AMCL_SURFACE_ID: " + g_xComponentId);
        return napiCreateBool(env, true);
    }
    
    return napiCreateBool(env, false);
}

// ============================================================
// NAPI: inputSendCursorPos
// ============================================================
static napi_value InputSendCursorPos(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc >= 2) {
        double x, y;
        napi_get_value_double(env, args[0], &x);
        napi_get_value_double(env, args[1], &y);
        InputBridge::getInstance().onCursorPos(x, y);
    }
    
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// ============================================================
// NAPI: inputSendMouseButton
// ============================================================
static napi_value InputSendMouseButton(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc >= 3) {
        int32_t button, action, mods;
        napi_get_value_int32(env, args[0], &button);
        napi_get_value_int32(env, args[1], &action);
        napi_get_value_int32(env, args[2], &mods);
        InputBridge::getInstance().onMouseButton(button, action, mods);
    }
    
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// ============================================================
// NAPI: inputSendKey
// ============================================================
static napi_value InputSendKey(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc >= 4) {
        int32_t key, scancode, action, mods;
        napi_get_value_int32(env, args[0], &key);
        napi_get_value_int32(env, args[1], &scancode);
        napi_get_value_int32(env, args[2], &action);
        napi_get_value_int32(env, args[3], &mods);
        InputBridge::getInstance().onKey(key, scancode, action, mods);
    }
    
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// ============================================================
// NAPI: inputSendScroll
// ============================================================
static napi_value InputSendScroll(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc >= 2) {
        double x, y;
        napi_get_value_double(env, args[0], &x);
        napi_get_value_double(env, args[1], &y);
        InputBridge::getInstance().onScroll(x, y);
    }
    
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// ============================================================
// Module Registration
// ============================================================
// ============================================================
// NAPI: runJavaProcessor
// 在 fork 出的独立子进程里运行一个 Java 主类（干净 classpath）。
// 供 Forge / NeoForge 安装期执行 install_profile 的 processors。
// 签名：runJavaProcessor(javaHome, classpath, mainClass, args[], workDir, logFile, xmxMb): Promise<number>
// ============================================================
namespace {

struct ProcessorJob {
    std::string javaHome;
    std::string classpath;
    std::string mainClass;
    std::vector<std::string> args;
    std::string workDir;
    std::string logFile;
    int xmxMb = 2048;
    int result = -1;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
};

void ProcessorExecute(napi_env env, void *data) {
    ProcessorJob *job = (ProcessorJob *) data;
    job->result = runJavaTool(job->javaHome, job->classpath, job->mainClass,
                              job->args, job->workDir, job->logFile, job->xmxMb);
}

void ProcessorComplete(napi_env env, napi_status status, void *data) {
    ProcessorJob *job = (ProcessorJob *) data;
    napi_value result;
    napi_create_int32(env, job->result, &result);
    if (job->deferred) {
        napi_resolve_deferred(env, job->deferred, result);
    }
    napi_delete_async_work(env, job->work);
    delete job;
}

} // namespace

static napi_value RunJavaProcessor(napi_env env, napi_callback_info info) {
    size_t argc = 7;
    napi_value args[7];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    ProcessorJob *job = new ProcessorJob();
    if (argc >= 7) {
        job->javaHome = napiGetString(env, args[0]);
        job->classpath = napiGetString(env, args[1]);
        job->mainClass = napiGetString(env, args[2]);
        bool isArray = false;
        napi_is_array(env, args[3], &isArray);
        if (isArray) {
            uint32_t n = 0;
            napi_get_array_length(env, args[3], &n);
            for (uint32_t i = 0; i < n; i++) {
                napi_value el;
                if (napi_get_element(env, args[3], i, &el) == napi_ok) {
                    job->args.push_back(napiGetString(env, el));
                }
            }
        }
        job->workDir = napiGetString(env, args[4]);
        job->logFile = napiGetString(env, args[5]);
        int32_t xmx = 2048;
        napi_get_value_int32(env, args[6], &xmx);
        job->xmxMb = xmx;
    }
    if (job->xmxMb < 512) job->xmxMb = 512;
    if (job->xmxMb > 8192) job->xmxMb = 8192;

    logInfo("NAPI", "runJavaProcessor: main=" + job->mainClass + " jdk=" + job->javaHome
        + " args=" + std::to_string(job->args.size()));

    napi_value promise;
    napi_create_promise(env, &job->deferred, &promise);
    napi_value resourceName;
    napi_create_string_utf8(env, "runJavaProcessor", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, ProcessorExecute, ProcessorComplete, job, &job->work);
    napi_queue_async_work(env, job->work);
    return promise;
}

static napi_value Init(napi_env env, napi_value exports) {
    logInfo("NAPI", "HMCL Native Bridge initializing...");
    
    // JVM
    napi_value fn_jvmInit;
    napi_create_function(env, "jvmInit", NAPI_AUTO_LENGTH, JvmInit, nullptr, &fn_jvmInit);
    napi_set_named_property(env, exports, "jvmInit", fn_jvmInit);
    
    napi_value fn_jvmCheckJit;
    napi_create_function(env, "jvmCheckJitAvailable", NAPI_AUTO_LENGTH, JvmCheckJitAvailable, nullptr, &fn_jvmCheckJit);
    napi_set_named_property(env, exports, "jvmCheckJitAvailable", fn_jvmCheckJit);
    
    napi_value fn_getGpuInfo;
    napi_create_function(env, "getGpuInfo", NAPI_AUTO_LENGTH, GetGpuInfo, nullptr, &fn_getGpuInfo);
    napi_set_named_property(env, exports, "getGpuInfo", fn_getGpuInfo);
    
    // Minecraft Launch
    napi_value fn_mcLaunch;
    napi_create_function(env, "mcLaunch", NAPI_AUTO_LENGTH, McLaunch, nullptr, &fn_mcLaunch);
    napi_set_named_property(env, exports, "mcLaunch", fn_mcLaunch);
    
    napi_value fn_mcGetStatus;
    napi_create_function(env, "mcGetStatus", NAPI_AUTO_LENGTH, McGetStatus, nullptr, &fn_mcGetStatus);
    napi_set_named_property(env, exports, "mcGetStatus", fn_mcGetStatus);
    
    napi_value fn_mcIsRunning;
    napi_create_function(env, "mcIsRunning", NAPI_AUTO_LENGTH, McIsRunning, nullptr, &fn_mcIsRunning);
    napi_set_named_property(env, exports, "mcIsRunning", fn_mcIsRunning);
    
    napi_value fn_mcForceExit;
    napi_create_function(env, "mcForceExit", NAPI_AUTO_LENGTH, McForceExit, nullptr, &fn_mcForceExit);
    napi_set_named_property(env, exports, "mcForceExit", fn_mcForceExit);
    
    napi_value fn_mcReadLog;
    napi_create_function(env, "mcReadLog", NAPI_AUTO_LENGTH, McReadLog, nullptr, &fn_mcReadLog);
    napi_set_named_property(env, exports, "mcReadLog", fn_mcReadLog);
    
    // Setup
    napi_value fn_setFilesDir;
    napi_create_function(env, "setFilesDir", NAPI_AUTO_LENGTH, SetFilesDir, nullptr, &fn_setFilesDir);
    napi_set_named_property(env, exports, "setFilesDir", fn_setFilesDir);
    
    napi_value fn_registerXComponent;
    napi_create_function(env, "registerXComponent", NAPI_AUTO_LENGTH, RegisterXComponent, nullptr, &fn_registerXComponent);
    napi_set_named_property(env, exports, "registerXComponent", fn_registerXComponent);
    
    // Input
    napi_value fn_inputCursorPos;
    napi_create_function(env, "inputSendCursorPos", NAPI_AUTO_LENGTH, InputSendCursorPos, nullptr, &fn_inputCursorPos);
    napi_set_named_property(env, exports, "inputSendCursorPos", fn_inputCursorPos);
    
    napi_value fn_inputMouseButton;
    napi_create_function(env, "inputSendMouseButton", NAPI_AUTO_LENGTH, InputSendMouseButton, nullptr, &fn_inputMouseButton);
    napi_set_named_property(env, exports, "inputSendMouseButton", fn_inputMouseButton);
    
    napi_value fn_inputKey;
    napi_create_function(env, "inputSendKey", NAPI_AUTO_LENGTH, InputSendKey, nullptr, &fn_inputKey);
    napi_set_named_property(env, exports, "inputSendKey", fn_inputKey);
    
    napi_value fn_inputScroll;
    napi_create_function(env, "inputSendScroll", NAPI_AUTO_LENGTH, InputSendScroll, nullptr, &fn_inputScroll);
    napi_set_named_property(env, exports, "inputSendScroll", fn_inputScroll);
    
    // Forge / NeoForge processors
    napi_value fn_runJavaProcessor;
    napi_create_function(env, "runJavaProcessor", NAPI_AUTO_LENGTH, RunJavaProcessor, nullptr, &fn_runJavaProcessor);
    napi_set_named_property(env, exports, "runJavaProcessor", fn_runJavaProcessor);
    
    logInfo("NAPI", "HMCL Native Bridge initialized successfully");
    return exports;
}

EXTERN_C_START
static napi_module hmclNativeModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "hmcl_native",
    .nm_priv = nullptr,
    .reserved = {0}
};

extern "C" __attribute__((constructor)) void RegisterHmclNativeModule() {
    napi_module_register(&hmclNativeModule);
    hmcl::logInfo("NAPI", "HMCL native module registered");
}
EXTERN_C_END
