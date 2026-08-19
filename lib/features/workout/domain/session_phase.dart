/// The phase of a live [WorkoutSession].
///
/// - [running]   — actively performing the current set.
/// - [resting]   — between sets, counting down the just-completed set's rest.
/// - [completed] — the final set is done; the session can be logged to history.
/// - [abandoned] — the user quit before finishing.
///
/// [completed] and [abandoned] are terminal.
enum SessionPhase { running, resting, completed, abandoned }
