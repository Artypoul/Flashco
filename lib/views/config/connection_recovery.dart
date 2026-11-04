import 'package:flashco/common/common.dart';
import 'package:flashco/models/models.dart';
import 'package:flashco/providers/config.dart';
import 'package:flashco/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

typedef ConnectionRecoveryChoice = ({
  bool? reconnect,
  bool? failover,
  int? interval,
});

enum _Mode { inherit, enabled, disabled }

class ConnectionRecoveryDialog extends StatefulWidget {
  const ConnectionRecoveryDialog({
    super.key,
    required this.initial,
    required this.global,
    this.allowInherit = true,
  });
  final ConnectionRecoveryChoice initial;
  final PatchClashConfig global;
  final bool allowInherit;

  @override
  State<ConnectionRecoveryDialog> createState() =>
      _ConnectionRecoveryDialogState();
}

class _ConnectionRecoveryDialogState extends State<ConnectionRecoveryDialog> {
  late bool? _reconnect = widget.initial.reconnect;
  late bool? _failover = widget.initial.failover;
  late final _interval = TextEditingController(
    text: widget.initial.interval?.toString() ?? '',
  );
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _interval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    Widget option(
      String title,
      bool? value,
      bool inherited,
      ValueChanged<bool?> changed,
    ) {
      String label(_Mode mode) => switch (mode) {
        _Mode.inherit => l.realityMlkemInherit(
          inherited ? l.enabled : l.disabled,
        ),
        _Mode.enabled => l.enabled,
        _Mode.disabled => l.disabled,
      };
      return ListItem<_Mode>.options(
        title: Text(title),
        subtitle: Text(
          label(
            value == null
                ? _Mode.inherit
                : value
                ? _Mode.enabled
                : _Mode.disabled,
          ),
        ),
        dialogTitle: title,
        options: [
          if (widget.allowInherit) _Mode.inherit,
          _Mode.enabled,
          _Mode.disabled,
        ],
        value: value == null
            ? _Mode.inherit
            : value
            ? _Mode.enabled
            : _Mode.disabled,
        textBuilder: label,
        onChanged: (mode) {
          if (mode != null) {
            setState(
              () => changed(switch (mode) {
                _Mode.inherit => null,
                _Mode.enabled => true,
                _Mode.disabled => false,
              }),
            );
          }
        },
      );
    }

    return CommonDialog(
      title: l.connectionRecovery,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.of(context).pop<ConnectionRecoveryChoice>((
                reconnect: _reconnect,
                failover: _failover,
                interval: int.tryParse(_interval.text.trim()),
              ));
            }
          },
          child: Text(l.confirm),
        ),
      ],
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.connectionRecoveryDesc),
            option(
              l.autoReconnect,
              _reconnect,
              widget.global.autoReconnect,
              (value) => _reconnect = value,
            ),
            option(
              l.autoFailover,
              _failover,
              widget.global.autoFailover,
              (value) => _failover = value,
            ),
            TextFormField(
              controller: _interval,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.recoveryInterval,
                hintText: widget.global.reconnectInterval.toString(),
              ),
              validator: (value) {
                if (widget.allowInherit && (value ?? '').trim().isEmpty) {
                  return null;
                }
                final seconds = int.tryParse((value ?? '').trim());
                return seconds != null && seconds >= 1 && seconds <= 3600
                    ? null
                    : l.recoveryIntervalError;
              },
            ),
          ],
        ),
      ),
    );
  }
}

class ConnectionRecoveryItem extends ConsumerWidget {
  const ConnectionRecoveryItem({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListItem(
      title: Text(context.appLocalizations.connectionRecovery),
      subtitle: Text(context.appLocalizations.connectionRecoveryDesc),
      onTap: () async {
        final global = ref.read(patchClashConfigProvider);
        final result = await dialogs.showCommonDialog<ConnectionRecoveryChoice>(
          child: ConnectionRecoveryDialog(
            global: global,
            initial: (
              reconnect: global.autoReconnect,
              failover: global.autoFailover,
              interval: global.reconnectInterval,
            ),
            allowInherit: false,
          ),
        );
        if (result == null || !context.mounted) return;
        ref
            .read(patchClashConfigProvider.notifier)
            .update(
              (state) => state.copyWith(
                autoReconnect: result.reconnect ?? state.autoReconnect,
                autoFailover: result.failover ?? state.autoFailover,
                reconnectInterval: result.interval ?? state.reconnectInterval,
              ),
            );
      },
    );
  }
}
