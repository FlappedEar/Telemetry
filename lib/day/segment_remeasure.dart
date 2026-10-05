/// Which groups' kept segments may be measured again on a new best lap
/// (FET-170, `remeasureDaySegments`). A group is marked when sessions are
/// added to it, and settled once a theoretical best for it was accepted,
/// measured again or not. Opening a day marks nothing: measuring again
/// there would change the day unasked.
final class SegmentRemeasure {
  final _pending = <String>{};

  /// Sessions were added to [groupIds].
  void added(Iterable<String> groupIds) => _pending.addAll(groupIds);

  /// Whether the next theoretical best for [groupId] may measure again.
  bool pendingFor(String? groupId) =>
      groupId != null && _pending.contains(groupId);

  /// A theoretical best for [groupId] was accepted.
  void settled(String groupId) => _pending.remove(groupId);
}
