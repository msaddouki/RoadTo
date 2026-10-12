import 'event.dart';

/// Filtre d'abonnement NIP-01.
class NostrFilter {
  final List<String>? ids;
  final List<String>? authors;
  final List<int>? kinds;

  /// Filtres sur tags d'une lettre, par exemple {'g': ['u05kq']}.
  final Map<String, List<String>> tags;
  final int? since;
  final int? until;
  final int? limit;

  const NostrFilter({this.ids, this.authors, this.kinds, this.tags = const {}, this.since, this.until, this.limit});

  factory NostrFilter.fromJson(Map<String, dynamic> json) {
    final tags = <String, List<String>>{};
    for (final e in json.entries) {
      if (e.key.startsWith('#') && e.key.length == 2) {
        tags[e.key.substring(1)] = [for (final v in e.value as List) v.toString()];
      }
    }
    List<String>? strings(String k) => json[k] == null ? null : [for (final v in json[k] as List) v.toString()];
    return NostrFilter(
      ids: strings('ids'),
      authors: strings('authors'),
      kinds: json['kinds'] == null ? null : [for (final v in json['kinds'] as List) v as int],
      tags: tags,
      since: json['since'] as int?,
      until: json['until'] as int?,
      limit: json['limit'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (ids != null) 'ids': ids,
    if (authors != null) 'authors': authors,
    if (kinds != null) 'kinds': kinds,
    for (final e in tags.entries) '#${e.key}': e.value,
    if (since != null) 'since': since,
    if (until != null) 'until': until,
    if (limit != null) 'limit': limit,
  };

  bool matches(NostrEvent e) {
    if (ids != null && !ids!.contains(e.id)) return false;
    if (authors != null && !authors!.contains(e.pubkey)) return false;
    if (kinds != null && !kinds!.contains(e.kind)) return false;
    if (since != null && e.createdAt < since!) return false;
    if (until != null && e.createdAt > until!) return false;
    for (final entry in tags.entries) {
      final values = e.tagValues(entry.key);
      if (!values.any(entry.value.contains)) return false;
    }
    return true;
  }
}
