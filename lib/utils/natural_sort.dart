/// Sorts strings the way a human would: "2. Book" comes before "10. Book",
/// and "Chapter 9.mp3" comes before "Chapter 10.mp3".
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final partsA = re.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final partsB = re.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();

  for (var i = 0; i < partsA.length && i < partsB.length; i++) {
    final sa = partsA[i];
    final sb = partsB[i];
    final na = BigInt.tryParse(sa);
    final nb = BigInt.tryParse(sb);

    final int c;
    if (na != null && nb != null) {
      c = na.compareTo(nb);
    } else {
      c = sa.compareTo(sb);
    }
    if (c != 0) return c;
  }
  return partsA.length.compareTo(partsB.length);
}
