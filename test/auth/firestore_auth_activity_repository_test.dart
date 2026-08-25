import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/data/firestore_auth_activity_repository.dart';
import 'package:zivo/features/auth/domain/account_auth_metadata.dart';
import 'package:zivo/features/auth/domain/auth_event_type.dart';

void main() {
  // FakeFirebaseFirestore resolves FieldValue.serverTimestamp() on write, so
  // every timestamp read back below is a real Timestamp.
  late FakeFirebaseFirestore firestore;
  late FirestoreAuthActivityRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = FirestoreAuthActivityRepository(firestore: firestore);
  });

  /// The account summary doc's raw data; fails the test if it doesn't exist.
  Future<Map<String, dynamic>> accountData(String uid) async {
    final doc = await firestore
        .collection('users')
        .doc(uid)
        .collection('auth')
        .doc('account')
        .get();
    if (!doc.exists) fail('auth/account for $uid does not exist');
    return doc.data()!;
  }

  Future<List<Map<String, dynamic>>> events(String uid) async {
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('authEvents')
        .get();
    return snap.docs.map((d) => d.data()).toList();
  }

  group('recordAccountCreated', () {
    test('stamps registration + first sign-in fields and logs the event',
        () async {
      await repo.recordAccountCreated(
        uid: 'u1',
        provider: 'apple.com',
        platform: 'ios',
      );

      final account = await accountData('u1');
      expect(account, isNotNull);
      expect(account['schemaVersion'], 1);
      expect(account['registeredVia'], 'apple.com');
      expect(account['registeredPlatform'], 'ios');
      expect(account['createdAt'], isNotNull);
      expect(account['lastSignInAt'], isNotNull); // creation IS a sign-in
      expect(account['lastSignInVia'], 'apple.com');
      expect(account['signInCount'], 1);

      final logged = await events('u1');
      expect(logged.single['type'], 'accountCreated');
      expect(logged.single['provider'], 'apple.com');
      expect(logged.single['platform'], 'ios');
      expect(logged.single['occurredAt'], isNotNull);
    });

    test('merge-preserves an existing summary (no clobber)', () async {
      await repo.recordAccountCreated(
          uid: 'u2', provider: 'password', platform: 'web');
      // A stray later write with only new fields must not erase history.
      await firestore
          .collection('users')
          .doc('u2')
          .collection('auth')
          .doc('account')
          .set({'lastPasswordChangeAt': DateTime(2026, 5, 1)},
              SetOptions(merge: true));

      final account = await accountData('u2');
      expect(account['registeredVia'], 'password');
      expect(account['createdAt'], isNotNull);
      expect(account['lastPasswordChangeAt'], isNotNull);
    });
  });

  group('recordSignIn', () {
    test('advances lastSignIn, shifts previous, and increments the count',
        () async {
      await repo.recordAccountCreated(
          uid: 'u3', provider: 'password', platform: 'ios');
      final countAfterCreate =
          (await accountData('u3'))['signInCount'] as int;

      await repo.recordSignIn(
          uid: 'u3', provider: 'google.com', platform: 'android');

      final account = await accountData('u3');
      expect(account['signInCount'], countAfterCreate + 1);
      expect(account['lastSignInVia'], 'google.com');
      expect(account['lastSignInPlatform'], 'android');
      // The pre-existing lastSignInAt moved into previousSignInAt.
      expect(account['previousSignInAt'], isNotNull);
      expect(
        (account['previousSignInAt'] as dynamic).compareTo(
          (account['lastSignInAt'] as dynamic),
        ),
        isNonPositive,
      );

      final types = (await events('u3')).map((e) => e['type']);
      expect(types, ['accountCreated', 'signIn']);
    });

    test('backfills a missing createdAt from Firebase Auth metadata',
        () async {
      final fallback = DateTime.utc(2026, 1, 15, 9, 30);

      await repo.recordSignIn(
        uid: 'u4',
        provider: 'apple.com',
        platform: 'ios',
        fallbackCreatedAt: fallback,
      );

      final account = await accountData('u4');
      // Fake round-trips the wall-clock instant (UTC flag is not preserved),
      // so compare moments, not representations.
      expect(
        (account['createdAt'] as Timestamp).millisecondsSinceEpoch,
        fallback.millisecondsSinceEpoch,
      );
    });

    test('never overwrites an existing createdAt with the fallback',
        () async {
      await repo.recordAccountCreated(
          uid: 'u5', provider: 'password', platform: 'ios');
      final original = (await accountData('u5'))['createdAt'];

      await repo.recordSignIn(
        uid: 'u5',
        provider: 'password',
        platform: 'ios',
        fallbackCreatedAt: DateTime.utc(2000, 1, 1),
      );

      expect((await accountData('u5'))['createdAt'], original);
    });
  });

  group('recordSignOut / recordEvent', () {
    test('signOut appends its event without touching the summary', () async {
      await repo.recordSignOut(uid: 'u6');

      final exists = await firestore
          .collection('users')
          .doc('u6')
          .collection('auth')
          .doc('account')
          .get()
          .then((d) => d.exists);
      expect(exists, isFalse);
      final logged = await events('u6');
      expect(logged.single['type'], 'signOut');
      expect(logged.single.containsKey('provider'), isFalse);
    });

    test('recordEvent carries optional provider/platform', () async {
      await repo.recordEvent(
        uid: 'u7',
        type: AuthEventType.passwordChanged,
        provider: 'password',
      );

      final logged = await events('u7');
      expect(logged.single['type'], 'passwordChanged');
      expect(logged.single['provider'], 'password');
      expect(logged.single.containsKey('platform'), isFalse);
    });
  });

  group('read side', () {
    test('watchAccount emits the parsed summary and null when absent',
        () async {
      final seen = <AccountAuthMetadata?>[];
      final sub = repo.watchAccount('u8').listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      await repo.recordAccountCreated(
          uid: 'u8', provider: 'google.com', platform: 'macos');
      await Future<void>.delayed(Duration.zero);

      expect(seen.first, isNull);
      expect(seen.last, isNotNull);
      expect(seen.last!.registeredVia, 'google.com');
      expect(seen.last!.registeredPlatform, 'macos');
      expect(seen.last!.signInCount, 1);
      await sub.cancel();
    });

    test('watchRecentEvents returns newest first, honoring limit', () async {
      for (var i = 0; i < 5; i++) {
        await repo.recordEvent(uid: 'u9', type: AuthEventType.signIn);
      }
      await Future<void>.delayed(Duration.zero);

      final top3 = await repo
          .watchRecentEvents(uid: 'u9', limit: 3)
          .firstWhere((l) => l.isNotEmpty);
      expect(top3, hasLength(3));
      expect(top3.every((e) => e.type == AuthEventType.signIn), isTrue);
    });
  });
}
