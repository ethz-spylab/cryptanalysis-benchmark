/******************************************************************
 ** C-linkage wrapper around the Twister reference implementation.
 **
 ** The upstream reference code (ref_twister.cpp / ref_twister.h) is C++
 ** and defines the NIST API (Init/Update/Final/Hash) with C++ linkage.
 ** Our generic SHA-3 cli.c is plain C and calls a C-linkage `Hash`
 ** symbol with the standard NIST prototype
 **   HashReturn Hash(int, const BitSequence*, DataLength, BitSequence*)
 ** where DataLength == unsigned long long.
 **
 ** This translation unit bridges the two: it includes the upstream header
 ** to reuse Init/Update/Final, and re-exports an `extern "C" Hash` whose
 ** parameter/return types match cli.c's C declaration exactly so the C
 ** object links cleanly. Upstream sources are left untouched.
 *******************************************************************/

#include "ref_twister.h"

/* Standard NIST C-API types as seen by cli.c (plain C). These mirror the
 * fallback declarations in cli.c (DataLength == unsigned long long). */
extern "C" {

typedef unsigned char C_BitSequence;
typedef unsigned long long C_DataLength;
typedef enum { C_SUCCESS = 0, C_FAIL = 1, C_BAD_HASHBITLEN = 2 } C_HashReturn;

C_HashReturn Hash(int hashbitlen, const C_BitSequence *data,
                  C_DataLength databitlen, C_BitSequence *hashval) {
  hashState state;
  HashReturn r;

  if ((r = Init(&state, hashbitlen)) != SUCCESS)
    return (C_HashReturn)r;
  if ((r = Update(&state, (const BitSequence *)data,
                  (DataLength)databitlen)) != SUCCESS)
    return (C_HashReturn)r;
  Final(&state, (BitSequence *)hashval);

  return C_SUCCESS;
}

} /* extern "C" */
