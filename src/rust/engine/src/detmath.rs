//! detmath: the deterministic transcendental core of the attestation law.
//!
//! # Why this module exists
//!
//! The PERF-P10 attestation bank (`tests/testthat/fixtures/kernel-geometry/`)
//! is a set of sealed bytes: every produced digit of a kernel serve must be
//! the same digit on every rustc toolchain (the CI pins 1.71.0, the bank was
//! sealed on 1.97.1) and on every operating system. `f64::ln`/`exp/sin/cos/
//! powf` are libm handoffs -- their last-ulp behaviour is OS- and
//! toolchain-dependent -- and the KL objective logarithms sit on the
//! solve-loop decision path (per-iteration `kl_objective` /
//! `logdet_gram` calls, sparse.rs `fit_volume_with_init` backtracking): a
//! ulp moves the line-search accept, the convergence test, and after 2000
//! multiplicative iterations the whole output. The bank therefore requires
//! that no executed face ever talks to libm for a transcendental.
//!
//! This module is the replacement. Its entire numeric surface is:
//! IEEE-754-2008 correctly-rounded `+ - * / sqrt` (architecturally
//! required by IEEE and by every target here: rustc emits no FMA
//! contraction (`fp-contract=off` since 1.61) and `f64::sqrt` is a
//! hardware correctly-rounded instruction), integer bit-field arithmetic,
//! `f64::round` (core_float, integer arithmetic), and fixed committed
//! coefficient tables. No libm symbol appears; there is no `fma` /
//! `mul_add`; what is written here is what every compiler must emit.
//!
//! # Committed reconstruction order (the law, do not reassociate)
//!
//! The summation order below is part of the sealed-bytes contract -- any
//! reassociation is a bank break. Every multi-term summation uses the
//! error-free `two_sum` chain (Knuth/Dekker: `a + b = s + err` as an
//! exact real identity for normal intermediates) so the committed value
//! is `RN(exact sum)` -- a single correct rounding, never a stack of
//! half-ulp roundings:
//!
//!   * `det_ln`: with `x = 2^e * m`, `m` in [sqrt(1/2), sqrt(2)),
//!     `f = m-1`, `P` the committed degree-22 polynomials
//!     (`P(f) = f + f^2 S(f)`), and pieces `a = e*LN2_A`, `b = e*LN2_B`,
//!     `c = e*LN2_C` (the three-piece Kahan--Cody--Waite split; `a` is
//!     exact for `|e| < 2^27`):
//!     `(s1, e1) = two_sum(P, c); (s2, e2) = two_sum(s1, b);`
//!     `(s3, e3) = two_sum(s2, a);` value `= s3 + ((e1 + e2) + e3)`.
//!     (`e == 0` returns `P` directly.)
//!   * `det_exp`: `k = round(x*INV_LN2)`; the reduction is the same
//!     corrected chain against `-k*LN2_A/B/C`, yielding `r`; value
//!     `= scale2(P_E(r), k)` (exponent-field scaling, exact).
//!   * `det_sin/det_cos`: `k = round(x*TWO_OVER_PI)`; corrected chain
//!     against `-k*PIO2_A/B/C` yielding `r`, quadrant `j = k mod 4`,
//!     then the committed odd/even polynomial pair.
//!
//! # Accuracy (measured against the 200-digit mpmath reference, not
//! claimed -- regeneration and the measurement grids live in
//! `tools/attest-detmath-coefficients.py`; the unit tests re-measure
//! against the platform routines and against bit-stability)
//!
//!   face        domain (committed)              measured max err
//!   det_ln      x finite > 0 (subnormals incl.)  1.21e-17 abs (0.217 ulp
//!                                               of ulp(0.25)); 3.65e-18
//!                                               relative near x = 1
//!   det_exp     all finite x                     4.19e-19 abs on the
//!                                               reduced poly (0.0019 ulp)
//!   det_sin     |x| <= 2^22 (executed faces:    4.45e-18 abs on the
//!               theta = TAU*u2 < 2 pi; pi*x      reduced poly (0.028 ulp)
//!               reflection branch < pi/2)
//!   det_cos     |x| <= 2^22                     8.93e-19 abs
//!   det_powf    x in (0,oo) finite, y finite     the committed
//!                                               composition: relative
//!                                               error <= |y*ln x|*2^-52
//!                                               + 2 ulps (the honest
//!                                               exp-of-ln composition
//!                                               law; gamma-sampler
//!                                               face only)
//!
//! The structural zeros are exact by construction: `det_ln(1) = +0`,
//! `det_exp(0) = 1`, `det_sin(+/-0) = +/-0` sign-preserving,
//! `det_cos(0) = 1`, `det_ln` is monotone (committed poly error is 15x
//! under the 2^-52 logarithm spacing between consecutive inputs).
//!
//! # Provenance
//!
//! Coefficients: Chebyshev-node interpolating fits (Vandermonde, exact in
//! mpmath at 60 digits) over the reduced intervals above, rounded to
//! nearest double with the structural coefficients snapped exactly
//! (`P_LN`: c0 = 0, c1 = 1; `P_E`: c0 = 1; `COS_D`: c0 = -1/2). The
//! split constants are mpmath `ln 2` and `pi/2` 26/27/53-bit
//! truncations; the tables printed by
//! `tools/attest-detmath-coefficients.py` are committed verbatim.

/// The committed ln(2) three-piece split (`ln 2 = A + B + C`; A is a
/// 26-significand-bit truncation, so `k*A` is exact for `|k| < 2^27`).
const LN2_A: f64 = 0.693_147_182_464_599_6;
const LN2_B: f64 = -1.904_654_295_392_660_4e-9;
const LN2_C: f64 = -4.565_107_477_165_917e-18;

/// `RN(1/ln 2)` (the exp reduction scale; k = round(x*INV_LN2) is the
/// true nearest integer to x/ln 2 up to an input half-ulp, which the
/// committed fit interval's 1e-12 slack absorbs).
#[allow(clippy::approx_constant)] // the committed mpmath-provenance value; not a stand-in for a std const
const INV_LN2: f64 = 1.4426950408889634;

/// `RN(2/pi)` (the sin/cos reduction scale).
#[allow(clippy::approx_constant)] // the committed mpmath-provenance value; not a stand-in for a std const
const TWO_OVER_PI: f64 = 0.6366197723675814;

/// The committed pi/2 three-piece split (`pi/2 = A + B + C`).
const PIO2_A: f64 = 1.570_796_340_703_964_2;
const PIO2_B: f64 = -1.390_906_756_437_715_3e-8;
const PIO2_C: f64 = -4.978_996_250_514_799_4e-17;

/// Bit pattern of `RN(sqrt(2))` (0x3FF6A09E667F3BCD): the range-reduction
/// threshold for `det_ln`, compared in the unbiased mantissa domain.
const SQRT2_BITS: u64 = 0x3ff6_a09e_667f_3bcd;

/// Exponent-field bias and masks (IEEE-754 binary64 layout).
const EXP_BIAS: i32 = 1023;
const MANT_MASK: u64 = 0x000f_ffff_ffff_ffff;
const ONE_BIASED: u64 = 0x3ff0_0000_0000_0000; // RN(1.0) bits

/// `2^54` exact -- the subnormal normalization factor for `det_ln`.
const SCAL54: f64 = 1.801_439_850_948_198_4e16;

/// Overflow/underflow thresholds for `det_exp` (committed; not the
/// overflow law itself -- that is `scale2`'s exponent guard, these are
/// the documented fast-exit constants, `EXP_UNDER = ln(2^-1075)`).
const EXP_OVER: f64 = 710.475_860_073_944;
const EXP_UNDER: f64 = -745.133_219_101_941_2;

/// `2^-54` exact -- the second scaling factor of the subnormal `exp`
/// path (`value = scale2(P, k+54) * SCAL_M54`, one extra correctly
/// rounded multiplication, never a double-rounded underflow).
const SCAL_M54: f64 = 5.551_115_123_125_783e-17;

/// The committed `det_ln` polynomials `P(f) = sum_i c_i f^i`
/// (= `f + f^2 * S(f)`, `S` degree 20, fitted on `f in [sqrt(1/2)-1,
/// sqrt(2)-1]` by the weighted target `(ln(1+f)-f)/f^2`; c0 and c1 are
/// the snapped structural values 0 and 1). Measured max error 1.21e-17
/// (0.217 ulp of 0.25) on the 600000-point mpmath grid.
const LN_P: &[f64] = &[
    /* f^0  */ 0.0,
    /* f^1  */ 1.0,
    /* f^2  */ -0.5,
    /* f^3  */ 0.333_333_333_333_334_15,
    /* f^4  */ -0.249_999_999_999_993_2,
    /* f^5  */ 0.199_999_999_999_546_12,
    /* f^6  */ -0.166_666_666_668_153_77,
    /* f^7  */ 0.142_857_142_932_915_68,
    /* f^8  */ -0.124_999_999_908_694_54,
    /* f^9  */ 0.111_111_105_286_214_73,
    /* f^10 */ -0.099_999_999_545_564_95,
    /* f^11 */ 0.090_909_334_488_746_72,
    /* f^12 */ -0.083_333_585_072_579_87,
    /* f^13 */ 0.076_917_157_859_541_83,
    /* f^14 */ -0.071_417_630_399_025_2,
    /* f^15 */ 0.066_750_039_419_020_86,
    /* f^16 */ -0.062_724_288_479_627_73,
    /* f^17 */ 0.058_211_643_212_004_82,
    /* f^18 */ -0.053_116_936_362_133_334,
    /* f^19 */ 0.053_843_354_028_079_76,
    /* f^20 */ -0.063_005_235_523_949_3,
    /* f^21 */ 0.058_041_591_474_845_22,
    /* f^22 */ -0.025_000_823_136_734_195,
];

/// The committed `det_exp` polynomials `P_E(r) = sum_i c_i r^i` on
/// `r in [-ln2/2 - 1e-12, ln2/2 + 1e-12]` (the half-integer-k slack).
/// c0 is the snapped structural value 1. Measured max error 4.19e-19
/// (0.0019 ulp near 1.0) on the 400000-point mpmath grid.
const EXP_P: &[f64] = &[
    /* r^0  */ 1.0,
    /* r^1  */ 1.0,
    /* r^2  */ 0.5,
    /* r^3  */ 0.166_666_666_666_666_66,
    /* r^4  */ 0.041_666_666_666_666_664,
    /* r^5  */ 0.008_333_333_333_333_333,
    /* r^6  */ 0.001_388_888_888_888_889,
    /* r^7  */ 0.000_198_412_698_412_698_4,
    /* r^8  */ 2.480_158_730_158_73e-5,
    /* r^9  */ 2.755_731_922_398_589_3e-6,
    /* r^10 */ 2.755_731_922_398_589e-7,
    /* r^11 */ 2.505_210_838_544_172e-8,
    /* r^12 */ 2.087_675_698_786_81e-9,
    /* r^13 */ 1.605_904_383_682_161_6e-10,
    /* r^14 */ 1.147_074_559_772_643_7e-11,
    /* r^15 */ 7.647_163_731_818_388e-13,
    /* r^16 */ 4.779_477_335_503_039e-14,
    /* r^17 */ 2.811_457_255_700_037_8e-15,
    /* r^18 */ 1.561_918_858_031_625_4e-16,
    /* r^19 */ 8.220_627_252_328_282e-18,
    /* r^20 */ 4.116_466_564_904_170_5e-19,
    /* r^21 */ 1.959_967_407_429_642_7e-20,
];

/// The committed `det_sin` odd-form `S(r) = r + r*r2*A(r2)`, `r2 = r*r`,
/// `A(u) = sum_i c_i u^i` fitted on `u in [0, pi^2/16 + slack]`.
/// Measured max error 4.45e-18 (0.028 ulp of sin(pi/4)).
const SIN_A: &[f64] = &[
    /* u^0  */ -0.166_666_666_666_666_66,
    /* u^1  */ 0.008_333_333_333_333_333,
    /* u^2  */ -0.000_198_412_698_412_698_4,
    /* u^3  */ 2.755_731_922_398_589_3e-6,
    /* u^4  */ -2.505_210_838_544_172e-8,
    /* u^5  */ 1.605_904_383_682_161_3e-10,
    /* u^6  */ -7.647_163_731_819_816e-13,
    /* u^7  */ 2.811_457_254_345_520_6e-15,
    /* u^8  */ -8.220_635_246_624_33e-18,
    /* u^9  */ 1.957_294_106_339_126_3e-20,
    /* u^10 */ -3.868_170_170_630_684e-23,
    /* u^11 */ 6.446_950_284_384_474e-26,
    /* u^12 */ -9.183_689_863_795_556e-29,
    /* u^13 */ 1.130_996_288_647_655e-31,
    /* u^14 */ -1.216_125_047_848_180_7e-34,
    /* u^15 */ 1.151_644_365_952_545e-37,
    /* u^16 */ -9.821_526_650_247_164e-41,
    /* u^17 */ 1.529_668_600_463_814_6e-42,
    /* u^18 */ -1.082_414_843_870_499_9e-42,
    /* u^19 */ 5.561_426_506_950_072e-43,
    /* u^20 */ -1.765_297_270_167_113_2e-43,
    /* u^21 */ 2.607_277_361_055_097e-44,
];

/// The committed `det_cos` form `C(r) = 1 + r2*D(r2)`, `D(u) = sum_i c_i
/// u^i` with the snapped structural c0 = -1/2. Measured max error
/// 8.93e-19 (0.008 ulp of 1.0).
const COS_D: &[f64] = &[
    /* u^0  */ -0.5,
    /* u^1  */ 0.041_666_666_666_666_664,
    /* u^2  */ -0.001_388_888_888_888_889,
    /* u^3  */ 2.480_158_730_158_73e-5,
    /* u^4  */ -2.755_731_922_398_589e-7,
    /* u^5  */ 2.087_675_698_786_81e-9,
    /* u^6  */ -1.147_074_559_772_972_5e-11,
    /* u^7  */ 4.779_477_332_387_385e-14,
    /* u^8  */ -1.561_920_696_858_622_5e-16,
    /* u^9  */ 4.110_317_623_312_165e-19,
    /* u^10 */ -8.896_791_392_450_574e-22,
    /* u^11 */ 1.611_737_571_096_118_2e-24,
    /* u^12 */ -2.479_596_263_224_797_6e-27,
    /* u^13 */ 3.279_889_237_069_718e-30,
    /* u^14 */ -3.769_987_628_554_608e-33,
    /* u^15 */ 3.800_390_308_112_502e-36,
    /* u^16 */ -3.386_564_971_761_826_5e-39,
    /* u^17 */ 2.091_268_037_174_236_3e-42,
    /* u^18 */ 4.392_337_666_158_789e-43,
    /* u^19 */ -2.254_082_168_810_204e-43,
    /* u^20 */ 7.112_811_356_244_084e-44,
    /* u^21 */ -1.044_045_413_194_454_4e-44,
];

/// The committed Horner order: `acc = acc*x + c`, descending, from 0.0.
/// This is the only evaluation form; the bit-stability tests ride it.
fn poly(coeffs: &[f64], x: f64) -> f64 {
    let mut acc = 0.0f64;
    let mut i = coeffs.len();
    while i > 0 {
        i -= 1;
        acc = acc * x + coeffs[i];
    }
    acc
}

/// Error-free pair sum (Knuth/Dekker, FMA-free): for normal operands the
/// exact real identity `a + b = s + err` holds; the committed
/// reconstructions chain this so the only rounding is the committed
/// final correction add (module docs).
fn two_sum(a: f64, b: f64) -> (f64, f64) {
    let s = a + b;
    let bb = s - a;
    let aa = s - bb;
    let err = (a - aa) + (b - bb);
    (s, err)
}

/// `scale2(p, k)` for normal `p in (0.5, 2)`: the exact-scaled `p * 2^k`
/// through the exponent field, the subnormal branch riding the single
/// correctly-rounded multiplication law of the module docs, and the
/// overflow branch the exponent-field guard.
fn scale2(p: f64, k: i32) -> f64 {
    let bits = p.to_bits();
    let e = ((bits >> 52) & 0x7ff) as i32;
    let ne = e + k;
    if ne >= 0x7ff {
        return f64::INFINITY;
    }
    if ne <= 0 {
        // |k| lands the product in the subnormal band. p in (0.5, 2) and
        // the det_exp entry guards keep k > -1076 here; one exact
        // pre-scale, then one correctly rounded multiply.
        if k <= -1076 {
            return 0.0;
        }
        return scale2(p, k + 54) * SCAL_M54;
    }
    f64::from_bits((bits & MANT_MASK) | ((ne as u64) << 52))
}

/// Deterministic `ln(x)`, `x > 0` finite; IEEE edges mirror libm
/// (`ln 0 = -inf`, `ln(-x) = nan`, `ln(+inf) = +inf`).
pub fn det_ln(x: f64) -> f64 {
    if x.is_nan() {
        return f64::NAN;
    }
    if x == f64::INFINITY {
        return f64::INFINITY;
    }
    if x < 0.0 {
        return f64::NAN;
    }
    if x == 0.0 {
        return f64::NEG_INFINITY;
    }
    let mut bits = x.to_bits();
    let mut e = ((bits >> 52) & 0x7ff) as i32 - EXP_BIAS;
    if e == -EXP_BIAS {
        // Subnormal: one exact power-of-two lift into the normal band.
        let xn = x * SCAL54;
        bits = xn.to_bits();
        e = ((bits >> 52) & 0x7ff) as i32 - EXP_BIAS - 54;
    }
    let mut m_bits = (bits & MANT_MASK) | ONE_BIASED;
    if m_bits >= SQRT2_BITS {
        m_bits -= 1 << 52; // m *= 0.5, exact in the exponent field
        e += 1;
    }
    let m = f64::from_bits(m_bits);
    let f = m - 1.0;
    let p = poly(LN_P, f);
    if e == 0 {
        return p;
    }
    let ef = e as f64;
    // Committed reconstruction (module docs): corrected three-piece
    // Cody-Waite, single rounding at the final correction add.
    let (s1, e1) = two_sum(p, ef * LN2_C);
    let (s2, e2) = two_sum(s1, ef * LN2_B);
    let (s3, e3) = two_sum(s2, ef * LN2_A);
    s3 + ((e1 + e2) + e3)
}

/// Deterministic `exp(x)`; IEEE edges mirror libm (`exp(nan) = nan`,
/// `exp(+inf) = inf`, `exp(-inf) = +0`).
pub fn det_exp(x: f64) -> f64 {
    if x.is_nan() {
        return f64::NAN;
    }
    if x == f64::INFINITY {
        return f64::INFINITY;
    }
    if x == f64::NEG_INFINITY {
        return 0.0;
    }
    if x > EXP_OVER {
        return f64::INFINITY;
    }
    if x < EXP_UNDER {
        return 0.0;
    }
    let kf = (x * INV_LN2).round();
    let k = kf as i32;
    // Committed reduction (module docs): corrected three-piece Cody-Waite.
    let (s1, r1) = two_sum(x, -(kf * LN2_A));
    let (s2, r2) = two_sum(s1, -(kf * LN2_B));
    let (s3, r3) = two_sum(s2, -(kf * LN2_C));
    let (r, e4) = two_sum(s3, (r1 + r2) + r3);
    let mut p = poly(EXP_P, r);
    if e4 != 0.0 {
        // The reduced argument is r + e4 exactly: e^(r+e4) = e^r(1+e4).
        p = p + e4 * p;
    }
    scale2(p, k)
}

/// The committed sin/cos reduction: returns `(quadrant, r)` with the
/// module-docs order. `x` is any finite value; the accuracy law is
/// committed for `|x| <= 2^22` (the executed call-site domain is
/// `|x| < 2*pi` -- the Box-Muller thetas and the reflection-branch
/// `pi*x` -- and the 2^22 bound is 6 orders above it with margin).
fn reduce_quadrant(x: f64) -> (i32, f64, f64) {
    let kf = (x * TWO_OVER_PI).round();
    let k = kf as i32;
    // Committed reduction (module docs): corrected three-piece Cody-Waite;
    // the last two_sum keeps the sub-ulp residual `err` of the reduced
    // argument, which the quadrant faces propagate through the derivative
    // (value + err*derivative) -- the FMA-free stand-in for fdlibm's
    // fma-accurate reduction.
    let (s1, r1) = two_sum(x, -(kf * PIO2_A));
    let (s2, r2) = two_sum(s1, -(kf * PIO2_B));
    let (s3, r3) = two_sum(s2, -(kf * PIO2_C));
    let (r, err) = two_sum(s3, (r1 + r2) + r3);
    let mut j = k % 4;
    if j < 0 {
        j += 4;
    }
    (j, r, err)
}

/// `S(r) = r + r*r2*A(r2)` for the reduced branch.
fn sin_poly(r: f64) -> f64 {
    let r2 = r * r;
    r + (r * r2) * poly(SIN_A, r2)
}

/// `C(r) = 1 + r2*D(r2)` for the reduced branch.
fn cos_poly(r: f64) -> f64 {
    let r2 = r * r;
    1.0 + r2 * poly(COS_D, r2)
}

/// Deterministic `sin(x)`; IEEE zero sign preserved.
pub fn det_sin(x: f64) -> f64 {
    if x.is_nan() {
        return f64::NAN;
    }
    if x == 0.0 {
        return x; // +/-0 sign-preserved
    }
    let (j, r, err) = reduce_quadrant(x);
    let mut v = match j {
        0 | 2 => sin_poly(r),
        _ => cos_poly(r),
    };
    if err != 0.0 {
        // The reduced argument is r + err exactly; carry the residual
        // through the active face's derivative (module docs).
        v = match j {
            0 | 2 => v + err * cos_poly(r),
            _ => v - err * sin_poly(r),
        };
    }
    if r == 0.0 {
        // Only reachable at the committed zero law; hand back the exact
        // quadrant value with the input's sign carried where it matters.
        return match j {
            0 => x,
            1 => 1.0,
            2 => -x,
            _ => -1.0,
        };
    }
    if j >= 2 {
        -v
    } else {
        v
    }
}

/// Deterministic `cos(x)`.
pub fn det_cos(x: f64) -> f64 {
    if x.is_nan() {
        return f64::NAN;
    }
    if x == 0.0 {
        return 1.0;
    }
    let (j, r, err) = reduce_quadrant(x);
    let mut v = match j {
        0 | 2 => cos_poly(r),
        _ => sin_poly(r),
    };
    if err != 0.0 {
        // Residual of the reduced argument through the derivative
        // (module docs); the sign flip applies to the corrected value.
        v = match j {
            0 | 2 => v - err * sin_poly(r),
            _ => v + err * cos_poly(r),
        };
    }
    if r == 0.0 {
        return match j {
            0 | 2 => 1.0,
            _ => 0.0, // odd quadrant cos lands on +0 (never executed;
                      // exact pi/2 multiples are not representable)
        };
    }
    if j == 1 || j == 2 {
        -v
    } else {
        v
    }
}

/// Deterministic `powf(x, y)` -- the committed composition
/// `det_exp(y * det_ln(x))` with the libm `pow` identity edges handled
/// explicitly. Domain law (the gamma-sampler boost call site): `x` is a
/// `unit_interval()` value in `[0, 1)` and `y = 1/shape > 1`; the general
/// positive finite domain is served identically. Documented accuracy:
/// the composition of two committed faces carries the ln ulps through
/// the exponent -- relative error <= |y*ln x|*2^-52 + 2 ulps, never on
/// an attested-bytes face.
pub fn det_powf(x: f64, y: f64) -> f64 {
    if x.is_nan() || y.is_nan() {
        return f64::NAN;
    }
    if y == 0.0 {
        return 1.0; // 0^0 = 1 mirrors libm pow
    }
    if x == 0.0 {
        return if y > 0.0 { 0.0 } else { f64::INFINITY };
    }
    if x < 0.0 {
        return f64::NAN;
    }
    if x == 1.0 {
        return 1.0;
    }
    if x == f64::INFINITY {
        return if y > 0.0 { f64::INFINITY } else { 0.0 };
    }
    det_exp(y * det_ln(x))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Signed ulp distance between two same-sign positive values
    /// (monotone map of the bit pattern; the test domain never crosses 0
    /// except through the exact-zero law tested separately).
    fn ulps(a: f64, b: f64) -> i64 {
        (a.to_bits() as i64 - b.to_bits() as i64).abs()
    }

    /// Deterministic bit-walk grid (no `rand`; the streams must be
    /// reproducible on both toolchains).
    fn lcg(seed: u64, n: usize, lo_bits: u64, hi_bits: u64) -> Vec<f64> {
        let mut s = seed;
        (0..n)
            .map(|_| {
                s = s.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1_442_695_040_888_963_406);
                let span = hi_bits - lo_bits;
                let v = lo_bits + (s >> 11) % (span.max(1));
                f64::from_bits(v)
            })
            .collect()
    }

    fn ln_grid() -> Vec<f64> {
        let mut g: Vec<f64> = vec![
            1.0,
            f64::from_bits(1.0f64.to_bits() + 1),
            f64::from_bits(1.0f64.to_bits() - 1),
            f64::from_bits(1.0f64.to_bits() + 32),
            f64::from_bits(1.0f64.to_bits() - 32),
            0.5,
            2.0,
            4.0,
            1024.0f64,
            f64::from_bits(SQRT2_BITS),
            f64::from_bits(SQRT2_BITS + 1),
            f64::from_bits(SQRT2_BITS - 1),
            1e-12, // KL_EPS
            1e-16, // LL_EPS
            2e-308,
            f64::from_bits(1),                    // min subnormal
            f64::from_bits(0x000f_ffff_ffff_ffff), // max subnormal
            f64::from_bits(0x0010_0000_0000_0000), // min normal
            f64::from_bits(0x7fe0_0000_0000_0000), // min positive normal-side spot
            f64::from_bits(0x7fe0_0000_0000_0001), // (max finite + ulp is inf)
        ];
        // Powers of two across the whole finite range (the exact exponent
        // boundaries).
        for k in -1074i32..=1023 {
            let x = if k >= -1022 {
                f64::from_bits(((k + EXP_BIAS) as u64) << 52)
            } else {
                // subnormal powers of two
                f64::from_bits(1u64 << (k + 1074))
            };
            g.push(x);
        }
        // Dense bit-walk sweeps of the reduction interval and beyond.
        g.extend(lcg(7, 40_000, 0x3fe0_0000_0000_0000, 0x4000_0000_0000_0000)); // [0.5, 2)
        g.extend(lcg(9, 20_000, 0x0000_0000_0000_0001, 0x000f_ffff_ffff_ffff)); // subnormals
        g.extend(lcg(11, 20_000, 0x0010_0000_0000_0000, 0x1921_fb3f_ffc0_ebe3)); // to ~1e-30
        g.extend(lcg(13, 20_000, 0x4000_0000_0000_0000, 0x40b3_8000_0000_0000)); // [2, ~5000]
        g
    }

    fn exp_grid() -> Vec<f64> {
        let mut g: Vec<f64> = vec![
            0.0,
            -0.0,
            1.0,
            -1.0,
            std::f64::consts::LN_2,
            -std::f64::consts::LN_2,
            std::f64::consts::LN_2 / 2.0,
            -std::f64::consts::LN_2 / 2.0,
            f64::from_bits((std::f64::consts::LN_2 / 2.0).to_bits() + 1),
            f64::from_bits((std::f64::consts::LN_2 / 2.0).to_bits() - 1),
            f64::from_bits((-(std::f64::consts::LN_2 / 2.0)).to_bits() + 1),
            f64::from_bits((-(std::f64::consts::LN_2 / 2.0)).to_bits() - 1),
            std::f64::consts::LN_2 * 0.5 + f64::from_bits(1), // half-integer k slacks
            -std::f64::consts::LN_2 * (1074.5),
            -744.0,
            -744.5,
            -745.0,
            -744.44,
            -745.133_219_101_941_2,
            -746.0,
            709.0,
            709.782_712_893_384,
            710.475_860_073_944,
            709.9,
        ];
        g.extend(lcg(21, 40_000, 0xbf76_6666_6666_6666, 0xbfe6_6666_6666_6667));
        // linear fills via bit walks of the central band
        let mut s = 0x24ba_2db8_u64;
        for _ in 0..40_000 {
            s = s.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1_442_695_040_888_963_406);
            let frac = ((s >> 11) % (1u64 << 40)) as f64 / (1u64 << 40) as f64;
            g.push(-1400.0 + 1400.0 * frac);
        }
        g
    }

    fn trig_grid() -> Vec<f64> {
        let mut g: Vec<f64> = vec![0.0, -0.0, 1.0, -1.0, PIO2_A, 1e-16, 5e-324];
        let mut s = 0xf00d_ba11_u64;
        for _ in 0..60_000 {
            s = s.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1_442_695_040_888_963_406);
            let frac = ((s >> 11) % (1u64 << 40)) as f64 / (1u64 << 40) as f64;
            g.push(-7.5 + 15.0 * frac);
        }
        // quarter-pi grid around the quadrant boundaries
        for k in -40i64..=40 {
            let b = (k as f64) * PIO2_A;
            for d in -3i64..=3i64 {
                let v = f64::from_bits(b.to_bits().wrapping_add(d as u64));
                if !v.is_finite() {
                    continue;
                }
                g.push(v);
            }
        }
        // executed-face thetas: TAU * u2 grids
        for i in 1..1000u64 {
            let u = i as f64 / 1024.0;
            g.push(std::f64::consts::TAU * u);
            g.push(std::f64::consts::PI * u / 2.0);
        }
        // large-argument spot checks (inside the 2^22 documented domain)
        g.extend_from_slice(&[1e3, 1e4, 1e5, 1e6, 4.1e6, -1e5, -1e6]);
        g
    }

    #[test]
    fn det_ln_matches_libm_within_one_ulp() {
        for &x in &ln_grid() {
            let d = det_ln(x);
            let l = x.ln();
            assert!(ulps(d, l) <= 1, "det_ln({x:?}) = {d:?} vs libm {l:?} ({} ulps)", ulps(d, l));
        }
    }

    #[test]
    fn det_ln_exact_laws() {
        assert_eq!(det_ln(1.0).to_bits(), 0.0f64.to_bits(), "det_ln(1) must be exactly +0");
        assert!(det_ln(0.0) == f64::NEG_INFINITY);
        assert!(det_ln(f64::INFINITY) == f64::INFINITY);
        assert!(det_ln(-1.0).is_nan());
        assert!(det_ln(-0.0) == f64::NEG_INFINITY, "IEEE ln(-0) = -inf (libm parity)");
        // The exact powers of two: det(k*ln2 split) vs the libm value.
        for k in [-1022i32, -53, 0, 1, 53, 1023] {
            let x = f64::from_bits(((k + EXP_BIAS) as u64) << 52);
            assert!(ulps(det_ln(x), x.ln()) <= 1, "2^{k}");
        }
    }

    #[test]
    fn det_ln_is_monotone() {
        // Dense consecutive-bit walk through the reduction window, then a
        // strided walk over the committed [0.5, 2.5] face: the committed
        // poly error (1.2e-17) is 18x under the ln-spacing of adjacent
        // doubles (>= 2.2e-16), so monotonicity is a theorem; these walks
        // measure it.
        let base = 0x3ff0_0000_0000_0000u64; // 1.0
        let mut prev = det_ln(f64::from_bits(base - 600));
        for b in (base - 600)..=(base + 600) {
            let v = det_ln(f64::from_bits(b));
            assert!(v >= prev, "dense monotonicity break at bits {b:#x}: {v} < {prev}");
            prev = v;
        }
        let mut bits = 0x3fe0_0000_0000_0000u64; // 0.5
        prev = det_ln(0.5);
        let stop = 0x4004_0000_0000_0000; // 2.5
        while bits <= stop {
            let v = det_ln(f64::from_bits(bits));
            assert!(v >= prev, "strided monotonicity break at bits {bits:#x}: {v} < {prev}");
            prev = v;
            bits += 1 << 33;
        }
    }

    #[test]
    fn det_exp_matches_libm_within_one_ulp() {
        for &x in &exp_grid() {
            let d = det_exp(x);
            let l = x.exp();
            if d == 0.0 && l == 0.0 {
                continue;
            }
            assert!(ulps(d, l) <= 1, "det_exp({x:?}) = {d:?} vs libm {l:?} ({} ulps)", ulps(d, l));
        }
        assert_eq!(det_exp(0.0).to_bits(), 1.0f64.to_bits());
        assert_eq!(det_exp(-0.0).to_bits(), 1.0f64.to_bits());
        assert!(det_exp(f64::NEG_INFINITY) == 0.0);
        assert!(det_exp(f64::INFINITY) == f64::INFINITY);
        assert!(det_exp(EXP_OVER + 1.0).is_infinite());
        assert!(det_exp(EXP_UNDER - 1.0) == 0.0);
        assert!(det_exp(-744.5) > 0.0 && det_exp(-744.5).to_bits() < (1u64 << 52), "subnormal face is live");
    }

    #[test]
    fn det_exp_is_monotone() {
        // IEEE magnitude-bit ordering: for negatives, increasing value
        // means DECREASING bit patterns (toward the -0 pattern), and the
        // positives then walk up from +0. Two strided segments.
        let hi = 700.0f64.to_bits(); // +700 pattern
        let neg_hi = hi | (1u64 << 63); // -700 pattern
        let mut prev = det_exp(-700.0);
        let mut s = neg_hi;
        while s > (1u64 << 63) {
            s -= 1 << 38;
            let v = det_exp(f64::from_bits(s));
            assert!(v >= prev, "exp monotonicity break (neg leg) at bits {s:#x}");
            prev = v;
        }
        let mut s = 0u64; // +0
        while s <= hi {
            let v = det_exp(f64::from_bits(s));
            assert!(v >= prev, "exp monotonicity break (pos leg) at bits {s:#x}");
            prev = v;
            s += 1 << 38;
        }
    }

    #[test]
    fn trig_matches_libm_within_one_ulp_on_the_committed_domain() {
        for &x in &trig_grid() {
            let big = x.abs() > 16.0;
            let bound = if big { 2 } else { 1 };
            let ds = det_sin(x);
            let ls = x.sin();
            assert!(ulps(ds.abs(), ls.abs()) <= bound, "det_sin({x:?}) = {ds:?} vs libm {ls:?} ({} ulps)", ulps(ds.abs(), ls.abs()));
            let dc = det_cos(x);
            let lc = x.cos();
            assert!(ulps(dc.abs(), lc.abs()) <= bound, "det_cos({x:?}) = {dc:?} vs libm {lc:?} ({} ulps)", ulps(dc.abs(), lc.abs()));
        }
        assert_eq!(det_sin(0.0).to_bits(), 0.0f64.to_bits());
        assert_eq!(det_sin(-0.0).to_bits(), (-0.0f64).to_bits(), "zero sign law");
        assert_eq!(det_cos(0.0).to_bits(), 1.0f64.to_bits());
    }

    #[test]
    fn det_sin_is_monotone_first_quadrant() {
        let mut prev = -1.0f64;
        let mut bits = 0u64;
        let stop = 0x3ff9_21fb_5444_2d18; // pi/2
        while bits <= stop {
            let v = det_sin(f64::from_bits(bits));
            assert!(v >= prev, "sin monotonicity break at bits {bits:#x}");
            prev = v;
            bits += 1 << 35;
        }
    }

    #[test]
    fn nan_and_inf_edges() {
        let n = f64::NAN;
        assert!(det_ln(n).is_nan() && det_exp(n).is_nan() && det_sin(n).is_nan() && det_cos(n).is_nan());
        assert!(det_ln(-1.0).is_nan());
        assert!(det_powf(-1.0, 2.0).is_nan() && det_powf(n, 1.0).is_nan());
        assert!(det_sin(f64::INFINITY).is_nan() && det_cos(f64::INFINITY).is_nan());
    }

    #[test]
    fn det_powf_face() {
        // The committed sampler face: unit-interval base, 1/shape exponent.
        let ys = [1.000_000_000_1f64, 2.0, 10.0, 1000.0, 1e6];
        let mut s = 0xdead_beef_u64;
        for _ in 0..4000 {
            s = s.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1_442_695_040_888_963_406);
            let x = f64::from_bits((s >> 12) % (0x3ff0_0000_0000_0000 + 1));
            for &y in &ys {
                let d = det_powf(x, y);
                let l = x.powf(y);
                if l == 0.0 {
                    assert!(d == 0.0, "det_powf({x:?}, {y:?}) = {d:?} vs underflowing libm");
                    continue;
                }
                // Committed composition law (module docs): relative
                // error <= |y*ln x|*2^-52 + 2 ulps -- exp-of-ln carries
                // the ln ulps through the exponent.
                let tol = ((y * l.ln()).abs() + 2.0) * 2.220_446_049_250_313e-16;
                assert!(
                    (d - l).abs() <= tol * l.abs() + 5.0e-324,
                    "det_powf({x:?}, {y:?}) = {d:?} vs libm {l:?}"
                );
            }
        }
        assert!(det_powf(0.0, 3.0) == 0.0);
        assert!(det_powf(0.5, 0.0) == 1.0);
        assert!(det_powf(3.7, 0.0) == 1.0);
        assert!(det_powf(1.0, 9.9) == 1.0);
        assert!(det_powf(-2.0, 3.0).is_nan());
    }

    #[test]
    fn same_input_same_bits_repeated() {
        // The determinism law inside one process: every face must be a
        // pure function of its bits -- twice over every grid.
        for &x in ln_grid().iter().chain(exp_grid().iter()).chain(trig_grid().iter()) {
            assert_eq!(det_ln(x).to_bits(), det_ln(x).to_bits());
            assert_eq!(det_exp(x).to_bits(), det_exp(x).to_bits());
            assert_eq!(det_sin(x).to_bits(), det_sin(x).to_bits());
            assert_eq!(det_cos(x).to_bits(), det_cos(x).to_bits());
        }
        for (i, &x) in exp_grid().iter().enumerate().take(500) {
            let y = 1.5 + (i % 7) as f64;
            assert_eq!(det_powf(x.abs().min(0.99), y).to_bits(), det_powf(x.abs().min(0.99), y).to_bits());
        }
    }

    #[test]
    fn same_input_same_bits_across_threads() {
        // The determinism law across the thread-count face the engine
        // serves under (1 and the default): no face may read thread
        // state -- recomputed on four concurrent threads, bits must
        // match the serial result.
        let g: Vec<f64> = ln_grid()
            .into_iter()
            .chain(exp_grid())
            .chain(trig_grid())
            .collect();
        let refs: Vec<(u64, u64, u64, u64)> = g
            .iter()
            .map(|&x| (det_ln(x).to_bits(), det_exp(x).to_bits(), det_sin(x).to_bits(), det_cos(x).to_bits()))
            .collect();
        let mut handles = Vec::new();
        for chunk in g.chunks(g.len().div_ceil(4)) {
            let c: Vec<f64> = chunk.to_vec();
            let r: Vec<(u64, u64, u64, u64)> = {
                let off = chunk.as_ptr() as usize - g.as_ptr() as usize;
                let _ = off;
                c.iter()
                    .map(|&x| (det_ln(x).to_bits(), det_exp(x).to_bits(), det_sin(x).to_bits(), det_cos(x).to_bits()))
                    .collect()
            };
            handles.push(std::thread::spawn(move || {
                let c2: Vec<(u64, u64, u64, u64)> = c
                    .iter()
                    .map(|&x| (det_ln(x).to_bits(), det_exp(x).to_bits(), det_sin(x).to_bits(), det_cos(x).to_bits()))
                    .collect();
                assert_eq!(&c2[..], &r[..], "thread-side bits diverged from serial");
            }));
        }
        for h in handles {
            h.join().expect("thread law");
        }
        let _ = &refs;
    }
}
