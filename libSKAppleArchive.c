//
//  libSKAppleArchive.c
//  AAFromScratch
//
//  Created by Snoolie Keffaber on 2024/03/18.
//

#include "libSKAppleArchive.h"
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/fcntl.h>

#define INCLUDE_SK_AA 1

#if INCLUDE_SK_AA

int aaFileStreamClose(struct SKAAByteStream_impl stream) {
  if (stream.fileDesc) {
    int fd = stream.fileDesc->fd;
    if (stream.fileDesc->automatic_close) {
      if (fd >= 0) {
        close(fd);
      }
    }
    free(stream.fileDesc);
  }
  return 0;
}

ssize_t aaFileStreamRead(SKAAByteStreamFileDesc fileDesc, void * buf, size_t nbyte) {
    printf("attempt read... (nbyte: %zu)\n",nbyte);
    if (fileDesc->reserved == 0) {
        return read(fileDesc->fd, buf, nbyte);
    }
    return -1;
}

ssize_t aaFileStreamWrite(struct SKAAByteStream_impl stream, void * buf, size_t nbyte) {
  if (stream.fileDesc->reserved == 0) {
    return write(stream.fileDesc->fd, buf, nbyte);
  }
  return -1;
}

ssize_t aaFileStreamPRead(struct SKAAByteStream_impl stream, void * buf, size_t nbyte, off_t offset) {
  if (stream.fileDesc->reserved == 0) {
    return pread(stream.fileDesc->fd, buf, nbyte, offset);
  }
  return -1;
}

ssize_t aaFileStreamPWrite(struct SKAAByteStream_impl stream, void * buf, size_t nbyte, off_t offset) {
  if (stream.fileDesc->reserved == 0) {
    return pwrite(stream.fileDesc->fd, buf, nbyte, offset);
  }
  return -1;
}

void aaFileStreamAbort(struct SKAAByteStream_impl stream) {
  stream.fileDesc->reserved = 1;
}

off_t aaFileStreamSeek(struct SKAAByteStream_impl stream, off_t offset, int whence) {
  if (stream.fileDesc->reserved == 0) {
    return lseek(stream.fileDesc->fd, offset, whence);
  }
  return -1;
}

int aaFileStreamTruncate(struct SKAAByteStream_impl stream, off_t len) {
  if (stream.fileDesc->reserved == 0) {
    return ftruncate(stream.fileDesc->fd, len);
  }
  return -1;
}

ssize_t SKAAByteStreamWrite(SKAAByteStream s, void *buf, size_t nbyte);
ssize_t SKAAByteStreamPWrite(SKAAByteStream s, void *buf, size_t nbyte, off_t offset);
ssize_t SKAAByteStreamRead(SKAAByteStream s, void *buf, size_t nbyte);
ssize_t SKAAByteStreamPRead(SKAAByteStream s, void *buf, size_t nbyte, off_t offset);
off_t SKAAByteStreamSeek(SKAAByteStream s, off_t offset, int whence);
void SKAAByteStreamCancel(SKAAByteStream s);
int SKAAByteStreamClose(SKAAByteStream s);
int SKAAByteStreamTruncate(SKAAByteStream s, off_t offset);

SKAAByteStream SKAAFileStreamOpenWithFD(int fd,int automatic_close) {
    SKAAByteStream byteStream = calloc(1, 80);
    SKAAByteStreamFileDesc descStream = malloc(12); /* mystery struct */
    if (byteStream && descStream) {
        
      descStream->fd = fd;
      descStream->automatic_close = automatic_close;
      descStream->reserved = 0;
        
      byteStream->fileDesc = descStream;
      byteStream->close = aaFileStreamClose;
      byteStream->read = aaFileStreamRead;
      byteStream->write = aaFileStreamWrite;
      byteStream->pread = aaFileStreamPRead;
      byteStream->pwrite = aaFileStreamPWrite;
      byteStream->seek = aaFileStreamSeek;
      byteStream->abort = aaFileStreamAbort;
      byteStream->truncate = aaFileStreamTruncate;
      /* finish latr */
      return byteStream;
    }
    /* error */
    return 0;
}

SKAAByteStream SKAAFileStreamOpenWithPath(const char *path,int open_flags,mode_t open_mode) {
    int fileDesc = open(path,open_flags,open_mode);
    if (fileDesc >= 0) {
      SKAAByteStream byteStream = SKAAFileStreamOpenWithFD(fileDesc, 1);
      if (!byteStream) {
        close(fileDesc);
        return 0;
      }
      return byteStream;
   } else {
      /* error */
   }
   return 0;
}

/* debug functions */

void log_all_bytes_n(void *buf, size_t nbytes) {
    printf("Buffer:");
    unsigned char *bytes = buf;
    size_t limit = 256;
    size_t n;
    if (nbytes > limit) {
        n = limit;
    } else {
        n = nbytes;
    }
    for (int i = 0; i < n; i++) {
        printf(" %02x",bytes[i]);
    }
    printf("\n");
}

ssize_t debug_aeaInputStreamRead(SKAAByteStreamFileDesc fileDesc, void * buf, size_t nbyte) {
    printf("attempt aeaRead... (nbyte: %zu)\n",nbyte);
    ssize_t res = orig_aeaInputStreamRead(fileDesc, buf, nbyte);
    /* log buffer after read */
    log_all_bytes_n(buf, nbyte);
    return res;
}

ssize_t debug_aaFileStreamRead(SKAAByteStreamFileDesc fileDesc, void * buf, size_t nbyte) {
    printf("attempt read... (nbyte: %zu)\n",nbyte);
    if (fileDesc->reserved == 0) {
        ssize_t res = read(fileDesc->fd, buf, nbyte);
        log_all_bytes_n(buf, nbyte);
        return res;
    }
    return -1;
}

#endif
