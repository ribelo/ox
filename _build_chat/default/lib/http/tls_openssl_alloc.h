#ifndef ETA_TLS_OPENSSL_ALLOC_H
#define ETA_TLS_OPENSSL_ALLOC_H

#include <stddef.h>

void *eta_tls_alloc(size_t size);
void *eta_tls_calloc(size_t nmemb, size_t size);
char *eta_tls_strdup(const char *s);
void eta_tls_free(void *ptr);

#endif
