# Changes applied to upstream SABER

All changes are expressed as patch files under `patches/` and are applied by
`build_cli.sh` after the upstream repository is cloned. Each patch is listed
below with its purpose.

## `0001-select-lightsaber.patch`

**File touched:** `Reference_Implementation_KEM/SABER_params.h`

**Change:** switch `#define SABER_L` from `3` (Saber) to `2` (LightSaber).

**Why:** SABER is a single configurable reference implementation; the
parameter that selects between the three security levels (LightSaber / Saber /
FireSaber) is a `#define SABER_L N` at the top of `SABER_params.h`. The
upstream default is `SABER_L = 3` (Saber, NIST Category 3). The benchmark's
`sources.txt` specifies LightSaber (Category 1) as the smallest safe
parameter set, so the patch flips the commented/uncommented lines to select
`SABER_L = 2` instead. A `-DSABER_L=2` compile flag cannot do this because
the default is set via an unguarded `#define` rather than an `#ifndef`.
