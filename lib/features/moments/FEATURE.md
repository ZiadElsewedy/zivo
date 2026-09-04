# moments — feature map

> Local-first photo memories with optional cloud backup. **Bytes never go to Firestore** —
> media flows through the shared pipeline in [`core/media/`](../../core/media); Firestore
> holds only metadata. Read `core/media/` before touching storage here.

## Start here

- `presentation/pages/moments_timeline_page.dart` — the grid/timeline.
- `presentation/pages/moment_capture_page.dart` — capture/add (crop via `image_cropper`).
- `presentation/pages/photo_viewer_page.dart` — full-screen viewer.
- `presentation/moment_metadata.dart` — per-photo metadata mapping.

## Repository (`AppScope.moments`)

- **`MomentRepository`** (`domain/moment_repository.dart`) — `firestore_moment_repository.dart`
  / `in_memory_moment_repository.dart`. Entity: `domain/moment.dart`.

## Media pipeline (shared — [`core/media/`](../../core/media))

Photos are stored via `MediaService` → `LocalMediaStore` (durable copy under
`Documents/media/{kind}/{id}.ext`, addressed by a **relative** ref so it survives iOS
container-path changes) → `MediaRegistry` (metadata at `users/{uid}/media`) → optional
`GoogleDriveTarget` / device-gallery "Save to Photos". Display via
`core/media/presentation/media_image.dart`.

## Gotchas

- **`MediaService.capture` returns at the local copy.** The registry write, the
  "Save to Photos" copy and the Drive push all run on a background tail once the bytes
  are safe — a test that asserts on any of those must `await service.settleCaptures()`.
  The capture screen awaits only the copy (it needs the ref) and defers the Firestore
  write; see the save contract in [`capture/FEATURE.md`](../capture/FEATURE.md).
- **Never store a raw `image_picker` cache path or an absolute path** — that was the old
  bug; everything goes through `MediaService` and relative refs.
- Backup connection is per-account and reset on account switch (see [`app.dart`](../../app/app.dart)).
