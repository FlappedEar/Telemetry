import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart' show deltaTimeChannel;

import 'day/channel_sources.dart';
import 'l10n.dart';
import 'ui/readable_list.dart';

/// The names the driver gave recorded channels in settings ("Throttle" for
/// `accelerator_pos-obd`), keyed by the channel's name as recorded. Kept in
/// `settings.json`; the recordings and the `.fetproject` keep the recorded
/// names.
final ValueNotifier<Map<String, String>> channelNamesSetting = ValueNotifier(
  const {},
);

/// The channels the driver starred in settings: when any is starred, the
/// lists of channels a chart can show offer those, and the rest under "All
/// channels…". Recorded names, kept in `settings.json`.
final ValueNotifier<List<String>> listedChannelsSetting = ValueNotifier(
  const [],
);

/// Stars [channel] for the chart lists, or takes its star away.
void setChannelListed(String channel, bool listed) {
  final current = listedChannelsSetting.value;
  if (current.contains(channel) == listed) return;
  listedChannelsSetting.value = List.unmodifiable(
    listed
        ? [...current, channel]
        : [
            for (final other in current)
              if (other != channel) other,
          ],
  );
}

/// What a chart list offers of [channels]: all of them while no channel is
/// starred; else the starred ones and Δ time, possibly none ("All
/// channels…" still lists every one).
List<String> listedChoices(List<String> channels) {
  final starred = listedChannelsSetting.value.toSet();
  if (starred.isEmpty) return channels;
  return [
    for (final channel in channels)
      if (channel == deltaTimeChannel || starred.contains(channel)) channel,
  ];
}

/// The menu value that opens every channel ([chooseChannel]).
const String allChannelsChoice = '\u0000all';

/// A chart menu's entries for [channels]: those [listedChoices] offers, by
/// [label], and "All channels…" when that leaves some out.
List<PopupMenuEntry<String>> channelMenuItems(
  BuildContext context,
  List<String> channels,
  String Function(String channel) label,
) {
  final listed = listedChoices(channels);
  return [
    for (final channel in listed)
      PopupMenuItem(value: channel, child: Text(label(channel))),
    if (listed.length < channels.length) ...[
      const PopupMenuDivider(),
      PopupMenuItem(
        key: const ValueKey('chartAllChannels'),
        value: allChannelsChoice,
        child: Text(context.l10n.chartAllChannels),
      ),
    ],
  ];
}

/// [onPick] with the channel chosen from a chart menu; "All channels…"
/// first lists every one of [channels].
Future<void> chooseChannel(
  BuildContext context,
  String value,
  List<String> channels,
  String Function(String channel) label,
  ValueChanged<String> onPick,
) async {
  if (value != allChannelsChoice) return onPick(value);
  final picked = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(context.l10n.chartChooseChannel),
      children: [
        for (final channel in channels)
          SimpleDialogOption(
            key: ValueKey('allChannels $channel'),
            onPressed: () => Navigator.pop(context, channel),
            child: Text(label(channel)),
          ),
      ],
    ),
  );
  if (picked != null) onPick(picked);
}

/// [names] without blank names, each trimmed; what [channelNamesSetting]
/// holds.
Map<String, String> cleanChannelNames(Map<String, String> names) =>
    Map.unmodifiable({
      for (final MapEntry(:key, :value) in names.entries)
        if (key.isNotEmpty && value.trim().isNotEmpty) key: value.trim(),
    });

/// The longest name a channel can be given.
const int maximumChannelNameLength = 40;

/// The most channels named or starred that settings keep.
const int maximumSettingsChannels = 500;

/// [channelNamesSetting] from `settings.json`'s `channelNames`: string names
/// of string channels, each at most [maximumChannelNameLength] long and at
/// most [maximumSettingsChannels]; anything else is left out.
Map<String, String> readChannelNames(Object? json) {
  if (json is! Map) return const {};
  final names = <String, String>{};
  for (final MapEntry(:key, :value) in json.entries) {
    if (names.length == maximumSettingsChannels) break;
    if (key is! String || value is! String) continue;
    final name = value.trim();
    names[key] = name.length > maximumChannelNameLength
        ? name.substring(0, maximumChannelNameLength)
        : name;
  }
  return cleanChannelNames(names);
}

/// [listedChannelsSetting] from `settings.json`'s `listedChannels`: string
/// channels, once each, at most [maximumSettingsChannels].
List<String> readListedChannels(Object? json) {
  if (json is! List) return const [];
  return List.unmodifiable(
    {
      for (final channel in json)
        if (channel is String && channel.isNotEmpty) channel,
    }.take(maximumSettingsChannels),
  );
}

/// Gives [channel] the name [name]; a blank name returns it to the recorded
/// one.
void setChannelName(String channel, String name) {
  channelNamesSetting.value = cleanChannelNames({
    ...channelNamesSetting.value,
    channel: name,
  });
}

/// The name the driver gave [channel], or [channel] as recorded.
String channelDisplayName(String channel) =>
    channelNamesSetting.value[channel] ?? channel;

/// Rebuilds what shows a channel's name when [channelNamesSetting] changes;
/// put above the app's navigator.
class ChannelNamesScope
    extends InheritedNotifier<ValueNotifier<Map<String, String>>> {
  ChannelNamesScope({super.key, required super.child})
    : super(notifier: channelNamesSetting);
}

/// [channelDisplayName], rebuilding [context] when a name changes.
String channelNameOf(BuildContext context, String channel) {
  context.dependOnInheritedWidgetOfExactType<ChannelNamesScope>();
  return channelDisplayName(channel);
}

/// Every recorded channel of the open day, and every channel already given a
/// name, each with a field for the name shown in place of the recorded one.
class ChannelNamesPage extends StatefulWidget {
  const ChannelNamesPage({super.key});

  @override
  State<ChannelNamesPage> createState() => _ChannelNamesPageState();
}

class _ChannelNamesPageState extends State<ChannelNamesPage> {
  // Every channel listed since the page opened: a field emptied while typing
  // keeps its row.
  final Set<String> _listed = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.channelNamesTitle)),
      body: ValueListenableBuilder(
        valueListenable: channelNamesSetting,
        builder: (context, names, _) {
          _listed.addAll([
            ...dayRecordedChannels,
            ...names.keys,
            ...listedChannelsSetting.value,
          ]);
          final channels = _listed.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return ReadableListView(
            children: [
              Text(l10n.channelNamesHelp, style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                l10n.channelNamesListedHelp,
                style: theme.textTheme.bodySmall,
              ),
              ValueListenableBuilder(
                valueListenable: listedChannelsSetting,
                builder: (context, listed, _) => listed.isEmpty
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const ValueKey('channelListedClear'),
                          onPressed: () =>
                              listedChannelsSetting.value = const [],
                          child: Text(l10n.channelListedClear),
                        ),
                      ),
              ),
              if (dayRecordedChannels.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.channelNamesNoDay,
                  key: const ValueKey('channelNamesNoDay'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              for (final channel in channels)
                _ChannelNameField(
                  key: ValueKey('channelName $channel'),
                  channel: channel,
                  name: names[channel] ?? '',
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ChannelNameField extends StatefulWidget {
  const _ChannelNameField({
    super.key,
    required this.channel,
    required this.name,
  });

  final String channel;
  final String name;

  @override
  State<_ChannelNameField> createState() => _ChannelNameFieldState();
}

class _ChannelNameFieldState extends State<_ChannelNameField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.name,
  );

  @override
  void didUpdateWidget(_ChannelNameField old) {
    super.didUpdateWidget(old);
    // A name changed elsewhere (cleared here) shows; typing is not undone.
    if (widget.name != _text.text.trim()) _text.text = widget.name;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: _field(l10n)),
          ValueListenableBuilder(
            valueListenable: listedChannelsSetting,
            builder: (context, listed, _) {
              final on = listed.contains(widget.channel);
              return IconButton(
                key: ValueKey('channelListed ${widget.channel}'),
                tooltip: on ? l10n.channelListedOn : l10n.channelListedOff,
                isSelected: on,
                icon: const Icon(Icons.star_border),
                selectedIcon: const Icon(Icons.star),
                onPressed: () => setChannelListed(widget.channel, !on),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _field(AppLocalizations l10n) => TextField(
    key: ValueKey('channelNameField ${widget.channel}'),
    controller: _text,
    textInputAction: TextInputAction.done,
    maxLength: maximumChannelNameLength,
    decoration: InputDecoration(
      labelText: widget.channel,
      // The limit is enforced quietly; a counter on every row is noise.
      counterText: '',
      hintText: widget.channel,
      helperText: widget.name.isEmpty
          ? l10n.channelNamesRecordedName
          : l10n.channelNamesShownAs(widget.name),
      suffixIcon: widget.name.isEmpty
          ? null
          : IconButton(
              key: ValueKey('channelNameClear ${widget.channel}'),
              tooltip: l10n.channelNamesClear,
              icon: const Icon(Icons.close),
              onPressed: () => setChannelName(widget.channel, ''),
            ),
    ),
    onChanged: (value) => setChannelName(widget.channel, value),
  );
}

/// A channel as a list of channels names it: "Throttle · accelerator_pos-obd"
/// once named, else the recorded name.
String channelLabelOf(BuildContext context, String channel) {
  final name = channelNameOf(context, channel);
  return name == channel ? channel : '$name · $channel';
}

/// [channels] with [channel] replaced by [picked], in its place.
List<String> replaceChannel(
  List<String> channels,
  String channel,
  String picked,
) => [
  for (final shown in channels)
    if (shown == channel) picked else if (shown != picked) shown,
];
