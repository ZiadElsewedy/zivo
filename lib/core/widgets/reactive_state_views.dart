import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// The three non-content states a reactive (stream-backed) surface can be in,
/// as one small shared vocabulary so every list/feed page renders them
/// identically: a first-load spinner, a stream error, and a calm empty state.
///
/// Before this, each surface inlined its own spinner and empty text (with
/// drifting alignment) and none handled `snapshot.hasError` at all — a failed
/// read silently looked like "you have nothing here". Routing all surfaces
/// through these keeps them consistent and makes the error case explicit.

/// Shown while a stream has not yet emitted its first value.
class LoadingStateView extends StatelessWidget {
  const LoadingStateView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.ink3),
    );
  }
}

/// The calm "nothing here yet" state. [message] is the surface's own copy
/// (e.g. 'No notes yet.', 'Nothing to do — enjoy the quiet.').
class EmptyStateView extends StatelessWidget {
  const EmptyStateView(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(message, style: AppText.aside, textAlign: TextAlign.center),
      ),
    );
  }
}

/// Shown when a reactive stream surfaces an error — a denied Firestore read, a
/// dropped connection, a decode failure. Deliberately distinct from
/// [EmptyStateView] so the user can tell "nothing here" apart from
/// "couldn't load this".
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({super.key, this.message = "Couldn't load this."});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 30, color: AppColors.ink3),
            const SizedBox(height: 12),
            Text(message, style: AppText.aside, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'Check your connection and try again in a moment.',
              style: AppText.meta.copyWith(color: AppColors.ink3),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
