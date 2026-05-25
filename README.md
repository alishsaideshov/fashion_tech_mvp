# AI Stylist Lookbook POC

Lightweight concept demo:

- upload a person / face reference photo
- upload 1-5 wardrobe item photos
- choose up to 3 style presets in fast demo mode
- generate a stylized lookbook with multiple outfit variations

Default styles:

- casual
- smart casual
- old money
- monochrome
- minimal fashion

Run the local Gemini image proxy:

```sh
GEMINI_API_KEY=your_key_here node tooling/ai_proxy.mjs
```

The proxy generates one image per selected style.
The default image model is `gemini-2.5-flash-image`, with fallbacks to `gemini-3-pro-image-preview` and the older `gemini-2.0-flash-preview-image-generation`.
For stability, explicitly selected app styles are always processed up to 3 styles, even if `MAX_LOOKS=1` is still set in Railway.
Generation runs style-by-style so Gemini rate limits do not kill the remaining styles after the first image.
You can override it if your key has access to another image model:

```sh
GEMINI_API_KEY=your_key_here GEMINI_IMAGE_MODEL=gemini-3-pro-image-preview node tooling/ai_proxy.mjs
```

Optional default volume knob when no styles are sent:

```sh
MAX_LOOKS=3 GEMINI_API_KEY=your_key_here node tooling/ai_proxy.mjs
```

Railway deployment:

- deploy this repo as a Node service
- start command: `npm start`
- set env var: `GEMINI_API_KEY=your_key_here`
- Railway provides `PORT` automatically, the proxy reads it
- health check URL: `https://YOUR_RAILWAY_DOMAIN/health`
- generation URL: `https://YOUR_RAILWAY_DOMAIN/api/analyze-outfit`

Build APK for other people with the Railway URL baked in:

```sh
flutter build apk --debug --dart-define=AI_PROXY_URL=https://YOUR_RAILWAY_DOMAIN/api/analyze-outfit
```

The app already includes demo person/clothes assets, so testers can press Generate lookbook without uploading anything.
If Railway/Gemini fails, the APK shows bundled fallback lookbook images and prints the real error in the UI.
Disable that behavior only when debugging strict AI output:

```sh
flutter build apk --debug --dart-define=DEMO_FALLBACK_ON_ERROR=false
```

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

For a physical phone:

```sh
tooling/run_phone.sh <device-id>
```

After adding or changing native plugins such as image picking, stop the app fully and run:

```sh
flutter pub get
flutter run
```

Hot restart is not enough to register native plugins.
