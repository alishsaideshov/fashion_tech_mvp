# AI Stylist Lookbook POC

Lightweight concept demo:

- upload a person / face reference photo
- upload 1-5 wardrobe item photos
- add photos in multiple selections; remove individual photos without replacing the wardrobe
- automatically generate five style groups from the uploaded wardrobe
- generate up to three distinct looks per style (15 looks total)

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

The app requests each style variation separately so completed images remain visible if a later request reaches an API limit. The proxy retries temporary Gemini errors with exponential backoff.
The default image model is `gemini-3.1-flash-image-preview`, with fallbacks to `gemini-3-pro-image-preview`, `gemini-2.5-flash-image`, and the older `gemini-2.0-flash-preview-image-generation`.
The proxy prompt treats uploaded clothes as exact wardrobe references and asks the model to preserve their color, pattern, material, and cut.
Every model attempt receives the selfie and ALL selected wardrobe photos, each separately labeled. Fallbacks no longer truncate references. The primary garment rotates across the 15 looks, so all selected photos are assigned a turn as the anchor. Compatible pieces are combined; alternative items such as multiple shirts are not forced into a single outfit. This is a prompt instruction, not a guarantee of visual garment fidelity.
The app and proxy allow up to five wardrobe photos. Larger selections are rejected explicitly without dropping photos. Exact duplicates are not added twice.
You can override it if your key has access to another image model:

```sh
GEMINI_API_KEY=your_key_here GEMINI_IMAGE_MODEL=gemini-3-pro-image-preview node tooling/ai_proxy.mjs
```

Optional default style-count knob for direct proxy requests that omit `styles`:

```sh
MAX_LOOKS=5 GEMINI_API_KEY=your_key_here node tooling/ai_proxy.mjs
```

Railway deployment:

- deploy this repo as a Node service
- start command: `npm start`
- set env var: `GEMINI_API_KEY=your_key_here`
- Railway provides `PORT` automatically, the proxy reads it
- health check URL: `https://YOUR_RAILWAY_DOMAIN/health`
- generation URL: `https://YOUR_RAILWAY_DOMAIN/api/analyze-outfit`

After deploying the multi-photo fix, `/health` must include `"inputPolicy":"all-wardrobe-v1"`. Rebuilding only the APK cannot update an older Railway proxy that still truncates image inputs.

Regression tests (mocked Gemini, no paid generation): `npm test` and `flutter test`.

Build APK for other people with the Railway URL baked in:

```sh
flutter build apk --debug --dart-define=AI_PROXY_URL=https://YOUR_RAILWAY_DOMAIN/api/analyze-outfit
```

The app requires both a person photo and at least one wardrobe item before generation starts.

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
