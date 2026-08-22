// sftp_helper.c — minimal libssh2 SFTP bridge for photo-export.
// Exposes a narrow streaming API to Swift so photo-export can push an in-memory
// PhotoKit buffer to sophrosyne over SFTP (no temp file on disk), and check
// remote existence/size for skipping. Uses the existing no-passphrase key
// (~/.ssh/id_photo_rsync), which sophrosyne's rrsync-photos wrapper confines to
// /dragon/media/photos/.
//
// Threading model: single-threaded CLI (one session held open for the run).
#include <netdb.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <libssh2.h>
#include <libssh2_sftp.h>
#include "sftp_helper.h"

// Opaque session handle — defined here, allocated by photo_sftp_open, free via
// photo_sftp_close. Swift only sees the pointer.
struct PhotoSftp {
  int sock;
  LIBSSH2_SESSION *session;
  LIBSSH2_SFTP *sftp;
};

static int die(const char *msg) {
  fprintf(stderr, "photo-export: sftp: %s\n", msg);
  return 1;
}

// Open SSH+SFTP session to host/port as user, authenticating with keyfile.
// Allocates *out (caller releases with photo_sftp_close). Returns 0 on success.
int photo_sftp_open(PhotoSftp **out, const char *host, int port,
                    const char *user, const char *keyfile) {
  if (out == NULL || host == NULL || user == NULL || keyfile == NULL) return 1;
  *out = NULL;

  struct addrinfo hints, *res = NULL;
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  char portstr[16];
  snprintf(portstr, sizeof(portstr), "%d", port);
  if (getaddrinfo(host, portstr, &hints, &res) != 0) return die("resolve failed");

  int sock = -1;
  for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
    sock = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
    if (sock < 0) continue;
    if (connect(sock, ai->ai_addr, ai->ai_addrlen) == 0) break;
    close(sock);
    sock = -1;
  }
  freeaddrinfo(res);
  if (sock < 0) return die("connect failed");

  LIBSSH2_SESSION *session = libssh2_session_init();
  if (session == NULL) { close(sock); return die("session_init failed"); }
  libssh2_session_set_blocking(session, 1);
  libssh2_session_set_timeout(session, 60000);
  if (libssh2_session_handshake(session, sock) != 0) {
    close(sock);
    return die("SSH handshake failed");
  }
  if (libssh2_userauth_publickey_fromfile(session, user, NULL, keyfile, NULL) != 0) {
    char *err = NULL;
    libssh2_session_last_error(session, &err, NULL, 0);
    fprintf(stderr, "photo-export: sftp: key auth failed (%s)\n", err ? err : "?");
    libssh2_session_disconnect(session, "auth failed");
    libssh2_session_free(session);
    close(sock);
    return die("key auth failed");
  }
  LIBSSH2_SFTP *sftp = libssh2_sftp_init(session);
  if (sftp == NULL) {
    fprintf(stderr, "photo-export: sftp: sftp_init failed (code %d) — key restricted to sftp?\n",
            libssh2_session_last_errno(session));
    libssh2_session_disconnect(session, "no sftp");
    libssh2_session_free(session);
    close(sock);
    return die("sftp_init failed");
  }

  *out = malloc(sizeof(PhotoSftp));
  if (*out == NULL) return 1;
  (*out)->sock = sock;
  (*out)->session = session;
  (*out)->sftp = sftp;
  return 0;
}

// Stat remote path (relative to the session's confined dir).
// Returns file size (>=0) if present, 0 if absent/unreadable, -1 on error.
int64_t photo_sftp_stat(PhotoSftp *s, const char *remote_path) {
  if (s == NULL || s->sftp == NULL) return -1;
  LIBSSH2_SFTP_ATTRIBUTES attrs;
  int rc = libssh2_sftp_stat(s->sftp, remote_path, &attrs);
  if (rc == 0) return (int64_t)attrs.filesize;
  // absent/unreadable → -1 (Swift's skip-check uses >0 to mean "present", so
  // a missing file is never treated as present).
  return -1;
}

// Stream-upload memory to remote_path via reader callback. 0 success, 1 failure.
int photo_sftp_put(PhotoSftp *s, const char *remote_path, PhotoReader reader, void *ctx) {
  if (s == NULL || s->sftp == NULL || reader == NULL) return 1;
  LIBSSH2_SFTP_HANDLE *h = libssh2_sftp_open(s->sftp, remote_path,
                                             LIBSSH2_FXF_CREAT | LIBSSH2_FXF_WRITE,
                                             LIBSSH2_SFTP_S_IRUSR | LIBSSH2_SFTP_S_IWUSR |
                                             LIBSSH2_SFTP_S_IRGRP | LIBSSH2_SFTP_S_IROTH);
  if (h == NULL) {
    long code = libssh2_sftp_last_error(s->sftp);
    fprintf(stderr, "photo-export: sftp: open-for-write failed (sftp status %ld)\n", code);
    return 1;
  }

  unsigned char buf[128 * 1024];
  int rc = 0;
  for (;;) {
    long n = reader(ctx, buf, (long)sizeof(buf));
    if (n < 0) { rc = 1; break; }
    if (n == 0) break;
    long off = 0;
    while (off < n) {
      ssize_t w = libssh2_sftp_write(h, (const char *)(buf + off), (size_t)(n - off));
      if (w < 0) { rc = 1; break; }
      off += w;
    }
    if (rc) break;
  }
  libssh2_sftp_close(h);
  return rc;
}

// ---- Chunked in-memory upload for LARGE assets (videos) ----
// For photos we use requestImageDataAndOrientation (single in-memory Data) and
// stream via photo_sftp_put's reader callback. Videos arrive as NSData chunks
// via PHAssetResourceManager.requestData(dataReceivedHandler:). We open the
// remote file once (photo_sftp_put_begin), stream each chunk
// (photo_sftp_put_chunk), then close (photo_sftp_put_close). No temp file, no
// SSD write — chunk data goes straight to the SFTP socket.
// Open a remote file for write, returning the raw LIBSSH2_SFTP_HANDLE pointer.
// Must NOT be cast through an int — the handle is a 64-bit pointer and would be
// truncated, corrupting it (→ SIGSEGV inside libssh2_sftp_write).
void *photo_sftp_put_begin(PhotoSftp *s, const char *remote_path) {
  if (s == NULL || s->sftp == NULL || remote_path == NULL) return NULL;
  LIBSSH2_SFTP_HANDLE *h = libssh2_sftp_open(s->sftp, remote_path,
                                             LIBSSH2_FXF_CREAT | LIBSSH2_FXF_WRITE,
                                             LIBSSH2_SFTP_S_IRUSR | LIBSSH2_SFTP_S_IWUSR |
                                             LIBSSH2_SFTP_S_IRGRP | LIBSSH2_SFTP_S_IROTH);
  if (h == NULL) return NULL;
  return h;
}

// Append one chunk at the current position. `handle` is the pointer from
// photo_sftp_put_begin. Returns 0 on success, 1 on failure.
int photo_sftp_put_chunk(void *handle, const unsigned char *data, size_t count) {
  LIBSSH2_SFTP_HANDLE *h = (LIBSSH2_SFTP_HANDLE *)handle;
  if (h == NULL) return 1;
  size_t off = 0;
  while (off < count) {
    ssize_t w = libssh2_sftp_write(h, (const char *)(data + off), count - off);
    if (w < 0) return 1;
    off += (size_t)w;
  }
  return 0;
}

void photo_sftp_put_end(void *handle) {
  LIBSSH2_SFTP_HANDLE *h = (LIBSSH2_SFTP_HANDLE *)handle;
  if (h != NULL) { libssh2_sftp_close(h); }
}

// Ensure a remote directory exists (idempotent). 0 on success, 1 on failure.
int photo_sftp_mkdir(PhotoSftp *s, const char *remote_dir) {
  if (s == NULL || s->sftp == NULL || remote_dir == NULL) return 0;
  int rc = libssh2_sftp_mkdir(s->sftp, remote_dir,
                              LIBSSH2_SFTP_S_IRWXU | LIBSSH2_SFTP_S_IRWXG |
                              LIBSSH2_SFTP_S_IROTH | LIBSSH2_SFTP_S_IXOTH);
  if (rc == 0) return 0;
  long code = libssh2_sftp_last_error(s->sftp);
  if (code == LIBSSH2_FX_FILE_ALREADY_EXISTS) return 0;
  // Treat "already exists/failure" as present (idempotent) rather than error.
  LIBSSH2_SFTP_ATTRIBUTES attrs;
  if (libssh2_sftp_stat(s->sftp, remote_dir, &attrs) == 0) return 0;
  return (rc == 0) ? 0 : 1;
}

void photo_sftp_close(PhotoSftp *s) {
  if (s == NULL) return;
  if (s->sftp) { libssh2_sftp_shutdown(s->sftp); s->sftp = NULL; }
  if (s->session) {
    libssh2_session_disconnect(s->session, "done");
    libssh2_session_free(s->session);
    s->session = NULL;
  }
  if (s->sock >= 0) { close(s->sock); s->sock = -1; }
  free(s);
}
