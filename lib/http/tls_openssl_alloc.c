#include "tls_openssl_alloc.h"

#include <stdlib.h>
#include <string.h>

void *ox_tls_alloc(size_t size) { return malloc(size); }

void *ox_tls_calloc(size_t nmemb, size_t size) { return calloc(nmemb, size); }

char *ox_tls_strdup(const char *s) { return strdup(s); }

void ox_tls_free(void *ptr) { free(ptr); }
