#ifndef DIRKA_ENGINE_H
#define DIRKA_ENGINE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct dirka_client dirka_client;

/* Returns immutable, NUL-terminated UTF-8 data borrowed for the process
 * lifetime. No handle is required. Callers must not free or mutate it. */
const char *dirka_engine_metadata(void);
const char *dirka_engine_upstream_license(void);
const char *dirka_engine_dependency_licenses(void);

/* Length-delimited UTF-8 JSON (up to 4096 bytes), borrowed only for this call.
 * Returns NULL for malformed input or engine initialization failure. Relay
 * and bind validation run asynchronously. Call off the UI thread. */
dirka_client *dirka_client_start(const uint8_t *input, size_t length);

/* Copies a UTF-8 JSON {status,error} snapshot into a separate caller-owned
 * buffer. Returns bytes written without NUL or -1 on failure. Supply 8192
 * bytes. Poll until status "stopped" to observe completed cleanup. */
int32_t dirka_client_snapshot(const dirka_client *client, uint8_t *out, size_t capacity);

/* Requests asynchronous cancellation. Safe to repeat until destruction. */
void dirka_client_stop(dirka_client *client);

/* Consumes the handle exactly once and also requests cancellation. NULL is
 * a no-op. Suitable as a Dart native finalizer. */
void dirka_client_destroy(dirka_client *client);

/* Serialize all calls on a particular handle and never race destruction
 * with another call. Separate handles can be used independently. Functions
 * contain Rust unwinds. Process-aborting failures cannot be recovered. */

#ifdef __cplusplus
}
#endif

#endif
