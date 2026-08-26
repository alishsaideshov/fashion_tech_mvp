import http from 'node:http';
import { pathToFileURL } from 'node:url';

const port = Number(process.env.PORT || process.env.AI_PROXY_PORT || 8787);
const isRailway =
  Boolean(process.env.RAILWAY_SERVICE_ID) ||
  Boolean(process.env.RAILWAY_PROJECT_ID) ||
  Boolean(process.env.RAILWAY_ENVIRONMENT_NAME);
const host = isRailway ? '0.0.0.0' : process.env.AI_PROXY_HOST || '0.0.0.0';
const preferredImageModel =
  process.env.GEMINI_IMAGE_MODEL || 'gemini-3.1-flash-image-preview';
const defaultMaxLooks = Number(process.env.MAX_LOOKS || 5);
const requestedStyleLimit = 5;
const maxWardrobeImages = 5;
const maxRequestBytes = Number(process.env.MAX_REQUEST_BYTES || 45 * 1024 * 1024);
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

const styleOutfitRules = {
  casual:
    'Combine the uploaded pieces into a relaxed everyday outfit with natural layering and comfortable proportions.',
  'smart casual':
    'Use the cleanest and most structured uploaded pieces. Create polish through tucking, layering, proportions, and restrained accessories without inventing replacement garments.',
  'old money':
    'Use only uploaded pieces to suggest quiet luxury through classic proportions, subtle layering, and understated styling. Do not invent cream trousers, knitwear, loafers, or other signature items when they were not uploaded.',
  monochrome:
    'Choose uploaded pieces from the closest tonal family for a cohesive outfit. Never recolor an item merely to force a perfect monochrome palette.',
  'minimal fashion':
    'Choose the cleanest, least visually busy uploaded pieces and style them with simple proportions and minimal accessories. Do not invent replacement basics.',
};

const variationDirections = {
  1: 'Build the most practical, immediately wearable combination from the uploaded wardrobe.',
  2: 'Use a different subset or layering arrangement to create a clearly different silhouette from variation 1.',
  3: 'Create the most expressive combination while remaining faithful to the uploaded wardrobe items.',
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

export const server = http.createServer(async (request, response) => {
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
      defaultMaxLooks,
      maxRequestBytes,
      requestedStyleLimit,
      maxVariationsPerStyle: 3,
      maxWardrobeImages,
      inputPolicy: 'all-wardrobe-v1',
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
    const personImage = body.personImage || null;
    const garments = Array.isArray(body.images) ? body.images : [];
    const styles = normalizeStyles(body.styles);
    const variation = normalizeVariation(body.variation);

    console.log(
      `[lookbook] request person=${Boolean(personImage)} garments=${garments.length} styles=${styles.join(', ')} variation=${variation}`,
    );

    if (!personImage) {
      sendJson(response, 400, { error: 'A person reference image is required.' });
      return;
    }

    if (garments.length === 0) {
      sendJson(response, 400, { error: 'At least one wardrobe image is required.' });
      return;
    }

    if (garments.length > maxWardrobeImages) {
      sendJson(response, 400, {
        error: `Select at most ${maxWardrobeImages} wardrobe photos. No photos were processed.`,
      });
      return;
    }

    // Stream each look as it finishes.
    response.writeHead(200, {
      ...corsHeaders,
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
    });
    const heartbeat = setInterval(() => {
      response.write(': ping\n\n');
    }, 15000);

    let completed = 0;
    const failures = [];

    try {
      for (const style of styles) {
        response.write(`data: ${JSON.stringify({ type: 'started', style, variation })}\n\n`);
        try {
          const look = await generateLook({ style, variation, personImage, garments });
          completed++;
          console.log(`[lookbook] look done style=${style} latencyMs=${look.latencyMs}`);
          response.write(`data: ${JSON.stringify({ type: 'look', look })}\n\n`);
        } catch (err) {
          const message = err.message || String(err);
          failures.push(`${style}: ${message}`);
          console.error(`[lookbook] look failed style=${style}`, message);
          response.write(`data: ${JSON.stringify({ type: 'error', style, message })}\n\n`);
        }
        if (style !== styles[styles.length - 1]) {
          await new Promise(r => setTimeout(r, 20_000));
        }
      }
    } finally {
      clearInterval(heartbeat);
    }

    const latencyMs = Date.now() - startedAt;
    console.log(`[lookbook] done requested=${styles.length} completed=${completed} failed=${failures.length} latencyMs=${latencyMs}`);
    response.write(
      `data: ${JSON.stringify({
        type: 'done',
        requested: styles.length,
        count: completed,
        failures,
        latencyMs,
      })}\n\n`,
    );
    response.end();

  } catch (error) {
    console.error('[lookbook] failed', error);
    // If headers not sent yet, send JSON error; otherwise end the stream
    if (!response.headersSent) {
      const status = error instanceof PayloadTooLargeError ? 413 : 500;
      sendJson(response, status, { error: error.message || String(error) });
    } else {
      response.write(`data: ${JSON.stringify({ type: 'error', message: error.message })}\n\n`);
      response.end();
    }
  }
});

async function generateLook({ style, variation, personImage, garments }) {
  const lookStartedAt = Date.now();
  // Rotate the anchor across the whole lookbook, not always the first garment.
  const styleIndex = Math.max(0, defaultStyles.indexOf(style));
  const focusGarmentNumber = ((styleIndex * 3 + variation - 1) % garments.length) + 1;
  const prompt = buildLookbookPrompt({
    style,
    variation,
    hasPerson: Boolean(personImage),
    garmentCount: garments.length,
    focusGarmentNumber,
  });
  const parts = [
    { text: prompt },
    { text: 'PERSON: identity reference only, not a wardrobe item.' },
    toInlineImage(personImage),
    ...garments.flatMap((garment, index) => [
      { text: `WARDROBE_${index + 1}: exact garment reference.` },
      toInlineImage(garment),
    ]),
  ];

  const { payload, model } = await generateWithFallback(parts);
  if (payload.error) {
    throw new Error(`${style}: ${payload.error}`);
  }

  const generatedImage = extractGeneratedImage(payload);
  if (!generatedImage) throw new Error(`${style}: no image returned`);

  return {
    style,
    variation,
    garmentCount: garments.length,
    referenceCount: garments.length + 1,
    focusGarmentNumber,
    prompt,
    model,
    latencyMs: Date.now() - lookStartedAt,
    imageDataUrl: `data:${generatedImage.mimeType};base64,${generatedImage.data}`,
  };
}

async function runInBatches(items, batchSize, worker) {
  const results = [];
  for (let index = 0; index < items.length; index += batchSize) {
    const batch = items.slice(index, index + batchSize);
    results.push(...(await Promise.allSettled(batch.map(worker))));
  }
  return results;
}

async function generateWithFallback(parts) {
  const candidates = [
    preferredImageModel,
    'gemini-3.1-flash-image-preview',
    'gemini-3-pro-image-preview',
    'gemini-2.5-flash-image',
    'gemini-2.0-flash-preview-image-generation',
  ].filter((model, index, list) => list.indexOf(model) === index);

  for (const candidate of candidates) {
    // A fallback must receive the same references; never hide dropped photos.
    const result = await generate(candidate, parts);
    if (result.ok && extractGeneratedImage(result.payload)) {
      return { payload: result.payload, model: candidate };
    }

    const message = result.payload.error?.message || '';
    if (result.ok) {
      console.warn(
        `[lookbook] model returned no image model=${candidate} text=${extractText(result.payload)}`,
      );
      continue;
    }
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
      status: 502,
      error:
        'Gemini returned no image output for every configured image model.',
    },
    model: preferredImageModel,
  };
}

async function generate(model, parts, retries = 4) {
  const cleanModel = model.replace(/^models\//, '');
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${cleanModel}:generateContent?key=${apiKey}`;

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 55_000); // 55s hard limit

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      signal: controller.signal,
      body: JSON.stringify({
        contents: [{ parts }],
        generationConfig: { responseModalities: ['TEXT', 'IMAGE'] },
      }),
    });
    clearTimeout(timeoutId);

    if ((response.status === 429 || response.status >= 500) && retries > 0) {
      const retryAfterHeader = response.headers.get('retry-after');
      const retryAfterSeconds = retryAfterHeader === null
        ? Number.NaN
        : Number(retryAfterHeader);
      const retryNumber = 5 - retries;
      const delay = Number.isFinite(retryAfterSeconds)
        ? retryAfterSeconds * 1000
        : Math.min(30_000, 2000 * (2 ** retryNumber)) + Math.random() * 1000;
      await new Promise(r => setTimeout(r, delay));
      return generate(model, parts, retries - 1);
    }

    return { ok: response.ok, status: response.status, payload: await response.json() };
  } catch (err) {
    clearTimeout(timeoutId);
    if (err.name === 'AbortError') {
      return { ok: false, status: 408, payload: { error: { message: 'Gemini request timed out after 55s' } } };
    }
    throw err;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  server.listen(port, host, () => {
    console.log(`AI proxy (Gemini lookbook generation) listening on http://${host}:${port}`);
    console.log(`From this Mac:  http://127.0.0.1:${port}/api/analyze-outfit`);
    console.log('From a phone:  use http://<your-mac-lan-ip>:8787/api/analyze-outfit');
  });
}

function normalizeStyles(rawStyles) {
  if (!Array.isArray(rawStyles)) {
    const limit = Math.max(1, Math.min(defaultMaxLooks, requestedStyleLimit));
    return defaultStyles.slice(0, limit);
  }

  const seen = new Set();
  const cleanStyles = rawStyles
    .map((style) => String(style || '').trim().toLowerCase())
    .filter(Boolean)
    .filter((style) => {
      if (seen.has(style)) return false;
      seen.add(style);
      return true;
    })
    .slice(0, requestedStyleLimit);

  return cleanStyles.length > 0
    ? cleanStyles
    : defaultStyles.slice(0, requestedStyleLimit);
}

function normalizeVariation(rawVariation) {
  const variation = Number(rawVariation);
  if (!Number.isInteger(variation)) return 1;
  return Math.max(1, Math.min(variation, 3));
}

function toInlineImage(image) {
  return {
    inline_data: {
      mime_type: image.mimeType || 'image/jpeg',
      data: image.base64Data,
    },
  };
}

function buildLookbookPrompt({ style, variation, hasPerson, garmentCount, focusGarmentNumber }) {
  const direction = styleDirections[style] || `${style} fashion styling`;
  const outfitRule =
    styleOutfitRules[style] ||
    `Create a clearly distinct ${style} outfit with a different silhouette, palette, and styling from the other styles.`;
  const variationDirection =
    variationDirections[variation] || variationDirections[1];
  const personInstruction = hasPerson
    ? 'The FIRST IMAGE is the uploaded user/person reference. The generated person MUST be the same person, not a new model: preserve the exact facial identity, face shape, eyes, nose, mouth, jaw, hair style/color, skin tone, age, body proportions, and overall posture. Use the first image for identity only. Do not copy the clothing from the first image unless it is compatible with the selected style.'
    : 'Create a realistic young adult model appropriate for the wardrobe references.';
  const garmentInstruction =
    garmentCount > 0
      ? `Inspect ALL ${garmentCount} separately labeled wardrobe photos (WARDROBE_1 through WARDROBE_${garmentCount}) before styling. These are exact references, not just inspiration. This look MUST feature the garment from WARDROBE_${focusGarmentNumber}; combine it with ALL compatible items from the other wardrobe photos. Do not default to WARDROBE_1 or the clothes in the person photo. If photos show alternatives for the same clothing slot, do not stack incompatible items: use the required anchor and compatible complementary pieces. Preserve each item's color, pattern, material, cut, and visible details. Do not recolor, replace, or redesign uploaded garments. Add only unobtrusive neutral basics when essential to complete a wearable full-body outfit.`
      : 'No wardrobe references were supplied; do not continue with image generation.';

  return `
CRITICAL IDENTITY REQUIREMENT: The output must show the exact same person from the uploaded reference image. Do not invent a different face, different age, different hairstyle, or generic fashion model.

CRITICAL STYLING REQUIREMENT: Keep identity, but change the outfit for the selected style. For non-casual styles, do not simply copy the outfit worn in the uploaded person reference.

Generate one vertical full-body fashion lookbook photo for the style: ${style}.
This is variation ${variation} of 3. ${variationDirection}

Style direction: ${direction}.
Style-specific outfit requirement: ${outfitRule}.
${personInstruction}
${garmentInstruction}

Output requirements:
- one single full-body person standing in a minimal warm studio with soft side daylight
- editorial AI stylist / lookbook quality
- realistic anatomy, realistic face, realistic clothing fit
- preserve the uploaded person's face identity as the highest priority
- do not replace the uploaded person with another person
- change the outfit strongly for this style
- make variation ${variation} visibly distinct from the other two variations of "${style}"
- the outfit, palette, shoes, and silhouette must visibly match "${style}"
- prioritize faithful use of the uploaded wardrobe over inventing new fashion pieces
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

function extractText(payload) {
  const parts = payload.candidates?.[0]?.content?.parts || [];
  return parts
    .map((part) => part.text)
    .filter(Boolean)
    .join(' ')
    .slice(0, 500);
}

function readJson(request) {
  return new Promise((resolve, reject) => {
    let raw = '';
    let totalBytes = 0;
    let settled = false;

    const settleReject = (error) => {
      if (settled) return;
      settled = true;
      reject(error);
    };

    request.on('data', (chunk) => {
      if (settled) return;
      totalBytes += chunk.length;
      if (totalBytes > maxRequestBytes) {
        request.resume();
        settleReject(
          new PayloadTooLargeError(
            `Request body is too large (${totalBytes} bytes). Reduce uploaded image size/count or raise MAX_REQUEST_BYTES.`,
          ),
        );
        return;
      }
      raw += chunk;
    });
    request.on('end', () => {
      if (settled) return;
      try {
        settled = true;
        resolve(JSON.parse(raw || '{}'));
      } catch (error) {
        settleReject(error);
      }
    });
    request.on('error', settleReject);
  });
}

class PayloadTooLargeError extends Error {}

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
