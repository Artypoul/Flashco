import 'dart:async';

import 'package:flashco/common/common.dart';
import 'package:flashco/enum/enum.dart';
import 'package:flashco/models/models.dart';
import 'package:flashco/providers/providers.dart';
import 'package:flashco/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';
import 'tab.dart';

class SafeGroupView extends ConsumerStatefulWidget {
  const SafeGroupView({
    super.key,
    required this.group,
    required this.controller,
    required this.columns,
    required this.cardType,
  });
  final Group group;
  final ScrollController controller;
  final int columns;
  final ProxyCardType cardType;

  @override
  ConsumerState<SafeGroupView> createState() => _SafeGroupViewState();
}

class _SafeGroupViewState extends ConsumerState<SafeGroupView> {
  bool _backup = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SafeControls(
        backup: _backup,
        onChanged: (value) => setState(() => _backup = value),
      ),
      Expanded(
        child: ProxyGroupView(
          group: widget.group,
          controller: widget.controller,
          columns: widget.columns,
          cardType: widget.cardType,
          cardBuilder: (proxy) => SafeNodeCard(
            group: widget.group,
            proxy: proxy,
            cardType: widget.cardType,
            backup: _backup,
          ),
        ),
      ),
    ],
  );
}

class SafeControls extends ConsumerWidget {
  const SafeControls({
    super.key,
    required this.backup,
    required this.onChanged,
  });
  final bool backup;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final data = ref.watch(safeProfileConfigProvider);
    final config = data.asData?.value;
    if (config == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: data.hasError
            ? TextButton(
                onPressed: () => ref.invalidate(safeProfileConfigProvider),
                child: Text(l.retry),
              )
            : const LinearProgressIndicator(),
      );
    }
    final nodes = safeProfileNodes(config);
    if (nodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(l.safeNoNodes),
      );
    }
    final pair = ref.watch(
      currentProfileProvider.select((p) => p?.overrides.nodeFailover),
    );
    final primary = pair?.primaryKey ?? nodes.first.key;
    final reserve = pair?.backupKey ?? '';
    String label(String key, String? saved) =>
        nodes.where((node) => node.key == key).firstOrNull?.name ??
        '${saved ?? l.noData} · ${l.nodeFailoverMissing}';
    final interval =
        ref.watch(currentProfileProvider)?.overrides.reconnectInterval ??
        ref.watch(patchClashConfigProvider).reconnectInterval;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: Text(l.nodeFailoverPrimary),
                selected: !backup,
                onSelected: (_) => onChanged(false),
              ),
              ChoiceChip(
                label: Text(l.nodeFailoverBackup),
                selected: backup,
                onSelected: (_) => onChanged(true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          EmojiText(
            '${label(primary, pair?.primaryName)} → ${reserve.isEmpty ? l.safeAutomatic : label(reserve, pair?.backupName)}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          Text(l.safeHint(interval), style: context.textTheme.bodySmall),
          Text(
            pair?.enabled == true ? l.safeActive : l.safeReady,
            style: context.textTheme.bodySmall,
          ),
          if (backup && reserve.isNotEmpty)
            TextButton(
              onPressed: () => unawaited(
                ref
                    .read(proxiesActionProvider.notifier)
                    .selectSafeNode(backup: true),
              ),
              child: Text(l.safeAutomatic),
            ),
        ],
      ),
    );
  }
}

class SafeNodeCard extends ConsumerWidget {
  const SafeNodeCard({
    super.key,
    required this.group,
    required this.proxy,
    required this.cardType,
    required this.backup,
  });
  final Group group;
  final Proxy proxy;
  final ProxyCardType cardType;
  final bool backup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(safeProfileConfigProvider).asData?.value;
    final nodes = config == null
        ? <ProfileFailoverNode>[]
        : safeProfileNodes(config);
    final node = nodes.where((node) => node.name == proxy.name).firstOrNull;
    final pair = ref.watch(
      currentProfileProvider.select((p) => p?.overrides.nodeFailover),
    );
    final primary = pair?.primaryKey ?? nodes.firstOrNull?.key;
    final isPrimary = node != null && node.key == primary;
    final isBackup = node != null && node.key == pair?.backupKey;
    final l = context.appLocalizations;
    return ProxyCard(
      groupName: group.name,
      testUrl: group.testUrl,
      proxy: proxy,
      groupType: GroupType.Fallback,
      type: cardType,
      selected: backup ? isBackup : isPrimary,
      showComputedMark: pair?.enabled == true,
      computedSelected:
          ref.watch(selectedProxyNameProvider(group.name)) == proxy.name,
      roleLabel: isPrimary
          ? l.nodeFailoverPrimary
          : isBackup
          ? l.nodeFailoverBackup
          : null,
      onSelect: () {
        if (node != null) {
          unawaited(
            ref
                .read(proxiesActionProvider.notifier)
                .selectSafeNode(nodeKey: node.key, backup: backup),
          );
        }
      },
    );
  }
}
