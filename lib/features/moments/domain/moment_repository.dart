import 'moment.dart';

/// The seam between the app and moment storage (in-memory demo for now).
abstract interface class MomentRepository {
  List<Moment> get current;
  Stream<List<Moment>> watchAll();
  Future<void> add(Moment moment);
}
