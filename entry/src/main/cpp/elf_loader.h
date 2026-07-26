/**
 * HMCL Native Bridge - ELF Loader
 * 
 * Custom ELF loader that bypasses HarmonyOS MAP_XPM (no-write-exec) 
 * memory restriction. Required for HotSpot JIT to function properly.
 * 
 * HarmonyOS NEXT enforces a security policy where writable memory pages
 * cannot be made executable (no MAP_XPM). The JIT compiler needs to
 * write JIT-compiled code to memory then execute it, which violates
 * this policy. This loader uses platform-specific techniques to create
 * the necessary memory mappings.
 *
 * The approach:
 * 1. Load ELF binaries using modified mmap/mprotect flags
 * 2. Relay symbol resolution through a trampoline mechanism
 * 3. Provide dlopen/dlsym compatible interface for JVM loading
 */

#ifndef HMCL_ELF_LOADER_H
#define HMCL_ELF_LOADER_H

#include <string>
#include <functional>
#include <vector>

namespace hmcl {

// Callback type for symbol resolution
using SymbolCallback = std::function<void*(const char*)>;

/**
 * ELF Loader context
 * Manages the custom ELF loading environment
 */
class ElfLoader {
public:
    ElfLoader();
    ~ElfLoader();

    /**
     * Initialize the ELF loader
     * Must be called before any other operations
     */
    bool initialize();

    /**
     * Load a shared library with MAP_XPM bypass
     * @param path Absolute path to the .so file
     * @return Handle to the loaded library, or nullptr on failure
     */
    void* loadLibrary(const std::string &path);

    /**
     * Resolve a symbol from loaded libraries
     * @param handle Library handle from loadLibrary
     * @param symbol Symbol name to resolve
     * @return Function pointer, or nullptr on failure
     */
    void* resolveSymbol(void *handle, const char *symbol);

    /**
     * Close a loaded library
     */
    void closeLibrary(void *handle);

    /**
     * Check if JIT-compatible memory is available
     * @return true if JIT memory can be allocated
     */
    bool isJitAvailable();

    /**
     * Allocate JIT-compatible memory (writable + executable)
     * @param size Size in bytes
     * @return Pointer to allocated memory, or nullptr
     */
    void* allocateJitMemory(size_t size);

    /**
     * Free JIT-compatible memory
     */
    void freeJitMemory(void *ptr, size_t size);

private:
    bool m_initialized = false;
    void *m_jitHeap = nullptr;
    size_t m_jitHeapSize = 0;

    // Internal: try mmap with PROT_WRITE | PROT_EXEC
    void* tryMmapWx(size_t size);

    // Internal: try using memfd_create + sealing trick
    void* tryMemfdSeal(size_t size);

    // Internal: try /dev/shm approach (if available)
    void* tryDevShm(size_t size);
};

/**
 * Global singleton access
 */
ElfLoader& getElfLoader();

} // namespace hmcl

#endif // HMCL_ELF_LOADER_H
