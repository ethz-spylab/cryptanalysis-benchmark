# Modifications to upstream MAGENTA sources

This document tracks every modification applied on top of the upstream
MAGENTA reference implementation. Pristine sources are downloaded by
`build_cli.sh`; the patches in `patches/` are then applied before
compilation.

## Provenance

Upstream archive: `MAGENTA-2.zip` from
<https://www.schneier.com/wp-content/uploads/2015/03/MAGENTA-2.zip>.
Deutsche Telekom only ever submitted a PDF spec for MAGENTA, so no
author-signed C reference exists. The zip linked above is Brian
Gladman's spec-faithful reimplementation (header inside `magenta.c`
reads "independent implementation of MAGENTA by Deutche Telekom ...
Copyright in this implementation is held by Dr B R Gladman"); this
is the implementation the AES community consistently cites when a
reference C is needed.

The zip ships `magenta.c` and `std_defs.h` side-by-side at the root,
but `magenta.c` contains `#include "../std_defs.h"` (an artefact of
Gladman's original dev tree, where `std_defs.h` was a header shared
between several ciphers and lived one directory above each). The
build script unpacks `magenta.c` into `MAGENTA/` and leaves
`std_defs.h` at the top level so that include path resolves
correctly without modifying the source.

## Patches

### `patches/std_defs.h.patch`

**Files touched:** `std_defs.h` lines 6 and 10.

**What it changes:**

```
-typedef unsigned long   u4byte; /* a 32 bit unsigned integer type   */
+typedef unsigned int    u4byte; /* a 32 bit unsigned integer type   */
...
-typedef signed long     s4byte; /* a 32 bit signed integer type     */
+typedef signed int      s4byte; /* a 32 bit signed integer type     */
```

**Why:** Brian Gladman wrote `std_defs.h` in 1999, when `unsigned long`
was 32 bits on the target platforms (Win32, 32-bit Linux). On modern
x86_64 Linux, `unsigned long` is 64 bits, which silently widens
`u4byte`. MAGENTA's PE function and key schedule rely on 32-bit
semantics in macros like `byte(x,n) = ((u1byte)((x) >> (8 * n)))` and
in the byte-extraction code that builds the round inputs, so a
64-bit `u4byte` would make the cipher produce wrong output. `unsigned
int` is 32 bits on all platforms this benchmark targets, restoring
the intended semantics.

This is purely a portability fix: it does not touch any
MAGENTA-specific code path and reveals nothing about the algorithm's
cryptographic properties.
