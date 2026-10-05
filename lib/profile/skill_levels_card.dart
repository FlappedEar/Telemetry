import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'profile_library.dart';

/// A skill's measured value with its unit: "6.4 m", "1.85 s".
String skillValueText(SkillLevel level) {
  final value = level.value;
  if (value == null) return '';
  final unit = level.skill.unit;
  return '${fixed(value, unit == 's' ? 2 : 1)}$unitSpace$unit';
}

/// [library]'s skill levels as a [SkillLevelsCard], worked out once per
/// profile; nothing while the profile has no days.
class ProfileSkillLevels extends StatefulWidget {
  const ProfileSkillLevels({
    super.key,
    required this.library,
    this.padding = EdgeInsets.zero,
  });

  final ProfileLibrary library;

  /// Around the card, when it shows.
  final EdgeInsets padding;

  @override
  State<ProfileSkillLevels> createState() => _ProfileSkillLevelsState();
}

class _ProfileSkillLevelsState extends State<ProfileSkillLevels> {
  DriverProfile? _profile;
  List<SkillLevel> _levels = const [];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final profile = widget.library.profile;
      if (profile == null || profile.days.isEmpty) {
        return const SizedBox.shrink();
      }
      // The profile is replaced on every change, so its identity is enough.
      if (!identical(profile, _profile)) {
        _profile = profile;
        _levels = skillLevels(profile);
      }
      return Padding(
        padding: widget.padding,
        child: SkillLevelsCard(levels: _levels),
      );
    },
  );
}

/// The driver's skills, level 1–5 each, grouped as the model groups them.
/// Every level shows what was measured and how sure it is; a skill with no
/// level says why.
class SkillLevelsCard extends StatelessWidget {
  const SkillLevelsCard({super.key, required this.levels});

  /// From `skillLevels`, in catalogue order.
  final List<SkillLevel> levels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final groups = <SkillGroup, List<SkillLevel>>{};
    for (final level in levels) {
      (groups[level.skill.group] ??= []).add(level);
    }
    return Card(
      key: const ValueKey('skillLevels'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.profileSkills, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.profileSkillsIntro, style: theme.textTheme.bodySmall),
            for (final MapEntry(key: group, value: skills)
                in groups.entries) ...[
              const SizedBox(height: 16),
              Text(
                l10n.skillGroup(group.name),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              for (final level in skills) _SkillRow(level: level),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({required this.level});

  final SkillLevel level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final id = level.skill.id;
    final value = level.level;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final details = value == null
        ? [
            level.skill.measured
                ? l10n.skillNeedsEvidence
                : l10n.skillNotMeasured,
          ]
        : [
            l10n.skillLevel(value),
            if (level.confidence case final confidence?)
              l10n.skillConfidence(confidence.name),
            l10n.skillEvidence(level.rankedLaps, level.days),
            if (level.trend case final trend?) l10n.skillTrend(trend.name),
          ];
    return Padding(
      key: ValueKey('skill $id'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.skillName(id),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              // Five steps, the level's filled; drawn only with a level.
              if (value != null)
                ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var step = 1; step <= 5; ++step)
                        Container(
                          width: 14,
                          height: 8,
                          margin: const EdgeInsets.only(left: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: step <= value
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          Text(
            details.join(' · '),
            key: ValueKey('skillDetails $id'),
            style: muted,
          ),
          if (value != null && level.value != null)
            Text(
              l10n.skillMeasured(id, skillValueText(level)),
              key: ValueKey('skillValue $id'),
              style: muted,
            ),
        ],
      ),
    );
  }
}
