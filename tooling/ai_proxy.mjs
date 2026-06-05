import http from 'node:http';

const port = Number(process.env.PORT || process.env.AI_PROXY_PORT || 8787);
const host = process.env.AI_PROXY_HOST || '0.0.0.0';
const preferredImageModel =
  process.env.GEMINI_IMAGE_MODEL || 'gemini-2.5-flash-image';
const defaultMaxLooks = Number(process.env.MAX_LOOKS || 5);
const requestedStyleLimit = 5;
const apiKey = process.env.GEMINI_API_KEY;

const defaultStyles = [
  'casual',
  'old money',
  'minimal fashion',
  'smart casual',
  'monochrome',
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
    'Use a relaxed casual outfit. It may reference the brown knit, denim, and sneakers, but restyle the fit and pose so it feels like a fresh casual look.',
  'smart casual':
    'Create smart casual styling: tailored overshirt or clean knit, pressed trousers or dark denim, refined shoes. Avoid a streetwear-only sneaker look.',
  'old money':
    'Create a visibly old money look: cream or ivory pleated trousers, navy/charcoal polo or fine cardigan, loafers or minimal leather shoes, quiet luxury. Do not reuse the brown sweater + blue ripped jeans outfit.',
  monochrome:
    'Create a monochrome look: one cohesive black/white/grey palette, strong silhouette, no blue denim, no brown sweater. Keep it editorial but wearable.',
  'minimal fashion':
    'Create a minimal fashion look: clean white/black/stone palette, plain tee or overshirt, relaxed tailored trousers, minimal sneakers or loafers. Do not reuse the casual sweater/jeans combination.',
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
      defaultMaxLooks,
      requestedStyleLimit,
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

    // SSE headers — stream each look as it finishes
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
        response.write(`data: ${JSON.stringify({ type: 'started', style })}\n\n`);
        try {
          const look = await generateLook({ style, personImage, garments });
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
      sendJson(response, 500, { error: error.message || String(error) });
    } else {
      response.write(`data: ${JSON.stringify({ type: 'error', message: error.message })}\n\n`);
      response.end();
    }
  }
});

async function generateLook({ style, personImage, garments }) {
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
  if (payload.error) {
    throw new Error(`${style}: ${payload.error}`);
  }

  const generatedImage = extractGeneratedImage(payload);
  if (!generatedImage) throw new Error(`${style}: no image returned`);

  return {
    style,
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

  const hasPersonReference = parts.length > 1;

  for (const candidate of candidates) {
    const result = await generate(
      candidate,
      limitPartsForModel(parts, candidate, hasPersonReference),
    );
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

async function generate(model, parts, retries = 2) {
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
      const delay = 2000 + Math.random() * 1000;
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

server.listen(port, host, () => {
  console.log(`AI proxy (Gemini lookbook generation) listening on http://${host}:${port}`);
  console.log(`From this Mac:  http://127.0.0.1:${port}/api/analyze-outfit`);
  console.log('From a phone:  use http://<your-mac-lan-ip>:8787/api/analyze-outfit');
});

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
  const outfitRule =
    styleOutfitRules[style] ||
    `Create a clearly distinct ${style} outfit with a different silhouette, palette, and styling from the other styles.`;
  const personInstruction = hasPerson
    ? 'Use the FIRST IMAGE as a face/body identity reference ONLY. Extract ONLY: face shape, facial features, hair style and color, skin tone, body proportions. COMPLETELY IGNORE AND DO NOT REPRODUCE the clothing, outfit, or styling shown in the first image. Dress the person from scratch using only the style direction and outfit rule below.'
    : 'Create a realistic young adult model appropriate for the wardrobe references.';
  const garmentInstruction =
    garmentCount > 0
      ? 'Use the remaining images as wardrobe inspiration only. You may reinterpret, combine, recolor, or add missing basics to satisfy the selected style. The final outfit must match the selected style more than it matches the source garments.'
      : 'Create the outfit from scratch based on the style direction.';

  return `
CRITICAL: The person reference image shows a brown sweater and blue jeans. DO NOT reproduce this outfit for any style except "casual". For all other styles, create a completely different outfit from scratch.

Generate one vertical full-body fashion lookbook photo for the style: ${style}.

Style direction: ${direction}.
Style-specific outfit requirement: ${outfitRule}.
${personInstruction}
${garmentInstruction}

Output requirements:
- one single full-body person standing in a minimal warm studio with soft side daylight
- editorial AI stylist / lookbook quality
- realistic anatomy, realistic face, realistic clothing fit
- preserve the person's face identity, but change the outfit strongly for this style
- create a fresh inspirational outfit variation unique to "${style}"
- the outfit, palette, shoes, and silhouette must visibly differ from the casual brown sweater + blue jeans reference unless this style is casual
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
