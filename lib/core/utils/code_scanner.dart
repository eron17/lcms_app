/// Scans C++ source code submitted from the 3D Meet Unity flow and detects
/// which programming concepts / patterns are present.
///
/// Pure Dart, regex-based heuristics only — no external packages.
class CodeScanner {
  CodeScanner(this.sourceCode);

  final String sourceCode;

  // ---------------------------------------------------------------------
  // Loops
  // ---------------------------------------------------------------------

  bool get hasForLoop => RegExp(r'\bfor\s*\(').hasMatch(sourceCode);

  bool get hasWhileLoop => RegExp(r'\bwhile\s*\(').hasMatch(sourceCode);

  bool get hasDoWhile =>
      RegExp(r'\bdo\s*\{').hasMatch(sourceCode) &&
      RegExp(r'\}\s*while\s*\(').hasMatch(sourceCode);

  bool get hasAnyLoop => hasForLoop || hasWhileLoop || hasDoWhile;

  // ---------------------------------------------------------------------
  // Classes / objects
  // ---------------------------------------------------------------------

  bool get hasClass => RegExp(r'\bclass\s+\w+').hasMatch(sourceCode);

  bool get hasObject {
    if (hasClass) {
      final classNames = RegExp(r'\bclass\s+(\w+)')
          .allMatches(sourceCode)
          .map((m) => m.group(1)!);
      for (final className in classNames) {
        final declared = RegExp('\\b$className\\s+\\w+\\s*[;(]');
        if (declared.hasMatch(sourceCode)) return true;
      }
    }
    return RegExp(r'\bnew\s+\w+').hasMatch(sourceCode) ||
        RegExp(r'\w+\.\w+\s*\(').hasMatch(sourceCode) ||
        RegExp(r'\w+->\w+\s*\(').hasMatch(sourceCode);
  }

  bool get hasEncapsulation =>
      RegExp(r'\b(private|public|protected)\s*:').hasMatch(sourceCode);

  bool get hasGetterSetter =>
      hasClass &&
      RegExp(r'\b(get|set)[A-Za-z0-9]+\s*\(').hasMatch(sourceCode);

  // ---------------------------------------------------------------------
  // Inheritance / polymorphism
  // ---------------------------------------------------------------------

  bool get hasInheritance => RegExp(
        r'\bclass\s+\w+\s*:\s*(public|private|protected)\s+\w+',
      ).hasMatch(sourceCode);

  bool get usesOverride => RegExp(r'\boverride\b').hasMatch(sourceCode);

  bool get hasVirtualFunction => RegExp(r'\bvirtual\b').hasMatch(sourceCode);

  bool get hasPureVirtual =>
      RegExp(r'\bvirtual\b[^;{]*=\s*0\s*;').hasMatch(sourceCode);

  bool get hasPolymorphism =>
      usesOverride || hasVirtualFunction || hasPureVirtual;

  bool get hasAbstraction => hasPureVirtual;

  // ---------------------------------------------------------------------
  // Overloading
  // ---------------------------------------------------------------------

  bool get hasFunctionOverloading {
    final names = _extractFunctions().map((f) => f.name).toList();
    final seen = <String>{};
    for (final name in names) {
      if (!seen.add(name)) return true;
    }
    return false;
  }

  bool get hasOperatorOverloading => RegExp(
        r'operator\s*(\+|\-|\*|/|==|!=|<<|>>|\[\]|\(\)|=|<=|>=|<|>)\s*\(',
      ).hasMatch(sourceCode);

  // ---------------------------------------------------------------------
  // Other language features
  // ---------------------------------------------------------------------

  bool get hasTemplates => RegExp(r'\btemplate\s*<').hasMatch(sourceCode);

  bool get hasExceptionHandling =>
      RegExp(r'\btry\s*\{').hasMatch(sourceCode) &&
      RegExp(r'\bcatch\s*\(').hasMatch(sourceCode);

  bool get hasPointers =>
      RegExp(r'\w+\s*\*\s*\w+\s*(=|;|,|\))').hasMatch(sourceCode) ||
      sourceCode.contains('->');

  bool get hasRecursion {
    for (final fn in _extractFunctions()) {
      final selfCall = RegExp('\\b${RegExp.escape(fn.name)}\\s*\\(');
      if (selfCall.hasMatch(fn.body)) return true;
    }
    return false;
  }

  bool get hasArray =>
      RegExp(r'\w+\s*\[\s*\d*\s*\]\s*[;=]').hasMatch(sourceCode) ||
      RegExp(r'\w+\s*\[\s*\w*\s*\]\s*(=|;)').hasMatch(sourceCode);

  bool get isLikelyHardcoded {
    final hasLogic = hasAnyLoop ||
        RegExp(r'\bif\s*\(').hasMatch(sourceCode) ||
        RegExp(r'\bswitch\s*\(').hasMatch(sourceCode) ||
        hasRecursion;
    final hasVariableDeclarations = RegExp(
      r'\b(int|float|double|char|string|bool|long)\s+\w+\s*(=|;)',
    ).hasMatch(sourceCode);
    final printsLiteral = RegExp(r'cout\s*<<\s*"').hasMatch(sourceCode);
    final printsVariable = RegExp(r'cout\s*<<\s*\w+\s*(;|<<)')
        .hasMatch(sourceCode);
    return printsLiteral && !printsVariable && !hasLogic && !hasVariableDeclarations;
  }

  // ---------------------------------------------------------------------
  // Generic keyword / forbidden-pattern lookups
  // ---------------------------------------------------------------------

  bool hasKeyword(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return false;
    if (RegExp(r'^\w+$').hasMatch(trimmed)) {
      return RegExp('\\b${RegExp.escape(trimmed)}\\b').hasMatch(sourceCode);
    }
    return sourceCode.contains(trimmed);
  }

  // NOTE: hasForbiddenPattern intentionally mirrors hasKeyword for now.
  // If forbidden patterns ever need stricter matching (e.g. no partial
  // matches even for symbols), separate the logic here.
  bool hasForbiddenPattern(String pattern) {
    final trimmed = pattern.trim();
    if (trimmed.isEmpty) return false;
    if (RegExp(r'^\w+$').hasMatch(trimmed)) {
      return RegExp('\\b${RegExp.escape(trimmed)}\\b').hasMatch(sourceCode);
    }
    return sourceCode.contains(trimmed);
  }

  bool allKeywordsPresent(List<String> keywords) {
    if (keywords.isEmpty) return true;
    return keywords.every(hasKeyword);
  }

  bool anyForbiddenFound(List<String> patterns) {
    if (patterns.isEmpty) return false;
    return patterns.any(hasForbiddenPattern);
  }

  // ---------------------------------------------------------------------
  // Full scan
  // ---------------------------------------------------------------------

  Map<String, dynamic> fullScan() {
    return {
      'hasForLoop': hasForLoop,
      'hasWhileLoop': hasWhileLoop,
      'hasDoWhile': hasDoWhile,
      'hasAnyLoop': hasAnyLoop,
      'hasClass': hasClass,
      'hasObject': hasObject,
      'hasEncapsulation': hasEncapsulation,
      'hasGetterSetter': hasGetterSetter,
      'hasInheritance': hasInheritance,
      'usesOverride': usesOverride,
      'hasVirtualFunction': hasVirtualFunction,
      'hasPureVirtual': hasPureVirtual,
      'hasFunctionOverloading': hasFunctionOverloading,
      'hasOperatorOverloading': hasOperatorOverloading,
      'hasPolymorphism': hasPolymorphism,
      'hasAbstraction': hasAbstraction,
      'hasTemplates': hasTemplates,
      'hasExceptionHandling': hasExceptionHandling,
      'hasPointers': hasPointers,
      'hasRecursion': hasRecursion,
      'hasArray': hasArray,
      'isLikelyHardcoded': isLikelyHardcoded,
    };
  }

  // ---------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------

  /// Extracts top-level function definitions (name + brace-matched body)
  /// using manual brace counting, since regex alone can't match nested
  /// braces reliably.
  List<_FunctionInfo> _extractFunctions() {
    final results = <_FunctionInfo>[];
    final header = RegExp(r'(\w[\w:<>,\s\*&]*?)\s+(\w+)\s*\(([^;{}]*)\)\s*\{');
    for (final match in header.allMatches(sourceCode)) {
      final name = match.group(2)!;
      final braceStart = match.end - 1;
      var depth = 0;
      var i = braceStart;
      for (; i < sourceCode.length; i++) {
        if (sourceCode[i] == '{') {
          depth++;
        } else if (sourceCode[i] == '}') {
          depth--;
          if (depth == 0) break;
        }
      }
      if (i >= sourceCode.length) i = sourceCode.length - 1;
      final body = sourceCode.substring(braceStart, i + 1);
      results.add(_FunctionInfo(name, body));
    }
    return results;
  }
}

class _FunctionInfo {
  _FunctionInfo(this.name, this.body);

  final String name;
  final String body;
}
