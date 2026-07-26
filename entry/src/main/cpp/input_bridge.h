/**
 * HMCL Native Bridge - Input Bridge
 * 
 * Bridges touch/input events from ArkTS UI to the JVM/LWJGL layer.
 * Mirrors AMCL's inputBridge architecture.
 *
 * The input bridge:
 * 1. Receives touch events from ArkTS XComponent callbacks
 * 2. Translates them to mouse/keyboard events
 * 3. Forwards events to LWJGL via JNI CallbackBridge
 */

#ifndef HMCL_INPUT_BRIDGE_H
#define HMCL_INPUT_BRIDGE_H

#include <functional>
#include <mutex>
#include <queue>
#include <jni.h>

namespace hmcl {

// Input event types
enum class InputEventType {
    CURSOR_POS,
    MOUSE_BUTTON,
    KEY,
    CHAR,
    CHAR_MODS,
    SCROLL,
    WINDOW_SIZE
};

// Input event structure
struct InputEvent {
    InputEventType type;
    double x = 0;
    double y = 0;
    int button = 0;
    int action = 0;
    int mods = 0;
    int key = 0;
    int scancode = 0;
    char character = 0;
    double scrollX = 0;
    double scrollY = 0;
    int width = 0;
    int height = 0;
};

/**
 * Input Bridge singleton
 * Manages input event forwarding to LWJGL
 */
class InputBridge {
public:
    static InputBridge& getInstance();

    // Called from ArkTS via NAPI
    void onCursorPos(double x, double y);
    void onMouseButton(int button, int action, int mods);
    void onKey(int key, int scancode, int action, int mods);
    void onChar(char c);
    void onCharMods(char c, int mods);
    void onScroll(double x, double y);
    void onWindowSize(int width, int height);
    
    // Called from game thread to process events
    void processEvents();
    
    // Set JNI env and class references for LWJGL
    void setJniEnv(JNIEnv *env);
    void setGrabbing(bool grabbed);
    bool isGrabbing() const { return m_grabbing; }
    
    // Callback registration
    using ExitCallback = std::function<void()>;
    void setMcExitCallback(ExitCallback cb) { m_exitCb = cb; }

private:
    InputBridge() = default;
    ~InputBridge() = default;
    InputBridge(const InputBridge&) = delete;
    InputBridge& operator=(const InputBridge&) = delete;

    std::queue<InputEvent> m_eventQueue;
    std::mutex m_mutex;
    bool m_grabbing = false;
    JNIEnv *m_env = nullptr;
    
    // JNI references for LWJGL CallbackBridge
    jclass m_callbackBridgeClass = nullptr;
    jmethodID m_sendCursorPos = nullptr;
    jmethodID m_sendMouseButton = nullptr;
    jmethodID m_sendKey = nullptr;
    jmethodID m_sendChar = nullptr;
    jmethodID m_sendCharMods = nullptr;
    jmethodID m_sendScroll = nullptr;
    jmethodID m_sendScreenSize = nullptr;
    
    ExitCallback m_exitCb;
    
    void ensureJniMethods();
    void sendToLwjgl(const InputEvent &evt);
};

} // namespace hmcl

#endif // HMCL_INPUT_BRIDGE_H
