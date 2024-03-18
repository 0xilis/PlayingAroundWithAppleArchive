/*
 * Snoolie K, (c) 2024.
 * library for contact signing shortcuts with no WorkflowKit
 * (Albeit, still requires libAppleArchive)
 * Based on my research on reversing WorkflowKit.
*/

#import <Foundation/Foundation.h>
#import <AppleArchive/AppleArchive.h>
#import <AppleArchive/AEAContext.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>
#include "libshortcutsign.h"
#include "libSKAppleArchive.h"

/* our hook */
ssize_t (*orig_aeaInputStreamRead)(SKAAByteStreamFileDesc fileDesc, void * buf, size_t nbyte);

#define NEEDS_LIBSHORTCUTSIGN 1
#if NEEDS_LIBSHORTCUTSIGN

#define EMBED_SKAA_IN_LIBSS 0
#if EMBED_SKAA_IN_LIBSS

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

ssize_t aaFileStreamRead(struct SKAAByteStream_impl *stream, void * buf, size_t nbyte) {
    printf("attempt read... (nbyte: %zu)\n",nbyte);
    if (!stream->fileDesc) {
        printf("no filedesc\n");
        //return orig_aaFileStreamRead(stream, buf, nbyte);
        return -1;
    }
    printf("stream->fileDesc->reserved: %d\n",stream->fileDesc->reserved);
    printf("stream->fileDesc->fd: %d\n",stream->fileDesc->fd);
    printf("stream->fileDesc->automatic_close: %d\n",stream->fileDesc->automatic_close);
  if (stream->fileDesc->reserved == 0) {
      printf("try to read\n");
    return read(stream->fileDesc->fd, buf, nbyte);
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

#endif

#ifndef COMPRESSION_LZFSE
#define COMPRESSION_LZFSE 0x801
#endif

/*
 * sign_shortcut_with_private_key_and_auth_data
 *
 * Contact signs a shortcut with a signing key and auth data.
 *
 * unsignedShortcutPath should be the path to the unsigned .shortcut file.
 * destPath should be the path you want to output the signed shortcut, including
 * the file name and extension of the signed shortcut.
 *
 * If verified, this function returns 0.
 * If not verified, this function returns a negative error code.
*/
int sign_shortcut_with_private_key_and_auth_data(SecKeyRef privKey, NSData *authData, const char *unsignedShortcutPath, const char *destPath) {
 int succeed = -1;
 AEAContext context = AEAContextCreateWithProfile(0);
 if (context) {
  if (AEAContextSetFieldUInt(context, AEA_CONTEXT_FIELD_COMPRESSION_ALGORITHM, COMPRESSION_LZFSE) == 0) {
   CFErrorRef cferr = 0;
   NSData *key = (__bridge NSData *)SecKeyCopyExternalRepresentation(privKey, &cferr);
   if (key) {
    if (AEAContextSetFieldBlob(context, AEA_CONTEXT_FIELD_SIGNING_PRIVATE_KEY, AEA_CONTEXT_FIELD_REPRESENTATION_X963, [key bytes], [key length]) == 0) {
     AEAContextSetFieldBlob(context, AEA_CONTEXT_FIELD_AUTH_DATA, AEA_CONTEXT_FIELD_REPRESENTATION_RAW, [authData bytes], [authData length]);
     AAByteStream byteStream = AAFileStreamOpenWithPath(destPath,O_CREAT | O_RDWR, 420);
     AAByteStream encryptedStream = AEAEncryptionOutputStreamOpen(byteStream, context, 0, 0);
     AAFieldKeySet fields = AAFieldKeySetCreateWithString("TYP,PAT,LNK,DEV,DAT,MOD,FLG,MTM,BTM,CTM,HLC,CLC");
     if (fields) {
      AAPathList pathList = AAPathListCreateWithDirectoryContents(unsignedShortcutPath, 0, 0, 0, 0, 0);
      if (pathList) {
       AAArchiveStream archiveStream = AAEncodeArchiveOutputStreamOpen(encryptedStream, 0, 0, 0, 0);
       if (archiveStream) {
        /* If it was successful it will return 0 */
        succeed = AAArchiveStreamWritePathList(archiveStream, pathList, fields, unsignedShortcutPath, 0, 0, 0, 0);
        AAArchiveStreamClose(archiveStream);
       }
       AAPathListDestroy(pathList);
      }
      AAFieldKeySetDestroy(fields);
     }
     AAByteStreamClose(encryptedStream);
     AAByteStreamClose(byteStream);
    }
   }
  }
  AEAContextDestroy(context);
 }
 return succeed;
}

/*
 * auth_data_from_shortcut
 *
 * Retrieves the auth data from a signed shortcut.
 *
 * This function is one of the few that doesn't use
 * libAppleArchive or Security.framework, meaning
 * even on non-apple platforms this function should
 * work for you. It does return it as NSData so
 * Foundation is needed, but if you don't want to
 * use GNUstep you can modify it to instead just
 * return the buffer variable itself.
 *
 * If it fails to get auth data, it will return 0/nil.
*/
NSData *auth_data_from_shortcut(const char *filepath) {
 /* load shortcut into memory */
 FILE *fp = fopen(filepath, "r");
 if (!fp) {
  fprintf(stderr,"libshortcutsign: failed to open file\n");
  return 0;
 }
 fseek(fp, 0, SEEK_END);
 size_t size = ftell(fp);
 fseek(fp, 0, SEEK_SET);
 char *archive = malloc(size * sizeof(char));
 /* copy bytes to binary */
 int c;
 size_t n = 0;
 while ((c = fgetc(fp)) != EOF) {
  archive[n++] = (char) c;
 }
 size_t archive_size = n;
 fclose(fp);
 /* find the size of AEA_CONTEXT_FIELD_AUTH_DATA field blob */
 /* We assume it's located at 0x8-0xB */
 register const char *sptr = archive + 0xB;
 size_t buf_size = *sptr << 24;
 buf_size += *(sptr - 1) << 16;
 buf_size += *(sptr - 2) << 8;
 buf_size += *(sptr - 3);
 if (buf_size > archive_size-0x293c) {
  /*
   * The encrypted data for for signed shortcuts, both contact signed
   * and icloud signed, should be at buf_size+0x293c. If our buf_size
   * reaches to or past the encrypted data, then it's too big.
  */
  fprintf(stderr,"libshortcutsign: buf_size reaches past data start\n");
  return 0;
 }
 /* we got buf_size, now fill buffer */
 uint8_t *buffer = (uint8_t *)malloc(buf_size);
 /*
  * the reason why we are doing a reverse
  * iteration is because doing it this way
  * will allow arm devices to take advantage
  * of the cbnz instruction, which should
  * mean about a 2 cycle save per iteration.
  *
  * also we're going to blindly trust that buf_size
  * is not larger than the buffer, because unless
  * you malform a aea file it should never be.
 */
 unsigned long i = buf_size;
 fill_buffer:
 i--;
 buffer[i] = archive[i+0xc];
 if (i != 0) {goto fill_buffer;};
 free(archive);
 /* make buffer NSData */
 NSData *authData = [NSData dataWithBytesNoCopy:buffer length:buf_size];
 return authData;
}

/*
 * decrypt_archive
 *
 * This function is meant for private use in extract_contact_signed_shortcut.
 * It should not be run normally, hence it is not defined in the header.
*/
int decrypt_archive(AAByteStream byteStream, AEAContext context, const char *signedShortcutPath, const char *destPath) {
 AAArchiveStream archiveStream = AAExtractArchiveOutputStreamOpen(destPath, nil, nil, 1, 0);
 if (!archiveStream) {
  fprintf(stderr,"libshortcutsign: AAExtractArchiveOutputStreamOpen returned nil\n");
  return -4;
 }
 AAByteStream decryptionInputStream = AEADecryptionInputStreamOpen(byteStream, context, 0, 0);
 if (!decryptionInputStream) {
  /*
   * Special Note: WorkflowKit doesn't check if we were actually successful
   * at opening the decryption input stream, at least as of iOS 16.
   * This will cause WorkflowKit to not show an error, but full on crash at
   * the AAArchiveStreamProcess. This is as it will try to jump to a function
   * pointer, and since the decryption input stream failed, it will be NULL.
   * Not sure if this is a WorkflowKit bug and it should be checking for nil
   * or if it's a libAppleArchive bug and it should check if the function pointers
   * actually exist on the struct before attempting to jump to it.
  */
  fprintf(stderr,"libshortcutsign: AEADecryptionInputStreamOpen returned nil\n");
  return -5;
 }
    /* hook aeaInputStreamRead */
    SKAAByteStream skdecryptionInputStream = (SKAAByteStream)decryptionInputStream;
    if (skdecryptionInputStream->read) {
        printf("->read at: %p\n",skdecryptionInputStream->read);
    } else {
        printf("->read not found\n");
        return -1;
    }
    orig_aeaInputStreamRead = skdecryptionInputStream->read;
    if (orig_aeaInputStreamRead) {
        printf("saved the world, orig_aeaInputStreamRead exists\n");
    }
    skdecryptionInputStream->read = debug_aeaInputStreamRead;
 AAArchiveStream decodeStream = AADecodeArchiveInputStreamOpen(decryptionInputStream, nil, nil, 0, 0);
 if (!decodeStream) {
  fprintf(stderr,"libshortcutsign: AADecodeArchiveInputStreamOpen returned nil\n");
  return -6;
 }
 /* Extracting Signed Shortcut Data */
 ssize_t archiveEntries = AAArchiveStreamProcess(decodeStream, archiveStream, nil, nil, 0, 0);
 /* archiveEntries will return a negative error code if failure */
 if (archiveEntries >= 0) {
  if (AAArchiveStreamClose(archiveStream) >= 0) {
   /* Success */
   return 0;
  } else {
   fprintf(stderr,"libshortcutsign: AAArchiveStreamClose failed\n");
   return -8;
  }
 } else {
  fprintf(stderr,"libshortcutsign: failed to extract, error: %zu\n", archiveEntries);
  return -7;
 }
}

/*
 * decrypt_signed_shortcut_with_context
 *
 * This function is meant for private use in extract_contact_signed_shortcut.
 * It should not be run normally, hence it is not defined in the header.
*/
int decrypt_signed_shortcut_with_context(AAByteStream byteStream, AEAContext context, NSData *authData, const char *signedShortcutPath, const char *destPath) {
 NSDictionary *dict = [NSPropertyListSerialization propertyListWithData:authData options:0 format:0 error:nil];
 if (dict) {
  if ([dict isKindOfClass:[NSDictionary class]]) {
   CFDataRef signingPublicKey = (__bridge CFDataRef)dict[@"SigningPublicKey"];

   SecKeyRef publicKey = SecKeyCreateWithData(signingPublicKey,(__bridge CFDictionaryRef)@{
    (__bridge NSString *)kSecAttrKeyType : (__bridge NSString *)kSecAttrKeyTypeECSECPrimeRandom,
    (__bridge NSString *)kSecAttrKeyClass : (__bridge NSString *)kSecAttrKeyClassPublic,
   }, nil);
   NSData *externalRep = (__bridge NSData*)SecKeyCopyExternalRepresentation(publicKey, nil);
   if (AEAContextSetFieldBlob(context, AEA_CONTEXT_FIELD_SIGNING_PUBLIC_KEY, AEA_CONTEXT_FIELD_REPRESENTATION_X963, [externalRep bytes], [externalRep length]) == 0) {
    return decrypt_archive(byteStream, context, signedShortcutPath, destPath);
   } else {
    fprintf(stderr,"libshortcutsign: failed to set public key\n");
    return -3;
   }
  }
 } else {
  printf("failed to create dict from auth data\n");
 }
 return -2;
}

/*
 * extract_contact_signed_shortcut
 *
 * Extracts/Decrypts the unsigned shortcut from a contact signed shortcut
 *
 * signedShortcutPath should be the filepath to the contact signed shortcut.
 * destPath should be a directory that you want to store the unsigned shortcut
 * file in. If extraction is successful, it would be placed as "Shortcut.wflow"
 * in the destPath. destPath must exist.
 *
 * If the function was successful, it will return 0.
 * If not, it will return a negative error code.
*/
int extract_contact_signed_shortcut(const char *signedShortcutPath, const char *destPath) {
 /*if (!access(destPath, F_OK)) {
  fprintf(stderr,"libshortcutsign: directory not created specified in destPath\n");
  return -1;
 }*/
 AAByteStream byteStream = AAFileStreamOpenWithPath(signedShortcutPath, 0, 420);
    SKAAByteStream skbyteStream = (SKAAByteStream)byteStream;
    /* debug hook */
    skbyteStream->read = debug_aaFileStreamRead;
 if (byteStream) {
  AEAContext context = AEAContextCreateWithEncryptedStream(byteStream);
  if (context) {
   NSData *authData = auth_data_from_shortcut(signedShortcutPath);
   return decrypt_signed_shortcut_with_context(byteStream, context, authData, signedShortcutPath, destPath);
  }
 }
 return -9;
}

/* WIP function, ignore */
#if 0
NSData *auth_data_for_account(OpaqueSecCertificateRef cert, OpaqueSecCertificateRef intermediateCert, OpaqueSecKeyRef privateKey, SecKeyRef signingKey) {
 SecKeyRef pubKey = SecKeyCopyPublicKey(key);
 CFDataRef data = SecKeyCopyExternalRepresentation(pubKey);
 NSData *signature = (__bridge NSData *)SecKeyCreateSignature(privateKey, kSecKeyAlgorithmRSASignatureMessagePSSSHA256, data, 0);
 return 0;
}
#endif

/*
 * generate_appleid_certs_with_data
 *
 * Generates an array of SecCertificateRef certs from
 * an NSArray containing NSData for the certs.
 *
 * This can be used for getting a cert chain from the
 * extracted auth data of a shortcut.
 *
 * If the function fails, it returns 0/nil.
*/
NSArray *generate_appleid_certs_with_data(NSArray *appleIDCertDataChain) {
 unsigned long count = [appleIDCertDataChain count];
 if (count < 1) {
  fprintf(stderr,"libshortcutsign: no items in passed in cert data chain\n");
  return 0;
 }
 NSMutableArray *returnArray = [[NSMutableArray alloc]initWithCapacity:count];
 NSData *certData;
 SecCertificateRef cert;
 for (int i = 0; i < count; i++) {
  certData = appleIDCertDataChain[i];
  cert = SecCertificateCreateWithData(0, (__bridge CFDataRef)certData);
  returnArray[i] = CFBridgingRelease(cert);
 }
 return [[NSArray alloc]initWithArray:returnArray];
}

#if 0

/* We have to define these ourselves */
SecPolicyRef SecPolicyCreateAppleIDAuthorityPolicy(void);
extern const CFStringRef kSecPolicyCheckTemporalValidity;
void SecPolicySetOptionsValue(SecPolicyRef policy, CFStringRef key, CFTypeRef value);
SecPolicyRef SecPolicyCreateAppleIDValidationRecordSigningPolicy(void);
OSStatus SecCMSVerifyCopyDataAndAttributes(CFDataRef message, CFDataRef detached_contents, CFTypeRef policy, SecTrustRef *trustref, CFDataRef *attached_contents, CFDictionaryRef *signed_attributes);

/*
 * verify_dict_auth_data
 *
 * Replicates the 1st step of WorkflowKit's signature check process.
 * The first sort of signature checking is not actually from
 * validation methods at all, but rather inside of the method
 * to get the signing context from auth data.
 * This is intended for contact signed shortcuts, as if this step detects
 * SigningCertificateChain, it sees it as iCloud signed and forms context
 * from the certificate chain, and this step will not do any checking
 * and instead just return YES.
 *
 * For both steps of contact signed validation, call verify_contact_signed_shortcut.
 *
 * If verified, this function returns 0.
 * If not verified, this function returns a negative error code.
*/
int verify_dict_auth_data(NSDictionary *dict) {
 /* TODO: Finish this function. */
 NSArray *appleIDDataCertChain = dict[@"AppleIDCertificateChain"];
 if (appleIDDataCertChain && [appleIDDataCertChain isKindOfClass:[NSArray class]]) {
  NSArray *appleIDCertChain = generate_appleid_certs_with_data(appleIDDataCertChain);
  NSData *signingPublicKey = dict[@"SigningPublicKey"];
  if (![signingPublicKey isKindOfClass:[NSData class]]) {
   signingPublicKey = nil;
  }
  NSData *signingPublicKeySignature = dict[@"SigningPublicKeySignature"];
  if (![signingPublicKeySignature isKindOfClass:[NSData class]]) {
   signingPublicKeySignature = nil;
  }
  SecKeyRef publicKey = SecCertificateCopyKey((__bridge SecCertificateRef)[appleIDCertChain firstObject]);
  SecKeyCreateWithData((__bridge CFDataRef)signingPublicKey, (__bridge CFDictionaryRef)@{
   (__bridge NSString *)kSecAttrKeyType : (__bridge NSString *)kSecAttrKeyTypeECSECPrimeRandom,
   (__bridge NSString *)kSecAttrKeyClass : (__bridge NSString *)kSecAttrKeyClassPublic,
  }, nil);
  unsigned char isVerified = SecKeyVerifySignature(publicKey, kSecKeyAlgorithmRSASignatureMessagePSSSHA256, (__bridge CFDataRef)signingPublicKey, (__bridge CFDataRef)signingPublicKeySignature, nil);
  if (isVerified) {
   NSData *appleIDValidationRecord = dict[@"AppleIDValidationRecord"];
   if (appleIDValidationRecord) {
    dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
    dispatch_queue_t queue = dispatch_queue_create("SFAppleIDQueue",attr);
    (void)dispatch_semaphore_create(0);
    if (!queue) {
     queue = dispatch_get_global_queue(0, 0);
    }
    SecPolicyRef policy = SecPolicyCreateAppleIDValidationRecordSigningPolicy();
    if (policy) {
     SecPolicySetOptionsValue(policy, kSecPolicyCheckTemporalValidity, kCFBooleanFalse);
     SecTrustRef trust = 0;
     CFDataRef attachedRecordContents = 0;
     if (SecCMSVerifyCopyDataAndAttributes((__bridge CFDataRef)appleIDValidationRecord, 0, policy, &trust, &attachedRecordContents, 0) == 0) {
      if (trust && attachedRecordContents) {
       NSDictionary *authDict = [NSPropertyListSerialization propertyListWithData:(__bridge NSData *)attachedRecordContents options:0 format:0 error:0];
       if (authDict) {
        /* there is more checking here, but for now it isn't implemented. */
        return 0;
       }
      }
     }
    }
   }
  }
 }
 return -1;
}

/*
 * verify_dict_auth_data_cert_trust
 *
 * Replicates the 2nd step of WorkflowKit's signature check process.
 * validateAppleIDCertificatesWithError checks the trust of the cert chain.
 * It should be noted that WorkflowKit actually checks if SecTrustEvaluateWithError
 * returns errSecCertificateExpired, and if it does, it renders it as valid anyway.
 *
 * For both steps of contact signed validation, call verify_contact_signed_shortcut.
 *
 * If verified, this function returns 0.
 * If not verified, this function returns a negative error code.
*/
int verify_dict_auth_data_cert_trust(NSDictionary *dict) {
 NSArray *appleIDDataCertChain = dict[@"AppleIDCertificateChain"];
 if (appleIDDataCertChain && [appleIDDataCertChain isKindOfClass:[NSArray class]]) {
  NSArray *appleIDCertChain = generate_appleid_certs_with_data(appleIDDataCertChain);
  if (appleIDCertChain) {
   SecPolicyRef policy = SecPolicyCreateAppleIDAuthorityPolicy();
   SecPolicySetOptionsValue(policy,kSecPolicyCheckTemporalValidity,kCFBooleanFalse);
   if (policy) {
    SecTrustRef trust;
    OSStatus res = SecTrustCreateWithCertificates((__bridge CFArrayRef)appleIDCertChain, policy, &trust);
    if (res == 0) {
     if (trust) {
      /* if we got errSecCertificateExpired return valid anyway */
      CFErrorRef trustErr;
      if (SecTrustEvaluateWithError(trust, &trustErr) == 0) {
       CFErrorDomain domain = CFErrorGetDomain(trustErr);
       if (CFEqual(domain, NSOSStatusErrorDomain)) {
        if (CFErrorGetCode(trustErr) == errSecCertificateExpired) {
         return 0;
        }
       }
      } else {
       return 0;
      }
     }
    }
   }
  }
 }
 return -1;
}

/*
 * verify_contact_signed_auth_data
 *
 * Replicates WorkflowKit's signature check process
 * The first sort of signature checking is not actually from
 * validation methods at all, but rather inside of the method
 * to get the signing context from auth data.
 *
 * Then, next, it uses validateAppleIDCertificatesWithError to check the trust.
 * It should be noted that WorkflowKit actually checks if SecTrustEvaluateWithError
 * returns errSecCertificateExpired, and if it does, it renders it as valid anyway.
 *
 * Finally, it uses validateAppleIDValidationRecordWithCompletion to check
 * if you shared the shortcut via the AltDSID in the validation record, or
 * if it's from someone in your contacts via the SHA256 phone/email hashes.
 * libshortcutsign doesn't replicate this final part, as it's easy to check
 * yourself if you have that info. Everything else is implemented by libshortcutsign.
 *
 * Currently (as the name implies) this only checks contact signed shortcuts, though
 * in the future a function for checking iCloud signed shortcuts may be implemented.
 *
 * If you just want to do the first step, call verify_dict_auth_data.
 * If you just want to do the second step, call verify_dict_auth_data_cert_trust.
 * If you want to use the path of the shortcut, call verify_contact_signed_shortcut.
 *
 * If verified, this function returns 0.
 * If not verified, this function returns a negative error code.
*/
int verify_contact_signed_auth_data(NSData *authData) {
 NSDictionary *dict = [NSPropertyListSerialization propertyListWithData:authData options:0 format:0 error:nil];
 if (dict && [dict isKindOfClass:[NSDictionary class]]) {
  if (verify_dict_auth_data(dict) == 0) {
   return verify_dict_auth_data_cert_trust(dict);
  }
 }
 /* validation failed :( */
 return -1;
}

/*
 * verify_contact_signed_shortcut
 *
 * Replicates WorkflowKit's signature check process
 * The first sort of signature checking is not actually from
 * validation methods at all, but rather inside of the method
 * to get the signing context from auth data.
 *
 * Then, next, it uses validateAppleIDCertificatesWithError to check the trust.
 * It should be noted that WorkflowKit actually checks if SecTrustEvaluateWithError
 * returns errSecCertificateExpired, and if it does, it renders it as valid anyway.
 *
 * Finally, it uses validateAppleIDValidationRecordWithCompletion to check
 * if you shared the shortcut via the AltDSID in the validation record, or
 * if it's from someone in your contacts via the SHA256 phone/email hashes.
 * libshortcutsign doesn't replicate this final part, as it's easy to check
 * yourself if you have that info. Everything else is implemented by libshortcutsign.
 *
 * Currently (as the name implies) this only checks contact signed shortcuts, though
 * in the future a function for checking iCloud signed shortcuts may be implemented.
 *
 * If you just want to do the first step, call verify_dict_auth_data.
 * If you just want to do the second step, call verify_dict_auth_data_cert_trust.
 *
 * If verified, this function returns 0.
 * If not verified, this function returns a negative error code.
*/
int verify_contact_signed_shortcut(const char *signedShortcutPath) {
 NSData *authData = auth_data_from_shortcut(signedShortcutPath);
 if (!authData) {
  fprintf(stderr,"libshortcutsign: verification failed to extract authData\n");
  return -1;
 }
 return verify_contact_signed_auth_data(authData);
}

/*
 * signing_cert_chain_for_icloud_signed_shortcut
 *
 * The SigningCertificateChain of an iCloud signed shortcut.
 *
 * Returns the signing chain on success.
 * On fail, returns nil.
*/
NSArray *signing_cert_chain_for_icloud_signed_shortcut(const char *signedShortcutPath) {
 NSData *authData = auth_data_from_shortcut(signedShortcutPath);
 NSDictionary *dict;
 if (!authData) {
  goto temp_fix_later_use_aea_manual;
 }
 dict = [NSPropertyListSerialization propertyListWithData:authData options:0 format:0 error:nil];
 if (!dict) {
  temp_fix_later_use_aea_manual:
  /*
   * For some reason, my current implementation, while does
   * work for contact signed shortcut files, doesn't for
   * iCloud signed?? Implement calling aea functions as a
   * placebo later, and later later, find out whats wrong.
  */
  fprintf(stderr,"libshortcutsign: failed to get aea info\n");
  exit(1);
 }
 NSArray *signingDataCertChain = dict[@"SigningCertificateChain"];
 if (!signingDataCertChain) {
  fprintf(stderr,"libshortcutsign: no SigningCertificateChain present\n");
  return 0;
 }
 return signingDataCertChain;
}

/*
 * verify_icloud_signed_shortcut
 *
 * Replicates WorkflowKit's signature check process
 * This is (not counting the encryption process itself)
 * the only form of validation for iCloud signed shortcuts.
 * Note that in the original WorkflowKit implementation,
 * if the certificate has expired (unlike contact signed
 * shortcuts, Shortcuts DOES actually care if iCloud signed
 * expire), it will attempt to redownload it from iCloud.
 * This function does not replicate this behavior, instead
 * it will return a negative error code.
 *
 * If verified, this function returns 0.
 * If not verified, this function returns a negative error code.
*/
int verify_icloud_signed_shortcut(const char *signedShortcutPath) {
 NSArray *signingDataCertChain = signing_cert_chain_for_icloud_signed_shortcut(signedShortcutPath);
 if (!signingDataCertChain) {
  fprintf(stderr,"libshortcutsign: failed to get signingDataCertChain\n");
  return -1;
 }
 NSArray *signingCertChain = generate_appleid_certs_with_data(signingDataCertChain);
 if ([signingCertChain count] != [signingDataCertChain count]) {
  return -1;
 }
 SecPolicyRef policy = SecPolicyCreateRevocation(kSecRevocationUseAnyAvailableMethod);
 SecTrustRef trust = 0;
 OSStatus res = SecTrustCreateWithCertificates((__bridge CFArrayRef)signingCertChain, policy, &trust);
 if (res == 0 || (res != 0 && !trust)) {
  SecCertificateRef root = (__bridge SecCertificateRef)(signingCertChain[0]);
  CFErrorRef evaluateErr = 0;
  bool isValid = SecTrustEvaluateWithError(trust, &evaluateErr);
  if (isValid) {
   /* This is a bitfield that cert[0] should have. */
   if (SecCertificateCopyExtensionValue(root, @"1.2.840.113635.100.18.1", 0)) {
    /* Our signing chain is valid, return 0. */
    return 0;
   }
  }
 }
 return -1;
}

/*
 * signed_shortcut_from_icloud_id
 *
 * Calls the iCloud API to retrieve the signed shortcut.
 * Returns this file as NSData.
 *
 * Please only call this function on the background thread.
*/
NSData *signed_shortcut_from_icloud_id(const char *icloudId);

/*
 * icloud_id_for_icloud_signed_shortcut
 *
 * In a iCloud signed shortcut, the first
 * certificate in the certificate should
 * have the name as the identifier of
 * the shortcut on icloud.
 *
 * Returns a NSString if successful.
 * On error, returns nil.
*/
NSString *icloud_id_for_icloud_signed_shortcut(const char *signedShortcutPath) {
 NSArray *signingDataCertChain = signing_cert_chain_for_icloud_signed_shortcut(signedShortcutPath);
 if (!signingDataCertChain) {
  fprintf(stderr,"libshortcutsign: failed to get signingDataCertChain\n");
  return 0;
 }
 NSArray *signingCertChain = generate_appleid_certs_with_data(signingDataCertChain);
 if ([signingCertChain count] != [signingDataCertChain count]) {
  return 0;
 }
 SecCertificateRef root = (__bridge SecCertificateRef)(signingCertChain[0]);
 CFStringRef rootCertName = 0;
 SecCertificateCopyCommonName(root, &rootCertName);
 return (__bridge NSString *)rootCertName;
}

#endif

#endif