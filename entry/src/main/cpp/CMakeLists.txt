# HMCL Native Bridge for HarmonyOS
# Builds the core JVM launcher and NAPI bridge for Minecraft Java Edition

cmake_minimum_required(VERSION 3.5)
project(hmcl_native LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ============================================================
# Fix library search path
# hvigor may use HMS toolchain (hmos.toolchain.cmake) for 
# HarmonyOS runtimeOS which only includes HMS native sysroot.
# The HMS sysroot lacks native_window and uv libraries.
# We explicitly add the OHOS native sysroot to ensure all
# required libraries are found.
# ============================================================
if(DEFINED ENV{OHOS_SDK_NATIVE})
  # OHOS_SDK_NATIVE is set by hvigor during build
  message(STATUS "OHOS_SDK_NATIVE: $ENV{OHOS_SDK_NATIVE}")
  list(APPEND CMAKE_FIND_ROOT_PATH "$ENV{OHOS_SDK_NATIVE}/sysroot")
endif()

# Find HarmonyOS Native APIs
# NOTE: Only hilog uses '.z' suffix in its library filename.
# native_window and uv do NOT use '.z' suffix.
find_library(hilog-lib hilog_ndk.z)

find_library(native-window-lib native_window)

find_library(uv-lib uv)

# NAPI runtime functions (napi_module_register, napi_create_function, etc.)
# Provided by the OHOS system runtime library. Must be linked explicitly.
find_library(ace-napi-lib ace_napi.z)

# Core native module
add_library(hmcl_native SHARED
    napi_init.cpp
    jvm_launcher.cpp
    elf_loader.cpp
    input_bridge.cpp
    log.cpp
)

# Add JNI include path from DevEco Studio's bundled JBR
# Priority: DEVECO_JAVA_HOME env > DEVECO_HOME env > OHOS_SDK_NATIVE parent > default fallback
if(DEFINED ENV{DEVECO_JAVA_HOME})
  set(JNI_INCLUDE_DIR "$ENV{DEVECO_JAVA_HOME}/include")
elseif(DEFINED ENV{DEVECO_HOME})
  # DEVECO_HOME points to DevEco Studio installation root
  set(JNI_INCLUDE_DIR "$ENV{DEVECO_HOME}/jbr/include")
elseif(DEFINED ENV{OHOS_SDK_NATIVE})
  # Try relative to OHOS SDK (DevEco Studio sets this during build)
  # OHOS_SDK_NATIVE = D:/HarmonyOS/DevEco Studio/sdk/default/openharmony/native
  # JBR is at D:/HarmonyOS/DevEco Studio/jbr
  # Need to go up 4 levels: native -> openharmony -> default -> sdk -> DevEco Studio
  get_filename_component(OHOS_SDK_PARENT "$ENV{OHOS_SDK_NATIVE}/../../../../" REALPATH)
  set(JNI_INCLUDE_DIR "${OHOS_SDK_PARENT}/jbr/include")
else()
  # Fallback: typical Windows DevEco Studio default path
  set(JNI_INCLUDE_DIR "D:/HarmonyOS/DevEco Studio/jbr/include")
endif()
message(STATUS "JNI_INCLUDE_DIR: ${JNI_INCLUDE_DIR}")

# Verify JNI headers exist
if(NOT EXISTS "${JNI_INCLUDE_DIR}/jni.h")
  message(WARNING "jni.h not found at ${JNI_INCLUDE_DIR}/jni.h")
  message(WARNING "Please set DEVECO_HOME or DEVECO_JAVA_HOME environment variable")
endif()

target_include_directories(hmcl_native PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${JNI_INCLUDE_DIR}
)

# Print library paths for debugging
message(STATUS "hilog-lib: ${hilog-lib}")
message(STATUS "native-window-lib: ${native-window-lib}")
message(STATUS "uv-lib: ${uv-lib}")
message(STATUS "ace-napi-lib: ${ace-napi-lib}")

target_link_libraries(hmcl_native
    ${hilog-lib}
    ${native-window-lib}
    ${uv-lib}
    ${ace-napi-lib}
    dl
    z
    pthread
)
