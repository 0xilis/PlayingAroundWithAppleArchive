# PlayingAroundWithAppleArchive
Bad code I wrote for debugging some libAppleArchive functions

(This was just me playing around and decided to upload, not for serious debugging)

# Why?

libshortcutsign could work on other *nix platforms, but libAppleArchive is exclusive to Apple platforms. libAppleArchive is too daunting of a task for me to decomp, so I'm just playing around with seeing how it reads the file format to attempt to gain more info about it. If anyone has looked into Apple Archive or Apple Encrypted Archive, please tell me of their work, I'd love to see it!

# How?

libAppleArchive splits up items into different streams (ex `AAByteStream`). This stream contains the file descriptor, `AAByteStreamFileDesc` (might not be the actual internal name for the struct type but doesn't matter). libAppleArchive *does* have functions for reading this, `aaFileStreamRead`, but it doesn't call them manually. There are different types of byte streams, and libAppleArchive must somehow take them all into account within one struct. How it does this is splits up different struct types to have their own functions, and it saves those function pointers to the struct. When it wants to read from this stream, it calls `AAByteStreamRead`. What this function does is jump to the function pointer pointed on the struct, with the file descriptor from the struct.

For example, calling `AAFileStreamOpenWithPath` would give you an AAByteStream that is a file stream, which means that the function pointer on the struct will be `aaFileStreamRead`. However, let's say we are decrypting a AEA so we do `AEADecryptionInputStreamOpen`. This (assuming the operation is successful) will give you a AAByteStream meant for decryption - meaning it will be a function pointer to the internal `aeaInputStreamRead` call.

What I did is in libshortcutsign, I hook these internal function calls by after opening a stream, I simply just do `skdecryptionInputStream->read = debug_aeaInputStreamRead;` to call `debug_aeaInputStreamRead` instead. I also save the original function pointer, which I call. In `debug_aeaInputStreamRead`, I log the nbyte passed in, as well as the buffer after the read operation completes.

# What have you found with this?

Not much, but something is still something. I found that when extracting and decrypting contact signed shortcuts, there are 4 noticable segments called in the read calls:

Segment 1 - 12 byte header, not encrypted. Contains `AEA1` as well as the size of the AEA context.
Segment 2 - Also not encrypted. Contains the AEA context; looks like it may also contain some other info but I have no idea what it represents...
Segment 3 - The main AEA encrypted shortcut. The result of the `aeaInputStreamRead` call is an Apple Archive (not encrypted) of it.
Segment 4 - Encrypted, I have absolutely no idea what it is.

