class UnresolvableVariantException implements Exception {
  final String rawDescriptor;

  UnresolvableVariantException(this.rawDescriptor);

  @override
  String toString() => 'Cannot resolve variant identifier "$rawDescriptor" as a mutation descriptor';
}

/// A single-residue substitution, 1-indexed against a parent sequence.
class Substitution {
  final int position;
  final String from;
  final String to;

  const Substitution({required this.position, required this.from, required this.to});

  @override
  String toString() => '$from$position$to';

  @override
  bool operator ==(Object other) =>
      other is Substitution && other.position == position && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(position, from, to);
}

final RegExp _substitutionPattern = RegExp(r'^([A-Z])(\d+)([A-Z])$');

/// Parses a colon-joined mutation descriptor such as "A25D:H7T" into its substitutions.
///
/// Throws [UnresolvableVariantException] if [raw] does not match that format.
List<Substitution> parseMutationDescriptor(String raw) {
  final tokens = raw.split(':');
  final substitutions = <Substitution>[];
  for (final token in tokens) {
    final match = _substitutionPattern.firstMatch(token);
    if (match == null) {
      throw UnresolvableVariantException(raw);
    }
    substitutions.add(Substitution(
      from: match.group(1)!,
      position: int.parse(match.group(2)!),
      to: match.group(3)!,
    ));
  }
  if (substitutions.isEmpty) {
    throw UnresolvableVariantException(raw);
  }
  return substitutions;
}

/// Uses 1-based positions; returns null for an out-of-range position or residue mismatch.
String? applySubstitutions(String parentSequence, List<Substitution> substitutions) {
  final residues = parentSequence.split('');
  for (final substitution in substitutions) {
    final index = substitution.position - 1;
    if (index < 0 || index >= residues.length) {
      return null;
    }
    if (residues[index] != substitution.from) {
      return null;
    }
    residues[index] = substitution.to;
  }
  return residues.join();
}

/// Formats substitutions for display, e.g. "A186V" or "A186V + T209P".
String formatSubstitutions(List<Substitution> substitutions) {
  return substitutions.map((substitution) => substitution.toString()).join(' + ');
}
