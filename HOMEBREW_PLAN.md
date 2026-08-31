# Homebrew Distribution Plan

## Overview

There are two ways to distribute TimeOn via Homebrew:

1. **Homebrew Cask** (recommended for GUI apps) — distributes a pre-built `.app` bundle
2. **Homebrew Formula** (build from source) — compiles from Swift source on install

Both approaches use a **personal Homebrew tap** (a GitHub repo).

---

## Option A: Homebrew Cask (Recommended)

### Steps

1. **Create a GitHub repo** for the app source:
   ```sh
   gh repo create time-on --public --source=. --push
   ```

2. **Create a release with a zipped .app**:
   ```sh
   make app
   cd .build/release
   zip -r TimeOn.app.zip TimeOn.app
   gh release create v1.0.0 TimeOn.app.zip --title "v1.0.0" --notes "Initial release"
   ```

3. **Get the SHA256 of the zip**:
   ```sh
   shasum -a 256 .build/release/TimeOn.app.zip
   ```

4. **Create a Homebrew tap repo**:
   ```sh
   gh repo create homebrew-tap --public
   git clone https://github.com/thomasjebsen/homebrew-tap.git
   mkdir -p homebrew-tap/Casks
   ```

5. **Copy and update the cask file**:
   ```sh
   cp Casks/time-on.rb homebrew-tap/Casks/time-on.rb
   # Edit: replace thomasjebsen and PLACEHOLDER_SHA256
   cd homebrew-tap && git add . && git commit -m "Add TimeOn cask" && git push
   ```

6. **Users install with**:
   ```sh
   brew install --cask thomasjebsen/tap/time-on
   ```

### Release Automation (GitHub Actions)

This is already implemented in `.github/workflows/release.yml`. Pushing a `v*`
tag builds the app, stamps the bundle version from the tag, zips it, computes the
SHA256, updates this repo's `Casks/time-on.rb` (version + sha256) automatically,
and publishes the GitHub Release (with the SHA in the release notes).

The remaining manual step is syncing the updated `Casks/time-on.rb` into the
separate `homebrew-tap` repo that users actually install from (cross-repo pushes
need a token that isn't configured here).

---

## Option B: Homebrew Formula (Build from Source)

### Steps

1. **Create the source repo and tag a release** (same as above steps 1-2, but no zip needed).

2. **Create the tap repo with a Formula directory**:
   ```sh
   gh repo create homebrew-tap --public
   mkdir -p homebrew-tap/Formula
   cp Formula/time-on.rb homebrew-tap/Formula/time-on.rb
   ```

3. **Get the SHA256 of the source tarball**:
   ```sh
   curl -sL https://github.com/thomasjebsen/time-on/archive/refs/tags/v1.0.0.tar.gz | shasum -a 256
   ```

4. **Update the formula** with the real SHA256 and username.

5. **Users install with**:
   ```sh
   brew install thomasjebsen/tap/time-on
   ```

---

## Submitting to Homebrew Core / Homebrew Cask (Official)

For inclusion in the **official Homebrew repositories** (so users can `brew install --cask time-on` without a tap):

### Requirements
- The app must be **notable** (significant user base, press coverage, or GitHub stars)
- Must have a **stable versioned release** on GitHub
- The cask must pass `brew audit --cask time-on`
- Source must be open and the binary must match the source

### Process
1. Fork [homebrew-cask](https://github.com/Homebrew/homebrew-cask)
2. Add `Casks/t/time-on.rb` following their template
3. Run `brew audit --cask time-on` and `brew style --fix Casks/t/time-on.rb`
4. Open a PR

### Realistic Timeline
- **Personal tap**: Ready immediately (today)
- **Official Homebrew Cask**: After gaining traction (100+ GitHub stars is a good threshold)

---

## Quick Start (Personal Tap)

```sh
# 1. Push source to GitHub
git init && git add . && git commit -m "Initial commit"
gh repo create time-on --public --source=. --push

# 2. Build and release
make app
cd .build/release && zip -r TimeOn.app.zip TimeOn.app && cd ../..
gh release create v1.0.0 .build/release/TimeOn.app.zip --title "v1.0.0"

# 3. Create tap
gh repo create homebrew-tap --public
# ... add cask with correct sha256 and push

# 4. Users install
brew install --cask thomasjebsen/tap/time-on
```
