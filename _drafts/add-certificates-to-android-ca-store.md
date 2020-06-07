---
# vi: set tw=72 et sw=2 sts=-1 autoindent fo=troqan :
title: Add a root CA certificate to Android CA store
category: android
---

# {{ page.title }}

While trying to add a missing root CA certificate to my Android phone,
I stumbled into [this blog post][original-article].

To sum it up, to add a new root CA to your Android system, you have to:

1. save the certificate to a file in PEM format;
2. give the file a specific name, derived by hashing the subject's
   distinguished name;
3. copy this file to Android under `/system/etc/security/cacerts/`.

The culprit is point 2, as giving the file any other name will not work.
In particular, it will still show up under Android's credential list,
but applications will _not_ be able to use it.  In order to obtain the
correct file name one can use `openssl` to compute the _subject hash_,
as pointed by the referenced article:

    HASH=$(openssl x509 -subject_hash -in mycert.pem | head -1)

After that, the file should be renamed to `${HASH}.0`. So, if the
`openssl` invocation yielded `1234ABCD`, the file should be named
`1234ABCD.0`.

It tried exactly this, and it didn't work.

It turns out that the algorithm used to compute the subject hash has
[changed][openssl-changelog] in OpenSSL 1.0.0. The `-subject_hash`
option now uses the new algorithm, while the previous implementation can
still be accessed using `-subject_hash_old`.

On my phone, certificates are named after the _old_ hash, but the
OpenSSL version I was using to generate them was higher than 1.0.0.
Therefore, the name was actually incorrect and the certificate wasn't
found.

It is pretty easy to fix the command to generate old-style hashes:

    HASH=$(openssl x509 -subject_hash_old -in mycert.pem | head -1)

A surefire way to check if you are generating names correctly is to grab
one certificate from your phone store and calculate its hash. If the
generated value doesn't match the file name, you need to switch
algorithm in OpenSSL invocation.

<!-- Links -->
[original-article]: https://ivrodriguez.com/installing-self-signed-certificates-on-android/
[openssl-changelog]: https://www.openssl.org/news/changelog.html#openssl-100
