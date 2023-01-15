import Numbers "./Numbers";
import Int "mo:base/Int";
import Iter "mo:base/Iter";

module {
  // Compute a ** -1 mod n.
  public func inverse(a : Nat, n : Nat) : ?Nat {
    let (gcd, x, _) = Numbers.eea(a, n);

    return if (gcd != 1) {
      null
    } else {
      let inverse = if (x < 0) x + n else x;
      ?Int.abs(inverse);
    };
  };

  // Compute a**b mod n.
  public func pow(a : Nat, b : Nat, n : Nat) : Nat {
    if (b == 0) {
      return 1;
    };

    let reversedBits = Numbers.toBinaryReversed(b);
    var result : Nat = 1;

    for (i in Iter.revRange(reversedBits.size() - 1, 0)) {
      result :=  mul(result, result, n);

      if (reversedBits[Int.abs(i)]) {
        result := mul(result, a, n);
      };
    };
    return result;
  };

  // Compute a + b  mod n.
  public func add(a : Nat, b : Nat, n : Nat) : Nat {
    let sum = a + b;

    return if (sum < n) {
      sum;
    } else {
      sum - n;
    }
  };

  // Compute a * b  mod n.
  public func mul(a : Nat, b : Nat, n : Nat) : Nat {
    return (a * b) % n;
  };

  // Compute a - b  mod n.
  public func sub(a : Nat, b : Nat, n : Nat) : Nat {
    return if (a >= b) {
      a - b ;
    } else {
      a + n - b;
    }
  };

  // Compute -a  mod n.
  public func neg(a : Nat, n : Nat) : Nat {
    return if (a == 0) {
      0;
    } else {
      n - a;
    };
  };
};
