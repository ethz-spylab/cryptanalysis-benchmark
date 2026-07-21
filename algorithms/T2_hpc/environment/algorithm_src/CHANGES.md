# Modifications to upstream HPC sources

This document tracks every modification applied on top of the upstream
HPC reference implementation. The pristine upstream sources live under
`vendor/`; the patches in `patches/` are applied during `build_cli.sh`.

## Provenance

Upstream archive: `HPC.zip` from
<https://www.schneier.com/wp-content/uploads/2015/03/HPC.zip>.
The zip ships two files at its root: `hpc.c` and `std_defs.h`.

Layout choices made here (not changes to file contents):

- `vendor/std_defs.h`: copied from the zip root.
- `vendor/HPC/hpc.c`: copied from the zip root into a `HPC/` subdirectory.
  The upstream `hpc.c` already contains `#include "../std_defs.h"`, so
  putting `hpc.c` one directory below `std_defs.h` simply makes that
  existing include path resolve.
- Line endings were converted from CR LF (the form they have inside the
  Schneier-mirror zip) to LF. No textual content changed.

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
`u4byte`. The HPC key schedule and round function rely on 32-bit
overflow / shift / carry behaviour (see the `add_eq`, `lsh_eq`, `rsh_eq`
macros in `HPC/hpc.c`), so a 64-bit `u4byte` would make the cipher
produce wrong output. `unsigned int` is 32 bits on all platforms this
benchmark targets, restoring the intended semantics.

This is purely a portability fix: it does not touch any HPC-specific
code path and reveals nothing about the algorithm's cryptographic
properties.
