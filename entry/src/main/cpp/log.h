/**
 * HMCL Native Bridge - Logging utility
 * Provides structured logging for the native layer
 */

#ifndef HMCL_LOG_H
#define HMCL_LOG_H

#include <string>
#include <hilog/log.h>

// Log domain for HMCL
#ifndef LOG_DOMAIN
#define LOG_DOMAIN 0x0001
#endif

#ifndef LOG_TAG
#define LOG_TAG "HMCL_NATIVE"
#endif

// Log levels
#define HMCL_LOG_DEBUG(...) OH_LOG_DEBUG(LOG_APP, __VA_ARGS__)
#define HMCL_LOG_INFO(...)  OH_LOG_INFO(LOG_APP, __VA_ARGS__)
#define HMCL_LOG_WARN(...)  OH_LOG_WARN(LOG_APP, __VA_ARGS__)
#define HMCL_LOG_ERROR(...) OH_LOG_ERROR(LOG_APP, __VA_ARGS__)
#define HMCL_LOG_FATAL(...) OH_LOG_FATAL(LOG_APP, __VA_ARGS__)

namespace hmcl {

// Convenience C++ wrappers
void logDebug(const std::string &tag, const std::string &msg);
void logInfo(const std::string &tag, const std::string &msg);
void logWarn(const std::string &tag, const std::string &msg);
void logError(const std::string &tag, const std::string &msg);

} // namespace hmcl

#endif // HMCL_LOG_H
