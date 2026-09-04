import 'dart:async';

import 'uid_source.dart';

/// A uid-scoped Firestore read, mirrored into a synchronous cache plus a
/// broadcast stream — the machinery every `Firestore<X>Repository` needs and
/// ten of them used to each spell out by hand.
///
/// ## What it replaces
///
/// Every Firestore-backed repository in this app is constructed **once at app
/// root, before sign-in**, so none of them can take a `uid` constructor
/// argument. Each therefore grew the same ~60 lines: hold a [UidSource],
/// re-open the query whenever the uid changes (including to and from
/// signed-out), cache the latest value so a synchronous `current` getter can
/// answer, and replay that cache to late subscribers. Ten repositories carried
/// that code; seven carried the same six-line explanatory comment verbatim.
/// The parts that actually differed were three lines: the collection path, the
/// `orderBy`, and the doc→domain mapper.
///
/// ## Why late subscribers get a replay
///
/// A broadcast stream never replays its latest value to a subscriber that
/// arrives after the fact. The Today dashboard subscribes first (it stays
/// alive in the shell's `IndexedStack`) and consumes the initial snapshot, so
/// a Hub detail page opened afterwards would otherwise sit on
/// `ConnectionState.waiting` forever whenever the collection is empty.
/// [watch] replays [current] on subscribe so every listener sees the current
/// value immediately — matching the in-memory repositories' contract, which
/// the pages and tests rely on.
///
/// ## Why the listener is always on
///
/// [start] is called from the owning repository's constructor and the
/// underlying Firestore listener then runs for the repository's whole
/// lifetime. It is deliberately **not** driven by `onListen`/`onCancel`.
///
/// Five repositories used to start on the first Flutter-side subscriber and
/// stop when the last one cancelled, which let the cache go stale behind a
/// scrolled-off-screen or torn-down widget: a write that landed while nothing
/// was subscribed had no listener to pick up the fresh snapshot, so the *next*
/// subscriber was replayed the STALE cached value first. That is the
/// Home/Workout-tab training-card drift, fixed in the workout repositories
/// (see `test/workout/firestore_workout_repos_stay_hot_test.dart`) and fixed
/// here for everyone else by construction. Repositories are singletons created
/// once at app root, so an unconditional listener costs one Firestore stream
/// per mirror per signed-in user — not one per widget.
///
/// ## Usage
///
/// ```dart
/// class FirestoreMomentRepository implements MomentRepository {
///   FirestoreMomentRepository({FirebaseFirestore? firestore, required this.uidSource})
///     : _firestore = firestore ?? FirebaseFirestore.instance {
///     _moments = UidScopedMirror<List<Moment>>(
///       uidSource: uidSource,
///       signedOutValue: const [],
///       source: (uid) => _collection(uid)
///           .orderBy('takenAt', descending: true)
///           .snapshots()
///           .map((s) => s.docs.map(_fromDoc).toList(growable: false)),
///     )..start();
///   }
/// }
/// ```
///
/// It is a held object rather than a superclass on purpose: a repository can
/// own **several** mirrors (the diet repository mirrors plans, targets and the
/// body profile independently), which a base class could not express.
class UidScopedMirror<T> {
  UidScopedMirror({
    required this.uidSource,
    required this.signedOutValue,
    required this.source,
  });

  final UidSource uidSource;

  /// What [current] reads as while no user is signed in — `const []` for a
  /// collection mirror, `null` for a single-document one.
  final T signedOutValue;

  /// Opens the Firestore read for [uid], already mapped to domain values.
  /// Called again on every uid change; the previous subscription is cancelled
  /// first.
  final Stream<T> Function(String uid) source;

  late T _value = signedOutValue;
  bool _hasSnapshot = false;

  final StreamController<T> _controller = StreamController<T>.broadcast();
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<T>? _sourceSub;

  /// The latest mirrored value, available synchronously and without waiting
  /// for a stream event. Reads [signedOutValue] before the first snapshot
  /// lands and after sign-out.
  ///
  /// Collection mirrors should wrap this in `List.unmodifiable` at the
  /// repository's own getter — the mirror hands back exactly what the mapper
  /// produced.
  T get current => _value;

  /// Whether a value has been emitted for the current session — i.e. whether
  /// [current] is a real answer rather than the not-yet-loaded default.
  bool get hasSnapshot => _hasSnapshot;

  /// The mirrored value over time, with [current] replayed to late
  /// subscribers. See the class doc for why the replay is load-bearing.
  Stream<T> watch() async* {
    if (_hasSnapshot) yield _value;
    yield* _controller.stream;
  }

  /// Begins mirroring. Call once, from the owning repository's constructor.
  void start() {
    _uidSub?.cancel();
    _uidSub = _uidWithInitial().listen(_onUidChanged);
  }

  /// Tears the mirror down — not called in production, where repositories
  /// live for the app's process lifetime, only for explicit teardown in
  /// tests.
  void dispose() {
    _uidSub?.cancel();
    _uidSub = null;
    _sourceSub?.cancel();
    _sourceSub = null;
    _controller.close();
  }

  /// [UidSource.uidChanges] only reports *changes*, so the uid that is already
  /// signed in at construction has to be yielded explicitly first.
  Stream<String?> _uidWithInitial() async* {
    yield uidSource.currentUid();
    yield* uidSource.uidChanges;
  }

  void _onUidChanged(String? uid) {
    _sourceSub?.cancel();
    _sourceSub = null;
    if (uid == null) {
      // Signing out clears the cache rather than leaving the previous user's
      // data readable through `current` — and a different user signing in
      // then starts from the empty value, never a bleed.
      _emit(signedOutValue);
      return;
    }
    _sourceSub = source(uid).listen(
      _emit,
      onError: (Object e, StackTrace s) {
        if (!_controller.isClosed) _controller.addError(e, s);
      },
    );
  }

  void _emit(T value) {
    _value = value;
    _hasSnapshot = true;
    if (!_controller.isClosed) _controller.add(value);
  }
}
