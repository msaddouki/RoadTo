# Release signing (Android)

## Two keys

- **Upload key**: signs what CI builds. It lives in the repository secrets
  only (never in the repository, nor on a workstation once created), and in
  a backup the owner keeps (password manager).
- **App signing key**: with Google Play App Signing, Google keeps it and
  re-signs every release; phones only ever see this one. If the upload key
  leaks or is lost, Google can reset it (Play Console > Test and release >
  App integrity), the app keeps its identity.

Outside Google Play (an APK sent to testers), the upload key *is* the key
phones see: updates must be signed with it, so losing it means testers have
to uninstall and reinstall. Keep the backup.

## What CI does

In the "Android APK" job, on master and manual runs (not on pull requests,
which keep the debug key):

1. decodes the key from the secrets into the runner's temporary directory,
   removed at the end of the job;
2. builds the APK and, on master, the Play bundle (`.aab`), with the run
   number as version code, so each build is higher than the last;
3. checks the APK's signature (`apksigner`) and fails if the key was given
   but the APK still carries the debug certificate;
4. publishes `app-release.apk`, `app-release.aab` and `SHA256SUMS` as the
   `roadto-android-apk` artifact.

Without the secrets, the build goes on with the debug key and a warning.
`app/android/app/build.gradle.kts` reads the key from these environment
variables, so a local release build without them is debug-signed too.

| Secret | Content |
| --- | --- |
| `ANDROID_UPLOAD_KEYSTORE` | the keystore (`.jks`), base64 |
| `ANDROID_UPLOAD_KEYSTORE_PASSWORD` | its password |
| `ANDROID_UPLOAD_KEY_ALIAS` | the key's alias (`upload`) |
| `ANDROID_UPLOAD_KEY_PASSWORD` | the key's password |

## Creating the upload key

Once, on a trusted computer with a JDK (`keytool`) and `gh` logged in:

```sh
keytool -genkeypair -v -keystore upload.jks -alias upload \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=RoadTo, O=RoadTo, C=FR"
# Prompts for the passwords. Then:
base64 -w0 upload.jks | gh secret set ANDROID_UPLOAD_KEYSTORE -R msaddouki/RoadTo
gh secret set ANDROID_UPLOAD_KEYSTORE_PASSWORD -R msaddouki/RoadTo
gh secret set ANDROID_UPLOAD_KEY_ALIAS -R msaddouki/RoadTo -b upload
gh secret set ANDROID_UPLOAD_KEY_PASSWORD -R msaddouki/RoadTo
keytool -list -v -keystore upload.jks -alias upload | grep SHA256   # fingerprint
```

Put `upload.jks` and the passwords in the password manager, then delete the
file from the computer. The SHA-256 fingerprint goes into the Play Console
when the app is created, and is what the CI log prints for the APK.

## Before Google Play

- **Size**: Google Play refuses a bundle whose base module is over 200 MB
  compressed. The embedded Lyon region (map, places, routing graph) is about
  190 MB, so the Play build will have to download regions instead of
  embedding them (package host, ADR 0009). CI prints the bundle's size and
  warns above 200 MB. The APK for testers can keep the region.
- **Android Auto**: Google reviews car apps on the internal test track
  first.

## Later

- Move the upload key from the GitHub secrets to Vault, as the plan's rule
  says, once Vault runs.
- Reproducible builds: check that two builds of the same commit give the
  same APK contents (unsigned), so anyone can verify a release.
