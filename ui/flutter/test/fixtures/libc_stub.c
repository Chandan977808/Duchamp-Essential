// Test-only libc.so stand-in for the Linux test host.
//
// DolbyBackend looks malloc/free up through DynamicLibrary.open('libc.so'),
// which is Android-specific (glibc ships no dlopen-able libc.so). This stub
// is found first via LD_LIBRARY_PATH and simply forces its malloc/free
// references to bind against the real glibc already loaded in the process.
#include <stdlib.h>

void *(*const _stub_malloc_ptr)(size_t) = malloc;
void (*const _stub_free_ptr)(void *) = free;
