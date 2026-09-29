#ifndef OX_TLS_OPENSSL_ALLOC_H
#define OX_TLS_OPENSSL_ALLOC_H

#include <stddef.h>

void *ox_tls_alloc(size_t size);
void *ox_tls_calloc(size_t nmemb, size_t size);
char *ox_tls_strdup(const char *s);
void ox_tls_free(void *ptr);

#endif
