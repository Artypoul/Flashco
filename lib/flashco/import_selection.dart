import 'package:flashco/common/compute.dart';
import 'package:flashco/enum/enum.dart';
import 'package:flashco/models/models.dart';

Map<String, String> importDefaultSelections(
  List<Group> groups,
  Map<String, String> existing,
) => {
  for (final mode in [Mode.rule, Mode.global])
    if (fastestChoice(groups, mode) case final choice?)
      choice.selector.name: choice.automatic.name,
  ...existing,
};
