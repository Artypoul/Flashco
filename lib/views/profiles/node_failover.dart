import 'package:flashco/common/common.dart';
import 'package:flashco/models/models.dart';
import 'package:flashco/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

typedef NodeFailoverSelection = ({ProfileNodeFailover? pair});

class NodeFailoverDialog extends StatefulWidget {
  const NodeFailoverDialog({
    super.key,
    required this.nodes,
    required this.groups,
    this.initial,
  });

  final List<ProfileFailoverNode> nodes;
  final List<String> groups;
  final ProfileNodeFailover? initial;

  @override
  State<NodeFailoverDialog> createState() => _NodeFailoverDialogState();
}

class _NodeFailoverDialogState extends State<NodeFailoverDialog> {
  late bool _enabled = widget.initial?.enabled ?? false;
  late String? _group =
      widget.initial?.groupName ??
      (widget.groups.length == 1 ? widget.groups.single : null);
  late String? _primary = widget.initial?.primaryKey;
  late String? _backup = widget.initial?.backupKey;

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final nodes = {for (final node in widget.nodes) node.key: node};
    final valid =
        _group != null &&
        _primary != null &&
        _backup != null &&
        _primary != _backup;
    String nodeName(String? key, String? saved) =>
        nodes[key]?.name ??
        (key == null
            ? l.nodeFailoverChoose
            : '${saved ?? l.noData} · ${l.nodeFailoverMissing}');
    return CommonDialog(
      title: l.nodeFailover,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        if (widget.initial != null)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop<NodeFailoverSelection>((pair: null)),
            child: Text(l.reset),
          ),
        FilledButton(
          onPressed: _enabled && !valid
              ? null
              : () {
                  final pair = !valid
                      ? widget.initial?.copyWith(enabled: false)
                      : ProfileNodeFailover(
                          enabled: _enabled,
                          groupName: _group!,
                          primaryKey: _primary!,
                          backupKey: _backup!,
                          primaryName:
                              nodes[_primary]?.name ??
                              widget.initial!.primaryName,
                          backupName:
                              nodes[_backup]?.name ??
                              widget.initial!.backupName,
                        );
                  Navigator.of(
                    context,
                  ).pop<NodeFailoverSelection>((pair: pair));
                },
          child: Text(l.confirm),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.nodeFailoverDescription),
          ListItem.toggle(
            title: Text(l.nodeFailover),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          if (_enabled) ...[
            ListItem<String?>.options(
              key: const ValueKey('failover-group'),
              title: Text(l.proxyGroup),
              subtitle: Text(_group ?? l.nodeFailoverChoose),
              dialogTitle: l.proxyGroup,
              options: widget.groups,
              value: _group,
              textBuilder: (value) => value ?? l.nodeFailoverChoose,
              onChanged: (value) => setState(() => _group = value),
            ),
            ListItem<String?>.options(
              key: const ValueKey('failover-primary'),
              title: Text(l.nodeFailoverPrimary),
              subtitle: Text(nodeName(_primary, widget.initial?.primaryName)),
              dialogTitle: l.nodeFailoverPrimary,
              options: nodes.keys.toList(),
              value: _primary,
              textBuilder: (value) =>
                  nodes[value]?.name ?? l.nodeFailoverChoose,
              onChanged: (value) => setState(() {
                _primary = value;
                if (_backup == value) _backup = null;
              }),
            ),
            ListItem<String?>.options(
              key: const ValueKey('failover-backup'),
              title: Text(l.nodeFailoverBackup),
              subtitle: Text(nodeName(_backup, widget.initial?.backupName)),
              dialogTitle: l.nodeFailoverBackup,
              options: nodes.keys.toList(),
              value: _backup,
              textBuilder: (value) =>
                  nodes[value]?.name ?? l.nodeFailoverChoose,
              onChanged: (value) => setState(() {
                _backup = value;
                if (_primary == value) _primary = null;
              }),
            ),
            if (widget.nodes.isEmpty ||
                widget.groups.isEmpty ||
                (_group != null && !widget.groups.contains(_group)) ||
                (_primary != null && !nodes.containsKey(_primary)) ||
                (_backup != null && !nodes.containsKey(_backup)))
              Text(l.nodeFailoverMissingDescription),
          ],
        ],
      ),
    );
  }
}
