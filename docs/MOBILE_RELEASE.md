# Bradford ERP mobile release guide

## Current application

- App name: `Bradford ERP`
- Application ID / bundle ID: `com.bradforderp.app`
- Web bundle: generated locally in `www/` and copied into each native application
- Production apps do not load a remote `server.url`

## Verification

```bash
npm ci
npm test
npm run test:mobile
npx cap sync
```

The `Build Android QA app` GitHub Actions workflow can create a debug APK for internal device testing. A debug APK must never be uploaded to Google Play as a production release.

## Android release

1. Install the supported Android Studio, Android SDK, JDK, and Node.js versions.
2. Run `npm ci`, `npm run test:mobile`, and `npx cap sync android`.
3. Create an upload key and protect it outside the repository.
4. Configure release signing using local protected properties or GitHub encrypted secrets.
5. Build a signed Android App Bundle with `./gradlew bundleRelease`.
6. Upload the `.aab` to an internal testing track first.
7. Complete Data safety, App access, target audience, content rating, and organization verification in Play Console.

Never commit the keystore, passwords, signing properties, Play service-account key, or production credentials.

## iOS release

1. Use a Mac with the supported Xcode version.
2. Run `npm ci`, `npm run test:mobile`, and `npx cap sync ios`.
3. Open the iOS project with `npm run mobile:ios`.
4. Select the organization’s Apple Developer team and verify the bundle ID.
5. Archive and upload the build to App Store Connect.
6. Test through TestFlight before App Review.
7. Complete App Privacy, age rating, review notes, export compliance, screenshots, and organization verification.

Never commit signing certificates, provisioning profiles, App Store Connect API private keys, or reviewer credentials.

## Release gates

- D-U-N-S and organization accounts completed.
- Privacy text approved and publicly reachable.
- Support and deletion URLs publicly reachable.
- Reviewer demo account works without production personal data.
- Login, MFA, file upload, downloads, printing, sharing, RTL layout, and logout tested on physical Android and iOS devices.
- No real HR, student, biometric, or financial information appears in store assets.
