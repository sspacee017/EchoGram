#include "CompiledTelegramAPI.h"
#include <stddef.h>

#if __has_include("EchoGramGeneratedAPI.h")
#include "EchoGramGeneratedAPI.h"
#endif

int32_t EchoGramCompiledApiId(void) {
#ifdef ECHOGRAM_API_ID
    return ECHOGRAM_API_ID;
#else
    return 0;
#endif
}

const char *EchoGramCompiledApiHash(void) {
#ifdef ECHOGRAM_API_HASH
    return ECHOGRAM_API_HASH;
#else
    return NULL;
#endif
}
