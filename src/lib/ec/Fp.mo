import P "mo:base/Prelude";
import Field "./Field";

module {
  // Arithmetic computations modulo n over the given _value.
  public class Fp(_value : Nat, n : Nat) : Fp {
    public let value : Nat = _value % n;

    // Compute value ** -1 mod n. The inverse does not exist if _value and n are
    // not relatively prime.
    public func inverse() : Fp {
      let inverse : ?Nat = Field.inverse(value, n);
      switch inverse {
        case (null) {
          P.unreachable();
        };
        case (?inverse) {
          return Fp(inverse, n);
        };
      };
    };

    // Compute value + other mod n.
    public func add(other: Fp) : Fp = Fp(Field.add(value, other.value, n), n);

    // Compute value * other mod n.
    public func mul(other : Fp) : Fp = Fp(Field.mul(value, other.value, n), n);

    // Compute value * 2 mod n.
    public func sqr() : Fp = Fp(Field.mul(value, value, n), n);

    // Compute value - other mod n.
    public func sub(other: Fp) : Fp = Fp(Field.sub(value, other.value, n), n);

    // Compute -value mod n.
    public func neg() : Fp = Fp(Field.neg(value, n), n);

    // Check equality with the given Fp object.
    public func isEqual(other : Fp) : Bool = other.value == value;

    // Compute value ** other mod n.
    public func pow(exponent: Nat) : Fp = Fp(Field.pow(value, exponent, n), n);

    // Compute sqrt(value) mod n.
    public func sqrt() : Fp {
      return Fp(Field.pow(value, (n + 1) / 4, n), n);
    };
  };
};
