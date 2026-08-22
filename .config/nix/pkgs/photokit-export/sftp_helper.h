// sftp_helper.h — Swift-visible API for sftp_helper.c.
// Keeps libssh2's C types opaque behind a void* so Swift never sees libssh2
// headers. Swift imports this module (via a module map or -I + include) and
// calls the functions; only these signatures are exposed.
#ifndef PHOTO_SFTP_HELPER_H
#define PHOTO_SFTP_HELPER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque session handle (defined in sftp_helper.c).
typedef struct PhotoSftp PhotoSftp;

// Reader callback used by photo_sftp_put to stream in-memory bytes.
// Return bytes read (0 = EOF, -1 = error).
typedef long (*PhotoReader)(void *ctx, unsigned char *buf, long max);

// Open an SSH+SFTP session. Returns 0 on success; on success caller must call
// photo_sftp_close when done.
int photo_sftp_open(PhotoSftp **out, const char *host, int port,
                    const char *user, const char *keyfile);

// Stat a remote path (relative to the session's chroot dir).
// Returns file size (>=0) if present, 0 if absent, -1 on error.
int64_t photo_sftp_stat(PhotoSftp *s, const char *remote_path);

// Stream-upload via reader callback to remote_path. Returns 0 on success, 1 on failure.
int photo_sftp_put(PhotoSftp *s, const char *remote_path, PhotoReader reader, void *ctx);

// --- Chunked in-memory upload (for large video assets, no temp file) ---
// Open a remote file for write, returning an opaque handle pointer (Swift keeps it).
// The remote file handle is a 64-bit pointer on arm64, so it must NOT be squeezed
// through an `int` (truncation corrupts the handle → SIGSEGV in libssh2_sftp_write).
// Stream each inbound NSData chunk with photo_sftp_put_chunk, then photo_sftp_put_end.
void *photo_sftp_put_begin(PhotoSftp *s, const char *remote_path);
// Append one chunk. handle = the pointer returned by put_begin. 0 ok / 1 fail.
int photo_sftp_put_chunk(void *handle, const unsigned char *data, size_t count);
// Close the remote file opened by put_begin.
void photo_sftp_put_end(void *handle);

// Ensure a remote directory exists (idempotent). Returns 0 on success, 1 on failure.
int photo_sftp_mkdir(PhotoSftp *s, const char *remote_dir);

// Close and free the session.
void photo_sftp_close(PhotoSftp *s);

#ifdef __cplusplus
}
#endif

#endif
