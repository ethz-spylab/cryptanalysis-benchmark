# Changes applied to upstream LAC

All changes are expressed as patch files under `patches/` and are applied by
`build_cli.sh` after the upstream repository is cloned. Each patch is listed
below with its purpose.

## `0001-select-lac128.patch`

**File touched:** `LAC-v3a/ref/lac_param.h`

**Change:** switch the active security-level macro from `LAC256` to
`LAC128`.

**Why:** LAC's v3a reference implementation carries parameters for three
security levels — `LAC_LIGHT`, `LAC128`, `LAC192`, `LAC256` — each gated by
an unguarded `#define <LEVEL>` at the top of `lac_param.h`. The upstream
default is `LAC256` (Category 5). Per the benchmark's `sources.txt`, we
want LAC128 (Category 1, the smallest safe set). Because the selector is an
unconditional `#define`, a compile-time `-D` flag cannot override it; an
in-tree edit is required.
