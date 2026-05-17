# Outfit Generator POC

Fast Flutter proof of concept:

- choose 1-5 clothing photos
- send them to a local Gemini proxy
- generate one realistic full-body outfit photo

Run the local Gemini image proxy:

```sh
GEMINI_API_KEY=your_key_here node tooling/ai_proxy.mjs
```

The default image model is `gemini-3.1-flash-image-preview`, with fallbacks to `gemini-2.5-flash-image` and `gemini-3-pro-image-preview`.

Run Flutter web:

```sh
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 5080
```

Run mobile:

```sh
# iOS simulator on the same Mac
flutter run -d ios --dart-define=AI_PROXY_URL=http://127.0.0.1:8787/api/analyze-outfit

# Android emulator
flutter run -d android --dart-define=AI_PROXY_URL=http://10.0.2.2:8787/api/analyze-outfit

# Physical phone on the same Wi-Fi as the Mac
flutter run -d <device-id> --dart-define=AI_PROXY_URL=http://YOUR_MAC_IP:8787/api/analyze-outfit
```

For a physical phone, there is also a helper:

```sh
chmod +x tooling/run_phone.sh
tooling/run_phone.sh <device-id>
```

It reads the current Mac LAN IP and passes the correct `AI_PROXY_URL` automatically.

After adding or changing native plugins such as image picking, stop the app fully and run:

```sh
flutter pub get
flutter run
```

Hot restart is not enough to register native plugins.
