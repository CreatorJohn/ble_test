# Encryption Review

We actually already have encryption implemented using `Chacha20.poly1305Aead` (an industry-standard alternative to AES used by Google/Cloudflare for mobile) in `MessageHandler.dart`. It uses the `X25519` key exchange to derive a shared secret.

The plan is to exit plan mode and inform the user.