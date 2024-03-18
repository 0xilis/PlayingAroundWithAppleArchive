//
//  libSKAppleArchive.h
//  AAFromScratch
//
//  Created by Snoolie Keffaber on 2024/03/18.
//

#ifndef libSKAppleArchive_h
#define libSKAppleArchive_h

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>

struct SKAAByteStreamFileDesc_impl {
    int fd;
    int automatic_close;
    int reserved;
};

typedef struct SKAAByteStreamFileDesc_impl* SKAAByteStreamFileDesc;

struct SKAAByteStream_impl {
    SKAAByteStreamFileDesc fileDesc;
    int (*close)(struct SKAAByteStream_impl); /* 0x8 */
    ssize_t (*read)(struct SKAAByteStream_impl, void*, size_t); /* 0x10 */
    ssize_t (*write)(struct SKAAByteStream_impl, void*, size_t); /* 0x18 */
    ssize_t (*pread)(struct SKAAByteStream_impl, void*, size_t, off_t offset); /* 0x20 */
    ssize_t (*pwrite)(struct SKAAByteStream_impl, void*, size_t, off_t offset); /* 0x28 */
    off_t (*seek)(struct SKAAByteStream_impl, off_t, int); /* 0x30 */
    void (*abort)(struct SKAAByteStream_impl); /* 0x38 */
    int (*truncate)(struct SKAAByteStream_impl, off_t); /* 0x40 */
};

typedef struct SKAAByteStream_impl* SKAAByteStream;

int aaFileStreamClose(struct SKAAByteStream_impl stream);
ssize_t aaFileStreamRead(SKAAByteStreamFileDesc fileDesc, void * buf, size_t nbyte);
ssize_t aaFileStreamWrite(struct SKAAByteStream_impl stream, void * buf, size_t nbyte);
ssize_t aaFileStreamPRead(struct SKAAByteStream_impl stream, void * buf, size_t nbyte, off_t offset);
ssize_t aaFileStreamPWrite(struct SKAAByteStream_impl stream, void * buf, size_t nbyte, off_t offset);

extern ssize_t (*orig_aeaInputStreamRead)(SKAAByteStreamFileDesc fileDesc, void * buf, size_t nbyte);
ssize_t debug_aeaInputStreamRead(SKAAByteStreamFileDesc fileDesc, void * buf, size_t nbyte);
ssize_t debug_aaFileStreamRead(SKAAByteStreamFileDesc fileDesc, void * buf, size_t nbyte);

#endif /* libSKAppleArchive_h */
