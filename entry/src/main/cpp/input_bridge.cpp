/**
 * HMCL Native Bridge - Input Bridge Implementation
 */

#include "input_bridge.h"
#include "log.h"

#include <thread>
#include <chrono>

namespace hmcl {

InputBridge& InputBridge::getInstance() {
    static InputBridge instance;
    return instance;
}

void InputBridge::onCursorPos(double x, double y) {
    std::lock_guard<std::mutex> lock(m_mutex);
    InputEvent evt;
    evt.type = InputEventType::CURSOR_POS;
    evt.x = x;
    evt.y = y;
    m_eventQueue.push(evt);
}

void InputBridge::onMouseButton(int button, int action, int mods) {
    std::lock_guard<std::mutex> lock(m_mutex);
    InputEvent evt;
    evt.type = InputEventType::MOUSE_BUTTON;
    evt.button = button;
    evt.action = action;
    evt.mods = mods;
    m_eventQueue.push(evt);
}

void InputBridge::onKey(int key, int scancode, int action, int mods) {
    std::lock_guard<std::mutex> lock(m_mutex);
    InputEvent evt;
    evt.type = InputEventType::KEY;
    evt.key = key;
    evt.scancode = scancode;
    evt.action = action;
    evt.mods = mods;
    m_eventQueue.push(evt);
}

void InputBridge::onChar(char c) {
    std::lock_guard<std::mutex> lock(m_mutex);
    InputEvent evt;
    evt.type = InputEventType::CHAR;
    evt.character = c;
    m_eventQueue.push(evt);
}

void InputBridge::onCharMods(char c, int mods) {
    std::lock_guard<std::mutex> lock(m_mutex);
    InputEvent evt;
    evt.type = InputEventType::CHAR_MODS;
    evt.character = c;
    evt.mods = mods;
    m_eventQueue.push(evt);
}

void InputBridge::onScroll(double x, double y) {
    std::lock_guard<std::mutex> lock(m_mutex);
    InputEvent evt;
    evt.type = InputEventType::SCROLL;
    evt.scrollX = x;
    evt.scrollY = y;
    m_eventQueue.push(evt);
}

void InputBridge::onWindowSize(int width, int height) {
    std::lock_guard<std::mutex> lock(m_mutex);
    InputEvent evt;
    evt.type = InputEventType::WINDOW_SIZE;
    evt.width = width;
    evt.height = height;
    m_eventQueue.push(evt);
}

void InputBridge::setJniEnv(JNIEnv *env) {
    m_env = env;
    if (m_env) {
        logInfo("InputBridge", "JNI env set, initializing CallbackBridge methods");
        ensureJniMethods();
    }
}

void InputBridge::setGrabbing(bool grabbed) {
    m_grabbing = grabbed;
}

void InputBridge::ensureJniMethods() {
    if (!m_env) return;
    
    jclass localClass = m_env->FindClass("org/lwjgl/glfw/CallbackBridge");
    if (!localClass) {
        if (m_env->ExceptionCheck()) m_env->ExceptionClear();
        logWarn("InputBridge", "LWJGL CallbackBridge not found (LWJGL may not be loaded yet)");
        return;
    }
    
    m_callbackBridgeClass = (jclass)m_env->NewGlobalRef(localClass);
    
    m_sendCursorPos = m_env->GetStaticMethodID(m_callbackBridgeClass, "nativeSendCursorPos", "(DD)V");
    m_sendMouseButton = m_env->GetStaticMethodID(m_callbackBridgeClass, "nativeSendMouseButton", "(III)V");
    m_sendKey = m_env->GetStaticMethodID(m_callbackBridgeClass, "nativeSendKey", "(IIII)V");
    m_sendChar = m_env->GetStaticMethodID(m_callbackBridgeClass, "nativeSendChar", "(C)V");
    m_sendCharMods = m_env->GetStaticMethodID(m_callbackBridgeClass, "nativeSendCharMods", "(CI)V");
    m_sendScroll = m_env->GetStaticMethodID(m_callbackBridgeClass, "nativeSendScroll", "(DD)V");
    m_sendScreenSize = m_env->GetStaticMethodID(m_callbackBridgeClass, "nativeSendScreenSize", "(II)V");
    
    if (m_env->ExceptionCheck()) {
        m_env->ExceptionClear();
        logWarn("InputBridge", "Some CallbackBridge methods not found (LWJGL version mismatch)");
    } else {
        logInfo("InputBridge", "All LWJGL CallbackBridge methods resolved");
    }
}

void InputBridge::sendToLwjgl(const InputEvent &evt) {
    if (!m_env || !m_callbackBridgeClass) return;
    
    switch (evt.type) {
        case InputEventType::CURSOR_POS:
            if (m_sendCursorPos)
                m_env->CallStaticVoidMethod(m_callbackBridgeClass, m_sendCursorPos, evt.x, evt.y);
            break;
        case InputEventType::MOUSE_BUTTON:
            if (m_sendMouseButton)
                m_env->CallStaticVoidMethod(m_callbackBridgeClass, m_sendMouseButton, evt.button, evt.action, evt.mods);
            break;
        case InputEventType::KEY:
            if (m_sendKey)
                m_env->CallStaticVoidMethod(m_callbackBridgeClass, m_sendKey, evt.key, evt.scancode, evt.action, evt.mods);
            break;
        case InputEventType::CHAR:
            if (m_sendChar)
                m_env->CallStaticVoidMethod(m_callbackBridgeClass, m_sendChar, evt.character);
            break;
        case InputEventType::CHAR_MODS:
            if (m_sendCharMods)
                m_env->CallStaticVoidMethod(m_callbackBridgeClass, m_sendCharMods, evt.character, evt.mods);
            break;
        case InputEventType::SCROLL:
            if (m_sendScroll)
                m_env->CallStaticVoidMethod(m_callbackBridgeClass, m_sendScroll, evt.scrollX, evt.scrollY);
            break;
        case InputEventType::WINDOW_SIZE:
            if (m_sendScreenSize)
                m_env->CallStaticVoidMethod(m_callbackBridgeClass, m_sendScreenSize, evt.width, evt.height);
            break;
    }
    
    if (m_env->ExceptionCheck()) {
        m_env->ExceptionClear();
    }
}

void InputBridge::processEvents() {
    std::queue<InputEvent> events;
    
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        std::swap(events, m_eventQueue);
    }
    
    while (!events.empty()) {
        InputEvent evt = events.front();
        events.pop();
        sendToLwjgl(evt);
    }
}

} // namespace hmcl
