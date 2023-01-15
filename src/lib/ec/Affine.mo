import FpBase "./Fp";
import Curves "./Curves";
import Common "./Common";
import Array "mo:base/Array";

module {
  type Fp = FpBase.Fp;
  public type Point = {
    #infinity : Curves.Curve;
    #point : (Fp, Fp, Curves.Curve);
  };

  // Check if the given point is valid.
  public func isOnCurve(point: Point) : Bool {
    return switch point {
      case (#infinity (_)) {
        true;
      };
      case (#point (x, y, curve)) {
        x.pow(3).add(
          x.mul(
            curve.Fp(curve.a)
          )
        ).add(curve.Fp(curve.b)).isEqual(y.sqr())
      };
    };
  };

  // Check if the two given affine points are equal.
  public func isEqual(point1 : Point, point2 : Point) : Bool {
    return switch (point1, point2) {
      case (#infinity (curve1), #infinity (curve2)) {
        Curves.isEqual(curve1, curve2);
      };
      case (#point (x1, y1, curve1), #point (x2, y2, curve2)) {
        x1.isEqual(x2) and y1.isEqual(y2) and Curves.isEqual(curve1, curve2)
      };
      case _ {
        false;
      };
    };
  };

  // Deserialize given data into a point on the given curve. This supports
  // compressed and uncompressed SEC-1 formats.
  // Returns null if data is not in correct format, data size is not exactly
  // equal to the serialized point size, or if deserialized point is not on the
  // given curve.
  public func fromBytes(data : [Nat8], curve: Curves.Curve) : ?Point {
    let Fp = curve.Fp;

    // Min size
    if (data.size() < 33) {
      return null;
    };

    let x : Fp = Fp(Common.readBE256(data, 1));

    let point = if (data[0] == 0x04) {
      // Parse uncompressed point.
      if (data.size() != 65) {
        return null;
      };
      let y : Fp = Fp(Common.readBE256(data, 33));
      #point (x, y, curve);
    } else if (data[0] == 0x02 or data[0] == 0x03) {
      if (data.size() != 33) {
        return null;
      };

      // Parse compressed point.
      let even : Bool = data[0] == 0x02;

      // Calculate the right side of the equation y^2 = x^3 + 7.
      let alpha : Fp = x.pow(3).add(x.mul(Fp(curve.a))).add(Fp(curve.b));

      // Solve for left side.
      let beta :  Fp = alpha.sqrt();

      let (evenBeta, oddBeta) : (Fp, Fp) = if (beta.value % 2 == 0) {
        (beta, Fp(curve.p - beta.value));
      } else {
        (Fp(curve.p - beta.value), beta);
      };

      if (even) {
        #point (x, evenBeta, curve)
      } else {
        #point (x, oddBeta, curve)
      };
    } else {
      return null;
    };
    return if (isOnCurve(point)) {
      ?point
    } else {
      null
    };
  };

  // Serialize given point to bytes in SEC-1 format.
  public func toBytes(point : Point, compressed : Bool) : [Nat8] {
    switch point {
      case (#infinity (_)) {
        return [];
      };
      case (#point (x, y, _)) {
        return if (compressed) {
          let startByte : Nat8 = if (y.value % 2 == 0) 0x02 else 0x03;
          let output = Array.init<Nat8>(33, startByte);
          Common.writeBE256(output, 1, x.value);
          Array.freeze(output);
        } else {
          let output = Array.init<Nat8>(65, 0x04);
          Common.writeBE256(output, 1, x.value);
          Common.writeBE256(output, 33, y.value);
          Array.freeze(output);
        };
      };
    };
  };
};
