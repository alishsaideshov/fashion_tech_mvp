# AI Stylist Lookbook POC

Lightweight concept demo:

- upload a person / face reference photo
- upload 1-3 wardrobe item photos (one garment per photo)
- add photos in multiple selections; remove individual photos without replacing the wardrobe
- automatically generate at most three looks TOTAL per button press
- one garment = one prompt and one generated try-on; two garments = two separate images; three = three
- each request contains the same selfie and ONLY the corresponding garment photo, with no style selection or variations

The app uses `mode: "single_garment"`. This proxy mode requires exactly one wardrobe image and ignores style/variation lists, always producing at most one look. The app makes exactly as many look requests as selected garments (maximum three), including failed requests; failures do not trigger extra replacement looks. Results retain their garment name and selection order, including when names match or one item fails.

Run the local Gemini image proxy:

```sh
GEMINI_API_KEY=your_key_here node tooling/ai_proxy.mjs
```

The app requests each garment separately so completed images remain visible if a later request reaches an API limit. The proxy retries temporary Gemini errors with exponential backoff; such retries do not create additional result slots.
The default image model is `gemini-3.1-flash-image-preview`, with fallbacks to `gemini-3-pro-image-preview`, `gemini-2.5-flash-image`, and the older `gemini-2.0-flash-preview-image-generation`.
The proxy prompt treats uploaded clothes as exact wardrobe references and asks the model to preserve their color, pattern, material, and cut.
Every single-garment model attempt receives exactly two image references: the selfie and that garment. Other selected garments are never mixed into the request. The prompt asks for the exact garment without redesigning it, allows only essential neutral complementary basics, and requests one image rather than alternative styles. This is a prompt instruction, not a guarantee of visual garment fidelity.
The app allows up to three wardrobe photos. Larger selections are rejected explicitly without dropping photos. Exact duplicates are not added twice.
Legacy direct proxy requests without `mode: "single_garment"` still support the older style-based lookbook and up to five wardrobe references; the app no longer uses that path.
You can override it if your key has access to another image model:

```sh
GEMINI_API_KEY=your_key_here GEMINI_IMAGE_MODEL=gemini-3-pro-image-preview node tooling/ai_proxy.mjs
```

Optional default style-count knob for legacy direct proxy requests that omit both single-garment mode and `styles` (does not affect the app):

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

After deploying the single-garment change, `/health` must include `"single_garment"` in `generationModes`. Install the updated APK AND deploy the updated proxy to Railway for the new exact-garment prompt. The APK also sends a singleton style list to prevent older proxies from defaulting to five outputs, but an old proxy still uses the old styling prompt.

Regression tests (mocked Gemini, no paid generation): `npm test` and `flutter test`.

Build APK for other people with the Railway URL baked in:

```sh
flutter build apk --release --dart-define=AI_PROXY_URL=https://YOUR_RAILWAY_DOMAIN/api/analyze-outfit
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
