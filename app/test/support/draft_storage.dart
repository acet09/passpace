import 'package:passpace_mobile/data/plan_draft.dart';

class MemoryDraftStorage implements PlanDraftStorage {
  final Map<String, String> values = {};
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String? value) async {
    if (failWrites) throw StateError('fixture storage unavailable');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}
