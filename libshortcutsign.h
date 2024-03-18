/*
 * Snoolie K, (c) 2024.
 * library for contact signing shortcuts with no WorkflowKit
 * (Albeit, still requires libAppleArchive)
 * Based on my research on reversing WorkflowKit.
*/

#ifndef libshortcutsign_h
#define libshortcutsign_h

#import <Foundation/Foundation.h>
#import <AppleArchive/AppleArchive.h>
#import <AppleArchive/AEAContext.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>

//ssize_t (*orig_aaFileStreamRead)(long long stream, void * buf, size_t nbyte);

int sign_shortcut_with_private_key_and_auth_data(SecKeyRef privKey, NSData *authData, const char *unsignedShortcutPath, const char *destPath);
NSData *auth_data_from_shortcut(const char *filepath);
int extract_contact_signed_shortcut(const char *signedShortcutPath, const char *destPath);
NSArray *generate_appleid_certs_with_data(NSArray *appleIDCertDataChain);
int verify_dict_auth_data(NSDictionary *dict);
int verify_dict_auth_data_cert_trust(NSDictionary *dict);
int verify_contact_signed_auth_data(NSData *authData);
int verify_contact_signed_shortcut(const char *signedShortcutPath);
int verify_icloud_signed_shortcut(const char *signedShortcutPath);
NSData *signed_shortcut_from_icloud_id(const char *icloudId);

#endif /* libshortcutsign_h */
