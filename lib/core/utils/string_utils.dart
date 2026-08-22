String toTitleCase(String input) {
  if (input.trim().isEmpty) return input;

  // Split camelCase and PascalCase into words
  // e.g. janeDoe → jane Doe → Jane Doe
  final spaced = input
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (m) => '${m[1]} ${m[2]}',
      )
      .replaceAllMapped(
        RegExp(r'([A-Z]+)([A-Z][a-z])'),
        (m) => '${m[1]} ${m[2]}',
      );

  // Split by whitespace and capitalize each word
  return spaced
      .trim()
      .split(RegExp(r'\s+'))
      .map((word) => word.isEmpty
          ? ''
          : word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join(' ');
}
