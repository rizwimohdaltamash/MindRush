# Challenge links

A friend challenge is a URL and nothing else. It carries the deck seed and
difficulty (which rebuild the identical questions) plus the sender's name and
score (which the receiver plays against). There is no server, no lobby and no
live connection between the two phones -- the link *is* the connection.

    https://mindrush-d92c3.web.app/c/sprint-849213?d=3&by=Naman&av=2&s=150&t=57310

## Getting the app onto a friend's phone

Firebase Hosting **refuses to serve executables on the Spark plan**, so the APK
cannot live next to this page:

    Error: HTTP Error: 400, Executable files are forbidden on the Spark
    billing plan.

`firebase.json` ignores `**/*.apk` so a stray build can never block a deploy
again. Pick one of these instead:

1. **Send the APK on WhatsApp**, in the same chat as the invite. It is one file
   and it is the least ceremony for a demo. Build it with:

       flutter build apk --release
       # build/app/outputs/flutter-apk/app-release.apk

2. **Put it on Google Drive** (or Dropbox, or a GitHub release) and paste the
   direct download link into `INSTALL_URL` at the top of the script in
   `public/c.html`. The Install button then appears on the page.

3. **Firebase App Distribution**, which is free on Spark and built for exactly
   this. More setup: testers are invited by email and install through it.

With `INSTALL_URL` left empty the page tells the visitor to ask whoever invited
them, rather than showing a button that goes nowhere.

For a stage demo the simplest thing is to install the app on both phones ahead
of time; this page is only for people who do not already have it.

## What works with nothing deployed

Everything except the *tap*. Sharing, the WhatsApp message, and the match
itself are all local. Without the file below, tapping the link opens this web
page in a browser instead of jumping straight into the app.

## Making the tap open the app

Android checks `https://<host>/.well-known/assetlinks.json` for the signing
fingerprint of the installed app. Two things are needed:

1. **The fingerprint of the build you install on the demo phones.**

   Already filled in: `assetlinks.json` carries the debug fingerprint from
   this machine's `~/.android/debug.keystore`, which is what `flutter run`
   and `flutter build apk --debug` sign with. It is a public value by design.
   Only redo this if you sign the demo build with a release key, or build it
   on a different machine:

       # debug build (the default for `flutter run` / `build apk --debug`)
       keytool -list -v -keystore ~/.android/debug.keystore \
         -alias androiddebugkey -storepass android -keypass android

   Copy the `SHA256:` line and paste it into
   `public/.well-known/assetlinks.json` in place of the placeholder. Both the
   debug and release fingerprints can be listed at once.

2. **Deploy.**

       cd hosting
       firebase deploy --only hosting --project mindrush-d92c3

Then reinstall the app once (Android verifies the link on install).

## Testing without any of the above

The custom scheme needs no hosting at all:

    adb shell am start -a android.intent.action.VIEW \
      -d "mindrush://c/sprint-849213?d=3&by=Naman&av=2&s=150&t=57310"
