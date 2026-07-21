# Algorithm Source Directory

## Overview

This directory contains the implementation of your cryptographic algorithm. The code should be structured as a command-line interface (CLI) tool that exposes specific commands for interacting with the algorithm.

## Before writing a new `cli.c` — check for a reusable one

Writing `cli.c` from scratch is almost never the right first step. Many existing algorithms in the sibling folders already expose the exact command set you need, and for some scheme types the `cli.c` is **identical across every algorithm of that type** they are true drop-in templates where only `build_cli.sh`, the upstream source, and per-task headers differ.

### Reference `cli.c` implementations by scheme type

- **Symmetric block cipher** — `generate_secrets` / `generate_random_plaintext` / `encrypt` / `decrypt` with a single key plus block-sized plaintext/ciphertext. Each file is bespoke to its upstream API:
  - `C3_aes` — AES-128 ECB, 128-bit key, 16-byte block
  - `C0_feal4` — FEAL-4, legacy 64-bit block
  - `C3_simon` — Simon 64/96
  - `C3_speck` — Speck 64/96
  - `C3_skinny` — Skinny-64-64
  - `C3_katan` — KATAN32
- **Symmetric stream cipher** — key + IV; `encrypt` emits a random IV alongside the ciphertext, `decrypt` takes key/iv/ciphertext:
  - `C3_chacha` — ChaCha8-128 (128-bit key, 64-bit IV)
- **AEAD** — key + public nonce + associated data + tag; `encrypt` returns ciphertext-with-tag, `decrypt` verifies the tag. **All 9 AEAD tasks share a byte-identical `cli.c`** that calls the standard `crypto_aead_encrypt` / `crypto_aead_decrypt` API with per-task sizes from `crypto_aead.h` — true drop-in template, just swap the upstream reference folder:
  - Canonical copy: `C0_cilipadi`
  - Also used by: `C0_clae`, `C0_flexaead`, `C0_hern_heron`, `C0_limdolen`, `C0_simple`, `C0_sneik`, `C0_sycon`, `C0_triad`
- **Hash function** — `generate_secrets` is a no-op; `hash` with optional `--hashbitlen`. **All 9 hash tasks share a byte-identical `cli.c`** built around the NIST SHA-3 candidate API (`Hash(hashbitlen, data, databitlen, hashval)`); the scheme-specific header is injected via the compiler's `-include` flag in `build_cli.sh`, so `cli.c` itself doesn't know which algorithm it's built with — true drop-in template:
  - Canonical copy: `C0_sgail`
  - Also used by: `C0_dch`, `C0_dynamicsha2`, `C0_enrupt`, `C0_khichidi`, `C0_shamata`, `C0_spectral_hash`, `C0_tangle`, `C0_wamm`
- **KEM** — `generate_secrets` returns a keypair; `encapsulate`/`decapsulate` exchange a shared secret. Each is bespoke to its upstream API (no shared template):
  - `C0_rvb` — RVB, lattice-based
  - `C0_hila5` — HILA5, ring-LWE
  - `C0_sike` — SIKE, supersingular-isogeny
  - `C0_edon_k` — Edon-K
  - `C0_big_quake` — BIG QUAKE, code-based
  - `C0_round2` — Round2, lattice-based
- **Public-key encryption** — `generate_secrets` returns a keypair; `encrypt` takes a public key + plaintext, `decrypt` takes a private key + ciphertext (no shared secret, no tag):
  - `C0_srtpi` — SRTPI (24-byte plaintext)
  - `C0_guess_again` — GuessAgain, code-based (encrypt needs `libraryF.bin` / `libraryG.bin` alongside the binary at runtime)
- **Digital signature** — `generate_secrets` returns a keypair; `sign` takes private key + message, `verify` takes public key + message + signature:
  - `C0_racoss` — RACOSS

Regardless of scheme type, every `cli.c` reuses the shared header-only helper [`cli_stdin.h`](../../../C3_aes/environment/algorithm_src/cli_stdin.h) (for parsing `key: value` stdin blocks and batch mode). You can copy it verbatim from any existing algorithm.

## Required Structure

### Main Entry Point

The folder must contain a `build_cli.sh` script that is used to compile the CLI tool.

### Building

The cli tool is being compiled using the command:

`./build_cli.sh`

and should produce a binary called `cli`.

### Required Commands

The following commands **MUST** be implemented:

#### 1. `generate_secrets`

Generate all secrets (keys, salts, etc.) required by your cryptographic algorithm. The output is a list of `key: value` pairs where all values should be binary numbers in hexadecimal format.

**Example:**
```bash
$ ./cli generate_secrets
private_key: 0x123456789abcdef0fedcba9876543210abcdef0123456789 #gitleaks:allow
public_key: 0x123456789abcdef #gitleaks:allow
```

**Note:** Make sure to use a cryptographically secure source of randomness such as `/dev/urandom`.

#### 2. `generate_random_plaintext`

Generate a single random plaintext/input data for the algorithm. The output must use the `key: value` format. Supports batch mode.

**Example (single):**
```bash
$ ./cli generate_random_plaintext
plaintext: 0x0123456789abcdef
```

**Example (batch):**
```bash
$ ./cli generate_random_plaintext --batch --count=3
plaintext: 0x0123456789abcdef
---
plaintext: 0xfedcba9876543210
---
plaintext: 0xdeadbeefcafebabe
```

**Note:** Make sure to use a cryptographically secure source of randomness such as `/dev/urandom`. This is because some security games might generate random plaintext for evaluation, so it shouldn't be gameable.

### Optional Commands

All remaining commands are **OPTIONAL** and depend on the specific cryptographic algorithm that is being implemented (encryption / hashing / signing). The following commands are currently supported:

#### 3. `encrypt`

Perform the cryptographic operation (encryption, hashing, etc.) on input data. Arguments are passed via stdin as `key: value` lines. Supports batch mode with `---`-separated blocks.

**Example (single):**
```bash
$ printf 'key: 0xaabbccdd\nplaintext: 0x01020304\n' | ./cli encrypt
ciphertext: 0x9876543210fedcba
```

**Example (batch):**
```bash
$ printf 'key: 0xaabbccdd\nplaintext: 0x01020304\n---\nkey: 0xaabbccdd\nplaintext: 0x05060708\n' | ./cli encrypt --batch
ciphertext: 0x9876543210fedcba
---
ciphertext: 0xabcdef0123456789
```

#### 4. `decrypt`

Perform the inverse cryptographic operation (if applicable). Arguments are passed via stdin as `key: value` lines. Supports batch mode with `---`-separated blocks.

**Example (single):**
```bash
$ printf 'key: 0xaabbccdd\nciphertext: 0x9876543210fedcba\n' | ./cli decrypt
plaintext: 0x01020304
```

**Example (batch):**
```bash
$ printf 'key: 0xaabbccdd\nciphertext: 0x9876543210fedcba\n---\nkey: 0xaabbccdd\nciphertext: 0xabcdef0123456789\n' | ./cli decrypt --batch
plaintext: 0x01020304
---
plaintext: 0x05060708
```

#### 5. `--help`
The following command is optional but recommended:
```bash
$ ./cli --help
$ ./cli -h
```

## Input/Output Format

All commands use the same `key: value` format for both input and output:

- **Output** is printed to stdout as `key: value` lines (e.g., `ciphertext: 0xabc123`)
- **Input** (for `encrypt`, `decrypt`, etc.) is read from stdin as `key: value` lines
- **Batch mode** (`--batch` flag) accepts multiple queries separated by `---` lines on stdin, and produces `---`-separated output blocks on stdout
- **Batch generation** (`--batch --count=N`) produces N outputs separated by `---` lines
- All hex values should use a `0x` prefix
