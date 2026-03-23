# B-Roll Downloader

Native macOS internal app for downloading YouTube b-roll into `~/Downloads/B-Roll`.

## Current direction

This project has been rebuilt as a native Swift/SwiftUI Mac app.

The working app now lives under:

- `NativeMacApp/`

The packaged local bundle is produced at:

- `native-dist/B-Roll Downloader.app`

## What the app currently does

- accepts multiple YouTube URLs
- normalizes and de-dupes only within the current pasted batch
- requires project name by default, with 30-day recent suggestions
- downloads the best available source with `yt-dlp`
- keeps original media when already Premiere-friendly
- remuxes when a container fix is enough
- transcodes only when codec compatibility actually requires it
- saves to `~/Downloads/B-Roll`
- uses archival filenames:
  - `Title - Channel - YYYY-MM-DD - [VideoID] [ShortCode] - Project Name.mp4`
- supports queueing, per-item cancel, abort cleanup, and completion beep

## Tool bootstrap

On launch, the app checks for:

- `yt-dlp`
- `ffmpeg`
- `ffprobe`

It prefers:

1. bundled app tools if they exist
2. system-installed tools if the Mac already has them
3. app-managed downloads of only the missing tools

Managed tools are stored in the app support directory, not inside the user-facing Downloads folder.

## Update behavior

For now:

- local builds identify themselves as `local`
- local builds skip automatic GitHub update prompting
- release builds can check GitHub Releases and surface a native update prompt

Phase 1 intentionally prioritizes a working app over signed/notarized self-updating distribution.

## Build locally

```bash
./scripts/build-native-app.sh
```

Optional overrides:

```bash
APP_VERSION=1.0.3 BUILD_CHANNEL=release ./scripts/build-native-app.sh
```

## Package a release zip

```bash
APP_VERSION=1.0.3 ./scripts/package-native-release.sh
```

That produces:

- `release-artifacts/B-Roll-Downloader-v1.0.3.zip`

## Streamlined future releases

This repo now has a simple native release workflow.

### 1. Bump the app version

```bash
./scripts/bump-version.sh 1.0.4
```

That updates:

- `VERSION`

### 2. Commit and push your feature work

```bash
git add .
git commit -m "Release v1.0.4"
git push
```

### 3. Push a release tag

```bash
git tag v1.0.4
git push origin v1.0.4
```

### 4. Let GitHub build the downloadable app

There is now a GitHub Actions workflow at:

- `.github/workflows/native-release.yml`

When you push a tag like `v1.0.4`, GitHub will:

- build the native macOS app
- package the zip
- create or update the GitHub Release
- attach the release zip automatically

That means future app updates can be shipped without manually building/uploading every release on your own machine unless you want to.

## Notes

- The old Electron path has been retired from the working build.
- Unsigned internal Mac distribution can still hit Gatekeeper friction on other machines.
- Proper friction-free teammate distribution later would require Apple Developer signing/notarization.
