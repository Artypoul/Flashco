import 'package:flashco/common/common.dart';
import 'package:flashco/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

typedef RealityMlkemSelection = ({bool? enabled, Map<String, bool> nodes});

enum _MlkemMode { inherit, enabled, disabled }

class RealityMlkemDialog extends StatefulWidget {
  const RealityMlkemDialog({
    super.key,
    required this.nodes,
    required this.overrides,
    required this.inheritedEnabled,
    this.enabled,
  });

  final List<RealityMlkemNode> nodes;
  final Map<String, bool> overrides;
  final bool inheritedEnabled;
  final bool? enabled;

  @override
  State<RealityMlkemDialog> createState() => _RealityMlkemDialogState();
}

class _RealityMlkemDialogState extends State<RealityMlkemDialog> {
  late final _overrides = Map<String, bool>.from(widget.overrides);
  late bool? _enabled = widget.enabled;

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    _MlkemMode selected(bool? value) => switch (value) {
      true => _MlkemMode.enabled,
      false => _MlkemMode.disabled,
      null => _MlkemMode.inherit,
    };
    Widget choice({
      required Key key,
      required String title,
      required bool? value,
      required bool inherited,
      required ValueChanged<bool?> onChanged,
    }) {
      String label(_MlkemMode mode) => switch (mode) {
        _MlkemMode.inherit => l.realityMlkemInherit(
          inherited ? l.enabled : l.disabled,
        ),
        _MlkemMode.enabled => l.enabled,
        _MlkemMode.disabled => l.disabled,
      };
      return ListItem<_MlkemMode>.options(
        key: key,
        title: Text(title),
        subtitle: Text(label(selected(value))),
        dialogTitle: title,
        options: _MlkemMode.values,
        value: selected(value),
        textBuilder: label,
        onChanged: (mode) {
          if (mode == null) return;
          setState(
            () => onChanged(switch (mode) {
              _MlkemMode.inherit => null,
              _MlkemMode.enabled => true,
              _MlkemMode.disabled => false,
            }),
          );
        },
      );
    }

    return CommonDialog(
      title: 'REALITY · ML-KEM',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop<RealityMlkemSelection>((enabled: _enabled, nodes: _overrides)),
          child: Text(l.confirm),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.realityMlkemDescription),
          const SizedBox(height: 16),
          choice(
            key: const ValueKey('profile-default'),
            title: l.realityMlkemProfile,
            value: _enabled,
            inherited: widget.inheritedEnabled,
            onChanged: (value) => _enabled = value,
          ),
          if (widget.nodes.isEmpty) Text(l.noData),
          for (final node in widget.nodes)
            choice(
              key: ValueKey(node.key),
              title: node.name,
              value: _overrides[node.key],
              inherited: _enabled ?? widget.inheritedEnabled,
              onChanged: (value) {
                if (value == null) {
                  _overrides.remove(node.key);
                } else {
                  _overrides[node.key] = value;
                }
              },
            ),
        ],
      ),
    );
  }
}
