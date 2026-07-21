# Modifications to upstream LOKI97 sources

This document tracks every modification applied on top of the upstream
LOKI97 reference implementation. Pristine sources are downloaded by
`build_cli.sh`; the patches in `patches/` are then applied before
compilation.

## Provenance

Upstream archive: `LOKI97-2.zip` from
<https://www.schneier.com/wp-content/uploads/2015/03/LOKI97-2.zip>,
the author-signed reference implementation by Lawrie Brown, Josef
Pieprzyk, and Jennifer Seberry (1997). Inside the zip the relevant
files live under `cref/`; we copy `cref/loki97.c` and `cref/loki97.h`
to the build root so that `gcc cli.c loki97.c` works without extra
include paths.

## Patches

### `patches/loki97.h.patch`

**Files touched:** `loki97.h` line 59.

**What it changes:**

```
-typedef    struct { unsigned long l,r; } ULONG64;	/* 64bit unsigned int */
+typedef    struct { unsigned int  l,r; } ULONG64;	/* 64bit unsigned int */
```

**Why:** `ULONG64` represents a 64-bit value as two 32-bit halves
(`l` and `r`). The reference was written in 1998, when `unsigned long`
was 32 bits on the targeted platforms (Win32, 32-bit Linux, etc.). On
modern x86_64 Linux, `unsigned long` is 64 bits, so each half would
silently widen to 64 bits — and the manual carry handling in `add64`
(`if (sum.r < b.r) sum.l++`) would never trigger because the lower
half no longer overflows at 2^32. That would corrupt every 64-bit
addition done in the key schedule and the round function `f`, so the
cipher would produce wrong output. `unsigned int` is 32 bits on all
platforms this benchmark targets, restoring the intended semantics.

This is purely a portability fix: it does not touch any LOKI97-specific
code path and reveals nothing about the algorithm's cryptographic
properties.
