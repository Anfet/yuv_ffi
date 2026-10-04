/// Computes the original LCG step without losing lower bits in dart2js.
///
/// Every intermediate stays below 2^53, unlike the direct multiplication by
/// 1103515245 whose result is rounded by JavaScript's IEEE-754 number type.
int probeNextSeed(int seed) {
  const aHi = 16838;
  const aLo = 20077;
  final hi = (seed * aHi) % 32768;
  return (seed * aLo + hi * 65536 + 12345) % 2147483648;
}
