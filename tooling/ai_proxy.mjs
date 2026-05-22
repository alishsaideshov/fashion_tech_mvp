import http from 'node:http';

const port = Number(process.env.PORT || process.env.AI_PROXY_PORT || 8787);
const host = process.env.AI_PROXY_HOST || '0.0.0.0';
const preferredImageModel =
  process.env.GEMINI_IMAGE_MODEL || 'gemini-2.5-flash-image';
const apiKey = process.env.GEMINI_API_KEY;

const defaultStyles = [
  'casual',
  'smart casual',
  'old money',
  'monochrome',
  'minimal fashion',
];

const styleDirections = {
  casual:
    'relaxed casual everyday outfit, approachable, comfortable, natural layering, street-ready but polished',
  'smart casual':
    'smart casual outfit, elevated but wearable, clean shirt or knit balance, refined shoes, subtle premium styling',
  'old money':
    'old money aesthetic, quiet luxury, cream/navy/charcoal palette, tailored relaxed trousers, understated elegance',
  monochrome:
    'monochrome fashion look, cohesive single-tone palette, strong silhouette, editorial but realistic',
  'minimal fashion':
    'minimal fashion look, clean shapes, neutral palette, no visual clutter, modern lookbook styling',
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

const server = http.createServer(async (request, response) => {
  if (request.method === 'OPTIONS') {
    send(response, 204, '');
    return;
  }

  if (request.method === 'GET' && ['/', '/health', '/api/health'].includes(request.url)) {
    sendJson(response, 200, {
      ok: true,
      service: 'fashion-tech-ai-proxy',
      route: '/api/analyze-outfit',
      apiKeyConfigured: Boolean(apiKey),
      defaultModel: preferredImageModel,
      styles: defaultStyles,
    });
    return;
  }

  if (request.method !== 'POST' || request.url !== '/api/analyze-outfit') {
    sendJson(response, 404, { error: 'Not found' });
    return;
  }

  if (!apiKey) {
    sendJson(response, 500, {
      error:
        'GEMINI_API_KEY is missing. Start with: GEMINI_API_KEY=... node tooling/ai_proxy.mjs',
    });
    return;
  }

  try {
    const startedAt = Date.now();
    const body = await readJson(request);
    const garments = Array.isArray(body.images) ? body.images.slice(0, 5) : [];
    const personImage = body.personImage || null;
    const styles = normalizeStyles(body.styles);

    console.log(
      `[lookbook] request person=${Boolean(personImage)} garments=${garments.length} styles=${styles.join(', ')}`,
    );

    if (!personImage && garments.length === 0) {
      sendJson(response, 400, { error: 'No person or garment images provided.' });
      return;
    }

    const looks = [];
    let modelUsed = preferredImageModel;

    for (const style of styles) {
      const lookStartedAt = Date.now();
      const prompt = buildLookbookPrompt({
        style,
        hasPerson: Boolean(personImage),
        garmentCount: garments.length,
      });
      const parts = [
        { text: prompt },
        ...(personImage ? [toInlineImage(personImage)] : []),
        ...garments.map(toInlineImage),
      ];

      const { payload, model } = await generateWithFallback(parts);
      modelUsed = model;

      if (payload.error) {
        sendJson(response, payload.status || 500, {
          error: payload.error,
          style,
        });
        return;
      }

      const generatedImage = extractGeneratedImage(payload);
      if (!generatedImage) {
        sendJson(response, 502, {
          error: `Gemini returned no image output for ${style}.`,
        });
        return;
      }

      looks.push({
        style,
        prompt,
        model,
        latencyMs: Date.now() - lookStartedAt,
        imageDataUrl: `data:${generatedImage.mimeType};base64,${generatedImage.data}`,
      });
    }

    const latencyMs = Date.now() - startedAt;
    console.log(`[lookbook] success looks=${looks.length} model=${modelUsed} latencyMs=${latencyMs}`);

    sendJson(response, 200, {
      summary: `Generated ${looks.length} stylist lookbook variations.`,
      prompt: 'AI stylist lookbook: user face/person reference + wardrobe items + style presets.',
      qualityScore: 'lookbook',
      limitations: [],
      generatedImageDataUrl: looks[0]?.imageDataUrl || null,
      model: modelUsed,
      latencyMs,
      looks,
    });
  } catch (error) {
    console.error('[lookbook] failed', error);
    sendJson(response, 500, { error: error.message || String(error) });
  }
});

async function generateWithFallback(parts) {
  const candidates = [
    preferredImageModel,
    'gemini-3-pro-image-preview',
    'gemini-2.5-flash-image',
    'gemini-2.0-flash-preview-image-generation',
  ].filter((model, index, list) => list.indexOf(model) === index);

  const hasPersonReference = parts.length > 1;

  for (const candidate of candidates) {
    const result = await generate(
      candidate,
      limitPartsForModel(parts, candidate, hasPersonReference),
    );
    if (result.ok) return { payload: result.payload, model: candidate };

    const message = result.payload.error?.message || '';
    console.warn(`[lookbook] model failed model=${candidate} status=${result.status} message=${message}`);
    const shouldTryNextModel =
      result.status === 404 ||
      result.status === 400 ||
      message.includes('not found') ||
      message.includes('not supported') ||
      message.includes('no longer available') ||
      message.includes('too many') ||
      message.includes('exceeds');
    if (!shouldTryNextModel) {
      return {
        payload: {
          status: result.status,
          error: message || 'Gemini image generation failed.',
        },
        model: candidate,
      };
    }
  }

  return {
    payload: {
      status: 404,
      error:
        'No available Gemini image-generation model was found for this API key.',
    },
    model: preferredImageModel,
  };
}

function limitPartsForModel(parts, model, hasPersonReference) {
  const cleanModel = model.replace(/^models\//, '');
  const prompt = parts[0];
  const imageParts = parts.slice(1);

  if (cleanModel === 'gemini-2.5-flash-image') {
    const maxInputImages = 3;
    return [prompt, ...imageParts.slice(0, maxInputImages)];
  }

  if (cleanModel === 'gemini-3-pro-image-preview') {
    const maxHighFidelityImages = hasPersonReference ? 5 : 6;
    return [prompt, ...imageParts.slice(0, maxHighFidelityImages)];
  }

  return parts;
}

async function generate(model, parts) {
  const cleanModel = model.replace(/^models\//, '');
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${cleanModel}:generateContent?key=${apiKey}`;
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ parts }],
      generationConfig: {
        responseModalities: ['TEXT', 'IMAGE'],
      },
    }),
  });

  return {
    ok: response.ok,
    status: response.status,
    payload: await response.json(),
  };
}

server.listen(port, host, () => {
  console.log(`AI proxy (Gemini lookbook generation) listening on http://${host}:${port}`);
  console.log(`From this Mac:  http://127.0.0.1:${port}/api/analyze-outfit`);
  console.log('From a phone:  use http://<your-mac-lan-ip>:8787/api/analyze-outfit');
});

function normalizeStyles(rawStyles) {
  if (!Array.isArray(rawStyles)) return defaultStyles;
  const cleanStyles = rawStyles
    .map((style) => String(style || '').trim().toLowerCase())
    .filter(Boolean)
    .slice(0, 5);
  return cleanStyles.length > 0 ? cleanStyles : defaultStyles;
}

function toInlineImage(image) {
  return {
    inline_data: {
      mime_type: image.mimeType || 'image/jpeg',
      data: image.base64Data,
    },
  };
}

function buildLookbookPrompt({ style, hasPerson, garmentCount }) {
  const direction = styleDirections[style] || `${style} fashion styling`;
  const personInstruction = hasPerson
    ? 'Use the first image as the person/face identity reference. Preserve the person identity, face shape, hair, glasses, skin tone, and overall vibe as much as possible while making a new full-body fashion look.'
    : 'Create a realistic young adult model appropriate for the wardrobe references.';
  const garmentInstruction =
    garmentCount > 0
      ? 'Use the remaining images as wardrobe inspiration. You may reinterpret, combine, recolor subtly, or add missing basics to create a fresh styled outfit. Do not copy the exact same look; create a new stylized variation.'
      : 'Create the outfit from scratch based on the style direction.';

  return `
Generate one vertical full-body fashion lookbook photo for the style: ${style}.

Style direction: ${direction}.
${personInstruction}
${garmentInstruction}

Output requirements:
- one single full-body person standing in a minimal warm studio with soft side daylight
- editorial AI stylist / lookbook quality
- realistic anatomy, realistic face, realistic clothing fit
- preserve the person's face identity more than the exact outfit
- create a fresh inspirational outfit variation, not the same outfit repeated
- no collage, no split screen, no text, no UI, no labels, no extra people
- clean neutral background, premium ecommerce/editorial mood
`.trim();
}

function extractGeneratedImage(payload) {
  const parts = payload.candidates?.[0]?.content?.parts || [];
  for (const part of parts) {
    const inlineData = part.inlineData || part.inline_data;
    if (inlineData?.data) {
      return {
        mimeType: inlineData.mimeType || inlineData.mime_type || 'image/png',
        data: inlineData.data,
      };
    }
  }

  return null;
}

function readJson(request) {
  return new Promise((resolve, reject) => {
    let raw = '';
    request.on('data', (chunk) => {
      raw += chunk;
      if (raw.length > 30 * 1024 * 1024) {
        request.destroy();
        reject(new Error('Request body too large.'));
      }
    });
    request.on('end', () => {
      try {
        resolve(JSON.parse(raw || '{}'));
      } catch (error) {
        reject(error);
      }
    });
    request.on('error', reject);
  });
}

function sendJson(response, status, payload) {
  send(response, status, JSON.stringify(payload), {
    'Content-Type': 'application/json',
  });
}

function send(response, status, body, headers = {}) {
  response.writeHead(status, {
    ...corsHeaders,
    ...headers,
  });
  response.end(body);
}
