from sage.all import GF, matrix, vector, save, load, gcd
from random import randrange

import os
import sys
import hashlib

# [T1_aimer compatibility patch] Track whether the optional Rust extension
# `ff_rust` is available. Upstream always builds it, so it defines the
# `AIM2_*_Rust` classes unconditionally; their `__init_subclass__` dereferences
# `ff_rust` at *class-definition* time, which raises NameError when only the
# pure-SageMath attack is used. We gate the Rust-only class definitions on this
# flag (see the matching patch lower down). Pure-Sage code uses AIM2_*_Sage and
# is unaffected. Only change vs upstream commit
# 5a372f43476a8afe74322a264723c658c883db8a.
try:
    import ff_rust

    _HAVE_FF_RUST = True
except ImportError:
    _HAVE_FF_RUST = False


_MASK64 = (1 << 64) - 1


class AIM2:
    n = NotImplemented
    nb = NotImplemented  # num bytes
    nw = NotImplemented  # num 64-bit words
    ell = NotImplemented
    es = NotImplemented  # Mersenne exponents
    ds = NotImplemented  # inverse exponents
    cs = NotImplemented  # constants
    field_implementation = NotImplemented
    _constants_words = NotImplemented
    _modulus_exps = NotImplemented
    _basis_change_bits_to_linearized = None

    @classmethod
    def custom_instance(cls, n, ell, es=None, cs=None):
        if cls.field_implementation == "ff_rust":
            if n not in (16, 32, 64, 128, 192, 256):
                raise ValueError(
                    "n=%d not supported, only (16, 32, 64, 128, 192, 256)" % n
                )
            F = getattr(ff_rust, "GF%dField" % n)()
            _modulus_exps = [i for i, b in enumerate(F.modulus_bits()) if b]
        elif cls.field_implementation == "sage":
            try:
                Fr = getattr(ff_rust, "GF%dField" % n)()

                _modulus_exps = [i for i, b in enumerate(Fr.modulus_bits()) if b]
                x = GF(2)["x"].gen()
                modulus = sum(x**i for i in _modulus_exps)
                F = GF(2**n, name="α", modulus=modulus)
            except Exception:
                F = GF(2**n, name="α", modulus=modulus)
                _modulus_exps = [i for i, b in enumerate(F.modulus()) if b]
        else:
            raise ValueError(
                "field implementation %s unsupported" % cls.field_implementation
            )

        if es is None:
            es = []
            while len(es) < ell + 1:
                e = randrange(2, n)
                if gcd(2**e - 1, 2**n - 1) == 1:
                    es.append(e)
        assert len(es) == ell + 1

        if cs is None:
            cs = [F.from_integer(randrange(2**n)) for _ in range(ell)]
        assert len(cs) == ell

        AIM2_Custom = type(
            "AIM2_Custom",
            (cls,),
            dict(
                n=n,
                ell=ell,
                es=es,
                cs=cs,
                _modulus_exps=_modulus_exps,
            ),
        )
        return AIM2_Custom

    def __init_subclass__(cls):
        if cls.n is NotImplemented or cls.field_implementation is NotImplemented:
            return
        assert cls.n % 8 == 0
        # assert cls.n % 64 == 0
        cls.nb = cls.n // 8
        cls.nw = (cls.n + 63) // 64
        x = GF(2)["x"].gen()
        modulus = sum(x**i for i in cls._modulus_exps)
        if cls.field_implementation == "sage":
            cls.F = GF(2**cls.n, modulus=modulus, name="α")
            cls.Fsage = cls.F
        elif cls.field_implementation == "ff_rust":
            cls.F = getattr(ff_rust, "GF%dField" % cls.n)()
            cls.Fsage = GF(2**cls.n, modulus=modulus, name="α")
            assert cls.F.modulus_bits() == list(modulus)
        else:
            raise ValueError(
                "Unknown field implementat`ion: %s" % cls.field_implementation
            )

        cls.ds = tuple(pow(2**e - 1, -1, 2**cls.n - 1) for e in cls.es)
        if cls.cs is NotImplemented:
            cls.cs = tuple(cls.words_to_gf(ws) for ws in cls._constants_words)

    def __init__(self, iv=None, lin=None, es=None, cs=None):
        if lin is None:
            if iv is None:
                iv = os.urandom(self.nb)
            self.iv = bytes(iv)
            self.LIN_Ls, self.LIN_Us, self.LIN_const = self.generate_matrices_L_and_U(
                self.iv
            )
            self.LIN_mats = [
                self.compose_matrices(self.LIN_Us[i], self.LIN_Ls[i])
                for i in range(self.ell)
            ]
        elif iv is None:
            *self.LIN_mats, self.LIN_const = lin
        else:
            raise ValueError("only one of iv, mats can be given")

        if es is not None:
            self.es = tuple(map(int, es))
        if cs is not None:
            self.cs = tuple(self.F.from_integer(int(v)) for v in cs)

        self._LIN_polys = None

    def with_affine_shift(self, a, b):
        """Return instance with constants replaced by a*γ+b, linear layer modified accordingly, ."""
        assert self.ell == 2
        cs = [a * c + b for c in self.cs]
        pre_scale0 = (self.F(1) / a) ** self.ds[0]
        pre_scale1 = (self.F(1) / a) ** self.ds[1]
        post_scale = a ** self.ds[-1]
        mat_pre_scale0 = self.matrix_scale_mul(pre_scale0)
        mat_pre_scale1 = self.matrix_scale_mul(pre_scale1)
        mat_post_scale = self.matrix_scale_mul(post_scale)
        lin = [
            self.compose_matrices(
                self.compose_matrices(mat_pre_scale0, self.LIN_mats[0]), mat_post_scale
            ),
            self.compose_matrices(
                self.compose_matrices(mat_pre_scale1, self.LIN_mats[1]), mat_post_scale
            ),
            post_scale * self.LIN_const,
        ]
        return type(self)(iv=None, lin=lin, es=self.es, cs=cs)

    def with_squaring(self, e):
        assert self.cs == (0, 1)  # not supported (no need for)
        cs = self.cs
        sqr = self.matrix_square(e)
        isqr = self.matrix_square(self.n - e)
        lin = [
            self.compose_matrices(self.compose_matrices(sqr, self.LIN_mats[0]), isqr),
            self.compose_matrices(self.compose_matrices(sqr, self.LIN_mats[1]), isqr),
            self.LIN_const ** (2 ** (self.n - e)),
        ]
        return type(self)(iv=None, lin=lin, es=self.es, cs=cs)

    @classmethod
    def matrix_scale_mul(cls, a):
        a = cls.F(a)
        two = cls.F(2)
        mat = [a]
        for _ in range(cls.n - 1):
            a *= two
            mat.append(a)
        return mat

    @classmethod
    def matrix_square(cls, e=1):
        mat = []
        for i in range(cls.n):
            x = cls.F(1 << i)
            y = x ** (2**e)
            mat.append(y)
        return mat

    @property
    def LIN_polys(self):
        if self._LIN_polys is None:
            self._LIN_polys = tuple(
                self.matrix_to_linearized(mat) for mat in self.LIN_mats
            )
        return self._LIN_polys

    @staticmethod
    def words_to_int(words):
        res = 0
        for w in reversed(words):
            res = (res << 64) | w
        return res

    @classmethod
    def words_to_gf(cls, words):
        return cls.F.from_integer(cls.words_to_int(words))

    @classmethod
    def gf_from_bytes(cls, b):
        if len(b) * 8 != cls.n:
            raise ValueError("%d bytes != %d bits" % (len(b), cls.n))
        return cls.F.from_integer(int.from_bytes(b, "little"))

    @classmethod
    def gf_to_bytes(cls, g):
        return g.to_integer().to_bytes(cls.nb, "little")

    @classmethod
    def generate_matrices_L_and_U(cls, iv: bytes = None):
        shake = hashlib.shake_128() if cls.n <= 128 else hashlib.shake_256()
        shake.update(iv)
        total_bytes = (cls.ell * cls.n + 1) * cls.nb
        stream = shake.digest(total_bytes)
        offset = 0

        matrix_L = [[None] * cls.n for _ in range(cls.ell)]
        matrix_U = [[None] * cls.n for _ in range(cls.ell)]

        Lw = [0] * cls.nw
        Uw = [0] * cls.nw
        for num in range(cls.ell):
            for row in range(cls.n):
                buf = stream[offset : offset + cls.nb]
                offset += cls.nb

                g = [
                    int.from_bytes(buf[i : i + 8], "little")
                    for i in range(0, len(buf), 8)
                ]

                ormask = 1 << (row & 63)
                lmask = (_MASK64 << (row & 63)) & _MASK64
                umask = _MASK64 ^ lmask

                inter = row >> 6

                for col_word in range(inter):
                    Lw[col_word] = 0
                    Uw[col_word] = g[col_word]

                Lw[inter] = (g[inter] & lmask) | ormask
                Uw[inter] = (g[inter] & umask) | ormask

                for col_word in range(inter + 1, cls.nw):
                    Lw[col_word] = g[col_word]
                    Uw[col_word] = 0

                matrix_L[num][row] = cls.words_to_gf(Lw)
                matrix_U[num][row] = cls.words_to_gf(Uw)

        assert len(stream[offset:]) == cls.nb
        vector_b = cls.gf_from_bytes(stream[offset : offset + cls.nb])
        return matrix_L, matrix_U, vector_b

    @classmethod
    def compose_matrices(cls, a_rows, b_rows):
        return [cls.transposed_matmul(a_rows[i], b_rows) for i in range(cls.n)]

    @classmethod
    def transposed_matmul(cls, a, matrix_rows):
        a_int = a.to_integer()
        acc = cls.F(0)
        for i in range(cls.n):
            if (a_int >> i) & 1:
                acc += matrix_rows[i]
        return acc

    @classmethod
    def matrix_to_linearized(cls, matrix_rows):
        # Given images of basis elements (bit i -> matrix_rows[i]),
        # return coefficients c_i for L(x) = sum_i c_i * x^(2^i).
        if cls._basis_change_bits_to_linearized is None:
            cache_filename = ".cache.%s.basis_change_bits_to_linearized.n%d" % (
                cls.field_implementation,
                cls.n,
            )
            try:
                mat = load(cache_filename)
                mat = [cls.Fsage.from_integer(v) for v in mat]
                mat = matrix(cls.Fsage, cls.n, cls.n, mat)
            except IOError:
                print("Precomputing cache of basis change, n=%d" % cls.n)
                basis = [cls.Fsage.from_integer(1 << i) for i in range(cls.n)]
                M = matrix(cls.Fsage, cls.n, cls.n)  # , lambda r, c: basis[r]**(2**c))
                for r in range(cls.n):
                    M[r, 0] = basis[r]
                    for c in range(1, cls.n):
                        M[r, c] = M[r, c - 1] ** 2
                mat = ~M
                save([v.to_integer() for v in mat.list()], cache_filename)
            cls._basis_change_bits_to_linearized = mat
        if cls.field_implementation != "sage":
            matrix_rows = [cls.Fsage.from_integer(v.to_integer()) for v in matrix_rows]
        coeffs = cls._basis_change_bits_to_linearized * vector(cls.Fsage, matrix_rows)
        if cls.field_implementation != "sage":
            coeffs = [cls.F.from_integer(v.to_integer()) for v in coeffs]
        return list(coeffs)

    @classmethod
    def apply_linearized(cls, x, coeffs):
        acc = cls.F(0)
        xsq = x
        for i, c in enumerate(coeffs):
            if c:
                # acc += c * x**(2**i)
                acc += c * xsq
            xsq = xsq**2
        return acc

    def eval(self, pt: bytes, as_bytes=True):
        if isinstance(pt, bytes):
            if len(pt) != self.nb:
                raise ValueError("plaintext must be %d bytes" % self.nb)

            pt = self.gf_from_bytes(pt)
        else:
            pt = self.F(pt)

        state = [pt + const for const in self.cs]
        state = [s**exp for s, exp in zip(state, self.ds[:-1])]

        # state = [self.transposed_matmul(s, mat) for s, mat in zip(state, self.LIN_Us)]
        # state = [self.transposed_matmul(s, mat) for s, mat in zip(state, self.LIN_Ls)]
        state = [self.transposed_matmul(s, mat) for s, mat in zip(state, self.LIN_mats)]
        state = sum(state) + self.LIN_const

        state = state ** (2 ** self.es[-1] - 1)

        ct = state + pt
        if as_bytes:
            return self.gf_to_bytes(ct)
        return ct


class AIM2_Sage(AIM2):
    BY_N = {}
    field_implementation = "sage"


class AIM2_Rust(AIM2):
    BY_N = {}
    field_implementation = "ff_rust"


class AIM2_128(AIM2):
    n = 128
    ell = 2
    es = (49, 91, 3)
    _constants_words = (
        (0x13198A2E03707344, 0x243F6A8885A308D3),
        (0x082EFA98EC4E6C89, 0xA4093822299F31D0),
    )
    _modulus_exps = (0, 1, 2, 7, 128)


class AIM2_192(AIM2):
    n = 192
    ell = 2
    es = (17, 47, 5)
    _constants_words = (
        (0xC0AC29B7C97C50DD, 0xBE5466CF34E90C6C, 0x452821E638D01377),
        (0xD1310BA698DFB5AC, 0x9216D5D98979FB1B, 0x3F84D5B5B5470917),
    )
    _modulus_exps = (0, 1, 2, 7, 192)


class AIM2_256(AIM2):
    n = 256
    ell = 3
    es = (11, 141, 7, 3)
    _constants_words = (
        (
            0x24A19947B3916CF7,
            0xBA7C9045F12C7F99,
            0xB8E1AFED6A267E96,
            0x2FFD72DBD01ADFB7,
        ),
        (
            0x0D95748F728EB658,
            0xA458FEA3F4933D7E,
            0x636920D871574E69,
            0x0801F2E2858EFC16,
        ),
        (
            0xC5D1B023286085F0,
            0x9C30D5392AF26013,
            0x7B54A41DC25A59B5,
            0x718BCD5882154AEE,
        ),
    )
    _modulus_exps = (0, 2, 5, 10, 256)


# [T1_aimer compatibility patch] Rust-only classes are defined only when the
# optional ff_rust extension is importable (see top-of-file patch).
if _HAVE_FF_RUST:

    class AIM2_128_Rust(AIM2_128, AIM2_Rust):
        pass

    class AIM2_192_Rust(AIM2_192, AIM2_Rust):
        pass

    class AIM2_256_Rust(AIM2_256, AIM2_Rust):
        pass


class AIM2_128_Sage(AIM2_128, AIM2_Sage):
    pass


class AIM2_192_Sage(AIM2_192, AIM2_Sage):
    pass


class AIM2_256_Sage(AIM2_256, AIM2_Sage):
    pass


if _HAVE_FF_RUST:
    AIM2_Rust.BY_N[128] = AIM2_128_Rust
    AIM2_Rust.BY_N[192] = AIM2_192_Rust
    AIM2_Rust.BY_N[256] = AIM2_256_Rust

AIM2_Sage.BY_N[128] = AIM2_128_Sage
AIM2_Sage.BY_N[192] = AIM2_192_Sage
AIM2_Sage.BY_N[256] = AIM2_256_Sage


def parse_keypairs_file(path):
    text = open(path).read().splitlines()
    sk = None
    ivs = []
    pks = []
    for line in text:
        line = line.strip()
        if not line:
            continue
        if line.startswith("sk = "):
            sk = bytes.fromhex(line.split("sk = ", 1)[1])
        elif line.startswith("iv = "):
            ivs.append(bytes.fromhex(line.split("iv = ", 1)[1]))
        elif line.startswith("pk = "):
            pks.append(bytes.fromhex(line.split("pk = ", 1)[1]))

    if sk is None:
        sk = b"\x00" * len(pks[0])
    if len(ivs) != len(pks):
        raise ValueError("Mismatched iv/pk count.")

    return sk, list(zip(ivs, pks))


def test_scale_mul_mat():
    A = AIM2_128_Rust()
    a = A.F.random_element()
    b = A.F.random_element()

    mat_scale = A.matrix_scale_mul(a)
    assert A.transposed_matmul(b, mat_scale) == a * b


def test_affine_shift():
    A = AIM2_128_Rust()
    a = A.F.random_element()
    b = A.F.random_element()

    A2 = A.with_affine_shift(a, b)

    x = A.F.random_element()
    y = A.eval(x, as_bytes=False)

    x2 = a * x + b
    y2 = a * y + b
    y2test = A2.eval(x2, as_bytes=False)
    assert y2 == y2test

    # force 0, 1
    a = A.F(1) / (A.cs[0] + A.cs[1])
    b = a * A.cs[0]

    A2 = A.with_affine_shift(a, b)
    assert A2.cs[0] == 0
    assert A2.cs[1] == 1

    x = A.F.random_element()
    y = A.eval(x, as_bytes=False)

    x2 = a * x + b
    y2 = a * y + b
    y2test = A2.eval(x2, as_bytes=False)
    assert y2 == y2test

    # test squaring
    e = 19
    A2s = A2.with_squaring(e=e)
    x2 = x ** (2**e)
    y2 = A2.eval(x2, as_bytes=False)  # ci

    y2test = A2s.eval(x, as_bytes=False)
    assert y2 ** (2 ** (A.n - e)) == y2test

    print("Affine shift & squaring ok")


def test_related_key():
    A = AIM2_128_Rust()
    a = A.F(1) / (A.cs[0] + A.cs[1])
    b = a * A.cs[0]

    A2 = A.with_affine_shift(a, b)
    assert A2.cs[0] == 0
    assert A2.cs[1] == 1

    sk_orig = A.F.random_element()

    sk = a * sk_orig + b
    for i in range(A.n):
        # original cipher, related key to be requested
        sk_i = ((a * sk_orig + b) ** (2**i) - b) / a
        ct_i = A.eval(sk_i, as_bytes=False)  # query result

        # custom cipher, having the same sk as the input
        # (but different linear layer / ct)
        # ct can be computed from the query above
        A2s = A2.with_squaring(i)
        ct = A2s.eval(sk, as_bytes=False)
        test = (a * ct_i + b) ** (2 ** (A.n - i))
        assert ct == test

    print("Related key test ok")


if __name__ == "__main__":
    test_scale_mul_mat()
    test_affine_shift()
    test_related_key()

    iv = b"abcd"
    AIM2_128_Sage().generate_matrices_L_and_U(iv)
    AIM2_192_Sage().generate_matrices_L_and_U(iv)
    AIM2_256_Sage().generate_matrices_L_and_U(iv)

    AIM2_128_Rust().generate_matrices_L_and_U(iv)
    AIM2_192_Rust().generate_matrices_L_and_U(iv)
    AIM2_256_Rust().generate_matrices_L_and_U(iv)

    AIM2_Rust.custom_instance(n=64, ell=5).generate_matrices_L_and_U(iv)

    if len(sys.argv) > 1:
        sk, pairs = parse_keypairs_file(sys.argv[1])
        print(f"sk {sk.hex()}")

        for idx, (iv, pk_expected) in enumerate(pairs, 1):
            if len(sk) == 16:
                A = AIM2_128_Sage(iv)
            elif len(sk) == 24:
                A = AIM2_192_Sage(iv)
            elif len(sk) == 32:
                A = AIM2_256_Sage(iv)
            pk = A.eval(sk)
            if pk != pk_expected:
                print(f"Mismatch Sage #{idx}:")
                print(f"  iv = {iv.hex()}")
                print(f"  expected pk = {pk_expected.hex()}")
                print(f"  computed pk = {pk.hex()}")
                print()
            A.LIN_polys

            if len(sk) == 16:
                A = AIM2_128_Rust(iv)
            elif len(sk) == 24:
                A = AIM2_192_Rust(iv)
            elif len(sk) == 32:
                A = AIM2_256_Rust(iv)
            pk = A.eval(sk)
            if pk != pk_expected:
                print(f"Mismatch Rust #{idx}:")
                print(f"  iv = {iv.hex()}")
                print(f"  expected pk = {pk_expected.hex()}")
                print(f"  computed pk = {pk.hex()}")
                print()

            A.LIN_polys

        print("Verification finished")
