import assert from 'node:assert/strict';
import { once } from 'node:events';
import http from 'node:http';
import { after, before, test } from 'node:test';

// Exercise the same older preferred model currently configured on Railway.
process.env.GEMINI_API_KEY = 'test-key-not-used-on-network';
process.env.GEMINI_IMAGE_MODEL = 'gemini-2.5-flash-image';
const { server } = await import('./ai_proxy.mjs');
let baseUrl;

before(async () => {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});
after(async () => {
  await new Promise((resolve) => server.close(resolve));
});

const image = (name) => ({ name, mimeType: 'image/png', base64Data: Buffer.from(name).toString('base64') });
const person = image('person');
const garments = Array.from({ length: 5 }, (_, index) => image(`garment-${index + 1}`));
const success = () => new Response(JSON.stringify({
  candidates: [{ content: { parts: [{ inlineData: { mimeType: 'image/png', data: 'generated-test-image' } }] } }],
}), { status: 200, headers: { 'content-type': 'application/json' } });

function request(body, path = '/api/analyze-outfit') {
  return new Promise((resolve, reject) => {
    const req = http.request(`${baseUrl}${path}`, {
      method: body === undefined ? 'GET' : 'POST',
      headers: { 'Content-Type': 'application/json' },
    }, (res) => {
      let text = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { text += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, text }));
      res.on('error', reject);
    });
    req.on('error', reject);
    req.end(body === undefined ? undefined : JSON.stringify(body));
  });
}

function looksFrom(response) {
  assert.equal(response.status, 200);
  return response.text.split('\n')
    .filter((line) => line.startsWith('data: '))
    .map((line) => JSON.parse(line.substring(6)))
    .filter((event) => event.type === 'look')
    .map((event) => event.look);
}

test('selfie plus every selected garment reaches Gemini 2.5, separately labeled', async (t) => {
  let sentParts;
  t.mock.method(globalThis, 'fetch', async (_url, init) => {
    sentParts = JSON.parse(init.body).contents[0].parts;
    return success();
  });
  const result = looksFrom(await request({ personImage: person, images: garments, styles: ['casual'], variation: 1 }));
  assert.equal(result.length, 1);
  assert.equal(result[0].referenceCount, 6);
  assert.equal(result[0].garmentCount, 5);
  assert.deepEqual(sentParts.filter((part) => part.inline_data).map((part) => part.inline_data.data),
    [person, ...garments].map((input) => input.base64Data));
  for (let index = 1; index <= garments.length; index++) {
    assert.ok(sentParts.some((part) => part.text === `WARDROBE_${index}: exact garment reference.`));
  }
});

test('fallback forwards the entire original image set instead of slicing it', async (t) => {
  const attempts = [];
  t.mock.method(globalThis, 'fetch', async (url, init) => {
    attempts.push({ url, parts: JSON.parse(init.body).contents[0].parts });
    if (attempts.length < 3) {
      return new Response(JSON.stringify({ error: { message: 'model not supported' } }), { status: 400 });
    }
    return success();
  });
  const result = looksFrom(await request({ personImage: person, images: garments, styles: ['casual'], variation: 2 }));
  assert.equal(result.length, 1);
  assert.equal(attempts.length, 3);
  for (const attempt of attempts) {
    assert.equal(attempt.parts.filter((part) => part.inline_data).length, 6);
    assert.deepEqual(attempt.parts, attempts[0].parts);
  }
});

test('all wardrobe photos become anchors across five styles with three variants', async (t) => {
  t.mock.method(globalThis, 'fetch', async () => success());
  const focused = new Set();
  for (const style of ['casual', 'smart casual', 'old money', 'monochrome', 'minimal fashion']) {
    for (let variation = 1; variation <= 3; variation++) {
      const [look] = looksFrom(await request({ personImage: person, images: garments, styles: [style], variation }));
      assert.equal(look.garmentCount, garments.length);
      assert.match(look.prompt, new RegExp(`MUST feature the garment from WARDROBE_${look.focusGarmentNumber}`));
      focused.add(look.focusGarmentNumber);
    }
  }
  assert.deepEqual([...focused].sort(), [1, 2, 3, 4, 5]);
});

test('one garment works without indexing nonexistent images', async (t) => {
  t.mock.method(globalThis, 'fetch', async () => success());
  const [look] = looksFrom(await request({ personImage: person, images: [garments[0]], styles: ['monochrome'], variation: 3 }));
  assert.equal(look.focusGarmentNumber, 1);
  assert.equal(look.referenceCount, 2);
});

test('over-limit input is rejected before generation, never silently truncated', async (t) => {
  const fetchMock = t.mock.method(globalThis, 'fetch', async () => { throw new Error('Unexpected Gemini request'); });
  const response = await request({ personImage: person, images: [...garments, image('extra')], styles: ['casual'] });
  assert.equal(response.status, 400);
  assert.match(JSON.parse(response.text).error, /No photos were processed/);
  assert.equal(fetchMock.mock.callCount(), 0);
});

test('an explicitly selected wardrobe photo is kept even if also used as person reference', async (t) => {
  let sentParts;
  t.mock.method(globalThis, 'fetch', async (_url, init) => {
    sentParts = JSON.parse(init.body).contents[0].parts;
    return success();
  });
  const [look] = looksFrom(await request({ personImage: person, images: [person, garments[0]], styles: ['casual'] }));
  assert.equal(look.garmentCount, 2);
  assert.deepEqual(sentParts.filter((part) => part.inline_data).map((part) => part.inline_data.data),
    [person, person, garments[0]].map((input) => input.base64Data));
});

test('single-garment mode generates one exact try-on even if styles and variations are supplied', async (t) => {
  const attempts = [];
  t.mock.method(globalThis, 'fetch', async (_url, init) => {
    attempts.push(JSON.parse(init.body).contents[0].parts);
    return success();
  });
  for (const garment of garments.slice(0, 3)) {
    const result = looksFrom(await request({
      mode: 'single_garment',
      personImage: person,
      images: [garment],
      styles: ['casual', 'smart casual', 'old money', 'monochrome', 'minimal fashion'],
      variation: 3,
    }));
    assert.equal(result.length, 1);
    const [look] = result;
    assert.equal(look.style, 'garment try-on');
    assert.equal(look.variation, 1);
    assert.equal(look.garmentName, garment.name);
    assert.equal(look.referenceCount, 2);
    assert.equal(look.garmentCount, 1);
    assert.equal(look.focusGarmentNumber, 1);
    assert.match(look.prompt, /exact garment in WARDROBE_1/);
    assert.match(look.prompt, /Do not redesign, recolor, replace, or restyle/);
    assert.doesNotMatch(look.prompt, /variation \d of 3|Style direction:|WARDROBE_2/);
    assert.deepEqual(attempts.at(-1).filter((part) => part.inline_data).map((part) => part.inline_data.data),
      [person.base64Data, garment.base64Data]);
    assert.equal(attempts.at(-1)[0].text, look.prompt);
  }
  assert.equal(attempts.length, 3);
});

test('single-garment mode with no styles still generates only one image', async (t) => {
  const fetchMock = t.mock.method(globalThis, 'fetch', async () => success());
  const result = looksFrom(await request({ mode: 'single_garment', personImage: person, images: [garments[0]] }));
  assert.equal(result.length, 1);
  assert.equal(fetchMock.mock.callCount(), 1);
});

test('single-garment mode rejects missing or multiple references before calling Gemini', async (t) => {
  const fetchMock = t.mock.method(globalThis, 'fetch', async () => { throw new Error('Unexpected Gemini request'); });
  for (const images of [[], garments.slice(0, 2), garments.slice(0, 3)]) {
    assert.equal((await request({ mode: 'single_garment', personImage: person, images })).status, 400);
  }
  assert.equal((await request({ mode: 'single_garment', images: [garments[0]] })).status, 400);
  assert.equal(fetchMock.mock.callCount(), 0);
});

test('health identifies support for single-garment try-on', async () => {
  const response = await request(undefined, '/health');
  assert.equal(response.status, 200);
  assert.equal(JSON.parse(response.text).inputPolicy, 'all-wardrobe-v1');
  assert.ok(JSON.parse(response.text).generationModes.includes('single_garment'));
});
