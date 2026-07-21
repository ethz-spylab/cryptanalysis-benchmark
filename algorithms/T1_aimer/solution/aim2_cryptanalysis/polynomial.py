class PolynomialRing:
    """Custom multivariate polynomial ring implementation for finite fields.

    Args:
        base_ring: The coefficient ring (must be a field)
        names: Variable names as string or list
        exp_mod: Exponent modulus ("auto" uses field order-1, None for no reduction)
        order: Monomial ordering ("lex" or "degrevlex")
        _allow_exp_o1: If False, reduce x^(q-1) to 1 (assumes x≠0). If True, keep x^(q-1)
                      terms (allows x=0, uses field equation x^q=x instead of x^(q-1)=1)
    """

    def __init__(
        self, base_ring, names, exp_mod="auto", order="lex", _allow_exp_o1=False
    ):
        self._base_ring = base_ring
        self._order = order

        if exp_mod is None:
            self._exp_mod = None
        elif exp_mod == "auto":
            assert self._base_ring.is_field()
            try:
                order = int(self._base_ring.order())
                self._exp_mod = order - 1
            except (ValueError, TypeError):
                # Handle infinite fields (like QQ) by disabling exp_mod
                self._exp_mod = None
        else:
            self._exp_mod = int(exp_mod)
        self._allow_exp_o1 = _allow_exp_o1
        assert self._order in ("lex", "degrevlex"), "not supported"

        if isinstance(names, str):
            names = names.replace(" ", "")
            names = names.split(",")

        self._varnames = list(map(str, names))
        self._var2id = {name: id for id, name in enumerate(self._varnames)}
        self._gens = tuple(Variable(parent=self, name=name) for name in self._varnames)

    def gens(self):
        """Return generator variables as tuple."""
        return self._gens

    def nvars(self):
        """Return number of variables."""
        return len(self._gens)

    def base_ring(self):
        """Return the coefficient ring."""
        return self._base_ring

    def term_order(self):
        """Return the monomial ordering."""
        return self._order

    def to_var(self, v):
        if isinstance(v, str):
            return Variable(parent=self, name=v)
        elif isinstance(v, Variable):
            assert v.parent() == self
            return v
        else:
            return self._gens[int(v)]

    def __hash__(self):
        return hash(
            (self._base_ring.order(), self._varnames, self._exp_mod, self._order)
        )

    def __eq__(self, other):
        if self._base_ring != other._base_ring:
            return False
        if self._varnames != other._varnames:
            return False
        if self._exp_mod != other._exp_mod:
            return False
        if self._allow_exp_o1 != other._allow_exp_o1:
            return False
        return True

    def __call__(self, obj):
        if isinstance(obj, Variable):
            obj = obj.as_monomial()
        if isinstance(obj, Monomial):
            obj = obj.as_polynomial()
            return obj
        return Monomial(parent=self) * self._base_ring(obj)


class Variable:
    """A polynomial variable (indeterminate).

    Args:
        parent: The PolynomialRing this variable belongs to
        name: Variable name as string
    """

    def __init__(self, parent, name):
        self._parent = parent
        self._index = self._parent._var2id[name]

    def name(self):
        return self._parent._varnames[self._index]

    def index(self):
        return self._index

    def parent(self):
        return self._parent

    def as_monomial(self):
        degrees = [0] * self._parent.nvars()
        degrees[self.index()] = 1
        return Monomial(parent=self._parent, degrees=degrees)

    def __str__(self):
        return self.name()

    def __repr__(self):
        return self.name()

    def __hash__(self):
        return hash((self._parent, self._index))

    def __eq__(self, other):
        return self._parent == other._parent and self._index == other._index

    def __mul__(self, other):
        return self.as_monomial() * other

    def __rmul__(self, other):
        return other * self.as_monomial()

    def __add__(self, other):
        return self.as_monomial() + other

    def __radd__(self, other):
        return other + self.as_monomial()

    def __sub__(self, other):
        return self.as_monomial() - other

    def __rsub__(self, other):
        return other - self.as_monomial()

    def __neg__(self):
        return -(self.as_monomial())

    def __pow__(self, e):
        return self.as_monomial() ** e


class Monomial:
    """A monomial term in a polynomial ring.

    Args:
        parent: The PolynomialRing this monomial belongs to
        degrees: List of exponents for each variable
    """

    def __init__(self, parent, degrees=None):
        self._parent = parent
        if degrees:
            exp_mod = self._parent._exp_mod
            if exp_mod and self._parent._allow_exp_o1:
                # Keep x^{q-1} terms (allows x=0, uses field equation x^q = x)
                self._degrees = tuple(
                    int(d) % exp_mod if d == 0 or d % exp_mod else exp_mod
                    for d in degrees
                )
            elif exp_mod:
                # Reduce x^{q-1} to 1 (assumes x≠0, uses x^{q-1} = 1)
                self._degrees = tuple(int(d) % exp_mod for d in degrees)
            else:
                self._degrees = tuple(int(d) for d in degrees)
        else:
            self._degrees = tuple([0] * parent.nvars())

    def parent(self):
        return self._parent

    def base_ring(self):
        return self._parent.base_ring()

    def is_one(self):
        return all(val == 0 for val in self._degrees)

    def degree(self, var=None):
        if var:
            return self._degrees[self.parent().to_var(var).index()]
        return sum(self._degrees)

    def degrees(self):
        return self._degrees

    def __iter__(self):
        return iter(
            (self.parent()._gens[index], exp) for index, exp in enumerate(self._degrees)
        )

    def __str__(self):
        ves = []
        for var, exp in self:
            if exp == 0:
                continue
            if exp == 1:
                ves.append(f"{var}")
            else:
                ves.append(f"{var}^{exp}")
        if not ves:
            return "1"
        return "*".join(ves)

    __repr__ = __str__

    def __hash__(self):
        return hash(self._degrees)

    def __eq__(self, other):
        if isinstance(other, Variable):
            other = other.as_monomial()

        if isinstance(other, Monomial):
            return self._parent == other._parent and self._degrees == other._degrees

        if other == 1:
            return self.is_one()

        raise NotImplementedError()

    def __mul__(self, other):
        if isinstance(other, Variable):
            assert self.parent() == other.parent()
            other = other.as_monomial()
        if isinstance(other, Monomial):
            assert self.parent() == other.parent()
            degs = list(self._degrees)
            for index, exp in enumerate(other._degrees):
                degs[index] += exp
            return Monomial(degrees=degs, parent=self.parent())
        elif isinstance(other, Polynomial):
            assert self.parent() == other.parent()
            # return self.as_polynomial() * other
            ret = other._new()
            for coef, mono in other:
                ret._add_to(self * mono, coef)
            return ret
        else:
            const = self.parent().base_ring()(other)
            return Polynomial(poly={self: const}, parent=self.parent())

    __rmul__ = __mul__

    def __add__(self, other):
        return self.as_polynomial() + other

    def __radd__(self, other):
        return other + self.as_polynomial()

    def __sub__(self, other):
        return self.as_polynomial() - other

    def __rsub__(self, other):
        return other - self.as_polynomial()

    def __neg__(self):
        return -self.as_polynomial()

    def as_polynomial(self):
        return Polynomial(
            poly={self: self.parent().base_ring()(1)}, parent=self.parent()
        )

    def __lt__(self, other):
        if self.parent().term_order() == "lex":
            return self._degrees < other._degrees
        raise NotImplementedError()
        # for var in vars:
        #     d1 = self._degree.get(var, 0)
        #     d2 = other._degree.get(var, 0)
        #     if d1 < d2:
        #         return True
        #     if d1 > d2:
        #         return False
        # return False

    def __pow__(self, e):
        if e == 0:
            degs = [0] * self.parent().nvars()
        else:
            degs = [d * e for d in self._degrees]
        return Monomial(parent=self.parent(), degrees=degs)


class Polynomial:
    """A multivariate polynomial with finite field coefficients.

    Internally stores as {monomial: coefficient} dictionary.

    Args:
        poly: Dictionary mapping monomials to coefficients
        parent: The PolynomialRing this polynomial belongs to
    """

    def __init__(self, poly=None, parent=None):
        self._parent = parent
        if poly:
            self._poly = poly.copy()
        else:
            self._poly = {}

    def parent(self):
        return self._parent

    def base_ring(self):
        return self._parent.base_ring()

    @property
    def _zero(self):
        return self.base_ring()(0)

    @property
    def _one(self):
        return self.base_ring()(1)

    @property
    def _mono_one(self):
        return Monomial(parent=self.parent())

    @property
    def _char(self):
        return self.base_ring().characteristic()

    def _cleanup(self):
        for mon, coef in list(self._poly.items()):
            if coef == 0:
                del self._poly[mon]

    # @classmethod
    # def new_zero(cls, field):
    #     return Polynomial(poly={}, field=field)

    # @classmethod
    # def new_one(cls, field):
    #     return Polynomial(poly={Monomial(): field(1)}, field=field)

    # @classmethod
    # def new_const(cls, const, field):
    #     return Polynomial(poly={Monomial(): field(const)}, field=field)

    def _new(self):
        return Polynomial(parent=self.parent())

    def _copy(self):
        return Polynomial(poly=self._poly, parent=self.parent())

    def _add_to(self, mono, const):
        """Add constant to coefficient of monomial (internal method).

        Args:
            mono: Monomial to modify
            const: Coefficient to add
        """
        res = self._poly.pop(mono, self._zero) + const
        if res:
            self._poly[mono] = res

    def __add__(self, other):
        if isinstance(other, Variable):
            other = other.as_monomial()
        if isinstance(other, Monomial):
            ret = self._copy()
            ret._add_to(other, self._one)
            return ret
        if isinstance(other, Polynomial):
            ret = self._copy()
            for mon, coef in other._poly.items():
                ret._add_to(mon, coef)
            return ret
        if not isinstance(other, Polynomial):
            const = self.base_ring()(other)
            ret = self._copy()
            ret._add_to(self._mono_one, const)
            return ret

    __radd__ = __add__

    def __sub__(self, other):
        return self + -other

    def __rsub__(self, other):
        return other + -self

    def __neg__(self):
        if self._char == 2:
            return self
        ret = self._copy()
        for mon in self._poly:
            ret._poly[mon] = -ret._poly[mon]
        return ret

    def __mul__(self, other):
        if isinstance(other, Variable):
            other = other.as_monomial()
        if isinstance(other, Monomial):
            other = other.as_polynomial()

        if isinstance(other, Polynomial):
            ret = self._new()
            for mon1, coef1 in self._poly.items():
                for mon2, coef2 in other._poly.items():
                    mon12 = mon1 * mon2
                    # mon12.reduce()
                    ret._add_to(mon12, coef1 * coef2)
            return ret
        else:
            const = self.base_ring()(other)
            if const == 0:
                return self._new()
            if const == 1:
                return self
            ret = self._copy()
            for mon in self._poly:
                ret._poly[mon] *= const
            return ret

    __rmul__ = __mul__

    def __str__(self):
        terms = []
        for mon, coef in sorted(self._poly.items(), reverse=True):
            scoef = str(coef)
            if "+" in scoef or "-" in scoef:
                scoef = "(" + scoef + ")"

            if mon.is_one():
                terms.append(scoef)
            elif coef == 1:
                terms.append(str(mon))
            else:
                terms.append(scoef + "*" + str(mon))
        return " + ".join(terms) or "0"

    __repr__ = __str__

    def __pow__(self, e):
        if e == 0:
            return self._mono_one.as_polynomial()
        if e == 1:
            return self

        if self._char:
            n_char = 0
            while e % self._char == 0:
                n_char += 1
                e //= self._char

            if n_char:
                ret = self._new()
                char = self._char
                for mon, coef in self._poly.items():
                    for _ in range(n_char):
                        mon = mon**char
                        # mon.reduce()
                        coef = coef**char
                    ret._poly[mon] = coef
                self = ret

        if e == 1:
            return self

        if e < 0:
            raise NotImplementedError()
        assert e > 1

        ret = self._mono_one.as_polynomial()
        cur = self
        while e:
            if e & 1:
                ret = ret * cur
            cur = cur * cur
            e >>= 1
        return ret

    def __iter__(self):
        return iter((coef, mon) for mon, coef in self._poly.items())

    def __getitem__(self, mono):
        return self._poly.get(mono, self._zero)

    def __setitem__(self, mono, coef):
        self._poly[mono] = coef

    def __delitem__(self, mono):
        del self._poly[mono]

    def monomials(self):
        self._cleanup()
        return list(self._poly.keys())

    def degree(self, var=None):
        degs = [mono.degree() for mono in self.monomials()]
        return max(degs, default=-1)
