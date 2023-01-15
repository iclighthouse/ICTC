import Fp "./Fp";

module {
  public type Curve = {
    p : Nat;
    // Order (number of points on the curve)
    r : Nat;
    // a and b from  y^2 = x^3 + ax + b
    a : Nat;
    b : Nat;
    // Generator point
    gx : Nat;
    gy : Nat;
    Fp : (Nat) -> Fp.Fp;
  };

  public let secp256k1 : Curve = {
    p = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f;
    r = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141;
    a = 0;
    b = 7;
    gx = 0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798;
    gy = 0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8;
    Fp = func (value : Nat) : Fp.Fp {
      return Fp.Fp(value, secp256k1.p);
    }; 
  };

  public func isEqual(curve1 : Curve, curve2 : Curve) : Bool {
    return curve1.p == curve2.p and curve1.a == curve2.a and
      curve1.b == curve2.b and curve1.gx == curve2.gx and
      curve1.gy == curve2.gy;
  };
};
