/* Empty stub for the Windows-only <tchar.h> header.
 *
 * The Twister reference implementation (ref_twister.cpp) unconditionally
 * does `#include <tchar.h>` but never actually uses any TCHAR symbols.
 * On Linux that header does not exist, so build_cli.sh copies this file to
 * `tchar.h` in the build directory (resolved via -I.) to satisfy the
 * include without modifying the upstream source.
 */
