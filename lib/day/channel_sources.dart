/// The channels of the open day that came, in at least one session, from a
/// recording other than the session's own (the RCZ fused into its VBO), with
/// that recording's format ("RCZ"), by channel name. Set by the open day;
/// shown where a chart does not say which session it reads.
Map<String, String> dayChannelSources = const {};

/// The names of every channel the open day recorded, its fused recordings'
/// included, sorted. Set by the open day; empty when none is open.
List<String> dayRecordedChannels = const [];
