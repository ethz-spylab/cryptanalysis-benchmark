/*
 * cli_stdin.h -- Header-only library for reading key:value arguments from stdin.
 *
 * Supports single-query mode (one block from stdin) and batch mode
 * (multiple blocks separated by "---" lines).
 *
 * All functions are static to avoid linker conflicts when included
 * in different translation units.
 */

#ifndef CLI_STDIN_H
#define CLI_STDIN_H

#define _POSIX_C_SOURCE 200809L
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STDIN_KV_MAX_ENTRIES 16
#define STDIN_KV_MAX_KEY_LEN 64

struct stdin_kv_entry {
  char key[STDIN_KV_MAX_KEY_LEN];
  char *value; /* dynamically allocated */
};

struct stdin_kv_block {
  struct stdin_kv_entry entries[STDIN_KV_MAX_ENTRIES];
  int count;
};

/* Strip trailing whitespace (newline, carriage return, spaces) in place. */
static void stdin_strip_trailing(char *s) {
  size_t len = strlen(s);
  while (len > 0 && (s[len - 1] == '\n' || s[len - 1] == '\r' ||
                      s[len - 1] == ' ' || s[len - 1] == '\t')) {
    s[--len] = '\0';
  }
}

/*
 * Read one key-value block from stdin until a "---" line or EOF.
 * Returns 1 if a block was read (at least one entry), 0 on EOF with no data.
 */
static int stdin_read_block(struct stdin_kv_block *block) {
  block->count = 0;

  char *line = NULL;
  size_t cap = 0;
  ssize_t len;

  while ((len = getline(&line, &cap, stdin)) != -1) {
    stdin_strip_trailing(line);

    /* Separator between blocks */
    if (strcmp(line, "---") == 0) {
      if (block->count > 0) {
        free(line);
        return 1;
      }
      /* Skip leading separators */
      continue;
    }

    /* Skip empty lines */
    if (line[0] == '\0') {
      continue;
    }

    /* Find the key/value separator (the first ':'). A single optional space
     * directly after the colon is consumed, so "key: value" and "key:value"
     * parse identically and "key:" yields an empty value. Empty values must
     * NOT be silently dropped: doing so previously let an empty-valued field
     * (e.g. `nonce:`) vanish, after which the CLI fell back to a randomly
     * generated default the caller never recorded. */
    char *sep = strchr(line, ':');
    if (!sep) {
      fprintf(stderr, "Warning: skipping malformed stdin line: %s\n", line);
      continue;
    }

    /* Hard-fail (rather than silently drop the overflow) when a block
     * exceeds the entry cap. Silent dropping let an adversary flood dummy
     * fields to push a real field past the cap, so the CLI operated on
     * different inputs than the caller recorded. */
    if (block->count >= STDIN_KV_MAX_ENTRIES) {
      fprintf(stderr, "Error: too many entries in stdin block (max %d)\n",
              STDIN_KV_MAX_ENTRIES);
      free(line);
      exit(EXIT_FAILURE);
    }

    struct stdin_kv_entry *entry = &block->entries[block->count];

    /* Copy key (up to separator) */
    size_t key_len = (size_t)(sep - line);
    if (key_len >= STDIN_KV_MAX_KEY_LEN) {
      key_len = STDIN_KV_MAX_KEY_LEN - 1;
    }
    memcpy(entry->key, line, key_len);
    entry->key[key_len] = '\0';

    /* Copy value (after the colon, skipping one optional leading space) */
    const char *val_start = sep + 1;
    if (*val_start == ' ') {
      val_start++;
    }
    entry->value = strdup(val_start);

    block->count++;
  }

  free(line);
  return block->count > 0 ? 1 : 0;
}

/* Look up a value by key name. Returns NULL if not found. */
static const char *stdin_kv_get(const struct stdin_kv_block *block,
                                const char *key) {
  for (int i = 0; i < block->count; i++) {
    if (strcmp(block->entries[i].key, key) == 0) {
      return block->entries[i].value;
    }
  }
  return NULL;
}

/* Free all dynamically allocated values in a block and reset count. */
static void stdin_kv_free(struct stdin_kv_block *block) {
  for (int i = 0; i < block->count; i++) {
    free(block->entries[i].value);
    block->entries[i].value = NULL;
  }
  block->count = 0;
}

#endif /* CLI_STDIN_H */
