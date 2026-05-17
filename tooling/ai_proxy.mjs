import http from 'node:http';

const port = Number(process.env.AI_PROXY_PORT || 8787);
const host = process.env.AI_PROXY_HOST || '0.0.0.0';
const preferredImageModel =
  process.env.GEMINI_IMAGE_MODEL || 'gemini-3.1-flash-image-preview';
const apiKey = process.env.GEMINI_API_KEY;

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
    const images = Array.isArray(body.images) ? body.images.slice(0, 5) : [];

    if (images.length === 0) {
      sendJson(response, 400, { error: 'No images provided.' });
      return;
    }

    const prompt = buildImagePrompt(images);
    const parts = [
      { text: prompt },
      ...images.map((image) => ({
        inline_data: {
          mime_type: image.mimeType || 'image/jpeg',
          data: image.base64Data,
        },
      })),
    ];

    const { payload, model } = await generateWithFallback(parts);
    if (payload.error) {
      sendJson(response, payload.status || 500, {
        error: payload.error,
      });
      return;
    }

    const generatedImage = extractGeneratedImage(payload);
    if (!generatedImage) {
      sendJson(response, 502, {
        error: 'Gemini returned no image output.',
      });
      return;
    }

    sendJson(response, 200, {
      summary: `Generated outfit image from ${images.length} selected garment photos.`,
      prompt,
      qualityScore: 'generated',
      limitations: [],
      generatedImageDataUrl: `data:${generatedImage.mimeType};base64,${generatedImage.data}`,
      model,
      latencyMs: Date.now() - startedAt,
    });
  } catch (error) {
    sendJson(response, 500, { error: error.message || String(error) });
  }
});

async function generateWithFallback(parts) {
  const candidates = [
    preferredImageModel,
    'gemini-2.5-flash-image',
    'gemini-3-pro-image-preview',
  ];

  for (const candidate of candidates) {
    const result = await generate(candidate, parts);
    if (result.ok) return { payload: result.payload, model: candidate };

    const message = result.payload.error?.message || '';
    const isUnavailableModel =
      result.status === 404 ||
      message.includes('not found') ||
      message.includes('not supported') ||
      message.includes('no longer available');
    if (!isUnavailableModel) {
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
  console.log(`AI proxy (Gemini image generation) listening on http://${host}:${port}`);
  console.log(`From this Mac:  http://127.0.0.1:${port}/api/analyze-outfit`);
  console.log('From a phone:  use http://<your-mac-lan-ip>:8787/api/analyze-outfit');
});

function buildImagePrompt(images) {
  const imageList = images
    .map((image, index) => `${index + 1}. ${image.name || 'garment image'}`)
    .join('\n');

  return `
Create one realistic vertical full-body fashion photo using the attached clothing references:
${imageList}

Show a young adult male model wearing all selected garments together as one complete outfit.
Preserve the real garment colors, textures, silhouette, and recognizable details from the references as closely as possible.
Use a minimal warm studio interior, soft daylight from a side window, full-body standing pose, simple neutral background, realistic proportions, editorial ecommerce quality.
Do not add extra garments, logos, bags, hats, jewelry, or accessories that were not supplied.
The final result must look like a real outfit photo, not a flat lay, collage, or ghost mannequin.
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
      if (raw.length > 25 * 1024 * 1024) {
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
