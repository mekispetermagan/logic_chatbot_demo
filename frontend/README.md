# Logic Chatbot Demo Frontend

A Flutter interface skeleton for web, Linux desktop, and Android. At widths of
900 logical pixels or more, the world and chat panels appear side by side.
Smaller screens use World and Chat tabs. The world uses a `Stack` with a vector
checkerboard and seven sample objects; the chat input has no message handling yet.

Run these commands from `frontend/`:

```sh
flutter pub get
flutter run -d chrome
flutter run -d linux
flutter run -d <android-device-id>
flutter analyze
dart format lib
flutter build web
flutter build linux
flutter build apk
```

Use `flutter devices` to find the Android device ID. Linux builds require the
native desktop toolchain and GTK development libraries; Android builds require
the Android SDK and a compatible JDK.

The app uses Material 3 with a dark, teal-seeded color scheme. No backend or
chatbot logic is connected.
