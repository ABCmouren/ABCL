/**
 * HMCL Native Bridge - Logging Implementation
 */

#include "log.h"
#include <cstdio>
#include <iostream>

namespace hmcl {

void logDebug(const std::string &tag, const std::string &msg) {
    HMCL_LOG_DEBUG(LOG_DOMAIN, "%{public}s: %{public}s", tag.c_str(), msg.c_str());
}

void logInfo(const std::string &tag, const std::string &msg) {
    HMCL_LOG_INFO(LOG_DOMAIN, "%{public}s: %{public}s", tag.c_str(), msg.c_str());
}

void logWarn(const std::string &tag, const std::string &msg) {
    HMCL_LOG_WARN(LOG_DOMAIN, "%{public}s: %{public}s", tag.c_str(), msg.c_str());
}

void logError(const std::string &tag, const std::string &msg) {
    HMCL_LOG_ERROR(LOG_DOMAIN, "%{public}s: %{public}s", tag.c_str(), msg.c_str());
    std::cerr << "[" << tag << "] " << msg << std::endl;
}

} // namespace hmcl
