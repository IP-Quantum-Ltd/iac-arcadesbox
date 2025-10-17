// iac/workers/game_gatekeeper.js
import jwt from '@tsndr/cloudflare-worker-jwt';

export default {
  async fetch(request, env, ctx) {
    // --- CORS Setup (remains the same) ---
    const allowedOrigins = JSON.parse(env.ALLOWED_ORIGINS || '[]');
    const origin = request.headers.get('Origin');
    const corsOrigin = allowedOrigins.includes(origin) ? origin : null;

    if (request.method === 'OPTIONS') {
      return handleOptions(request, corsOrigin);
    }

    // --- NEW: Path-Based Security Logic ---
    const url = new URL(request.url);
    const objectKey = url.pathname.slice(1); // remove leading '/'

    // If the request is for a thumbnail, it's a public asset.
    // Skip all authentication and serve the file directly.
    if (objectKey.startsWith('thumbnails/')) {
      return serveFromR2(env.GAMES_BUCKET, objectKey, corsOrigin);
    }

    // For any other path (like /games/), enforce JWT authentication.
    const cookieHeader = request.headers.get('Cookie') || '';
    const cookies = Object.fromEntries(
      cookieHeader.split(';').map((c) => c.trim().split('='))
    );
    const token = cookies['game-auth-token'];

    if (!token) {
      return new Response('Access Denied: Missing authentication token.', {
        status: 401,
        headers: getCorsHeaders(corsOrigin),
      });
    }

    try {
      await jwt.verify(token, env.WORKER_JWT_SECRET);
      // If verification succeeds, serve the protected file from R2.
      return serveFromR2(env.GAMES_BUCKET, objectKey, corsOrigin);
    } catch (err) {
      return new Response(`Access Denied: Invalid or expired token.`, {
        status: 403,
        headers: getCorsHeaders(corsOrigin),
      });
    }
  },
};

// --- HELPER FUNCTIONS ---

// NEW: A reusable function to fetch and serve a file from R2.
async function serveFromR2(bucket, key, corsOrigin) {
  console.log('Serving from R2');
  const object = await bucket.get(key);

  if (object === null) {
    return new Response('Object Not Found', {
      status: 404,
      headers: getCorsHeaders(corsOrigin),
    });
  }

  const headers = getCorsHeaders(corsOrigin);

  const r2Headers = new Headers();
  object.writeHttpMetadata(r2Headers);

  // Manually copy selected headers to avoid `X-Frame-Options`
  for (const [key, value] of r2Headers.entries()) {
    if (key.toLowerCase() !== 'x-frame-options') {
      headers.set(key, value);
    }
  }

  headers.set('etag', object.httpEtag);

  // Optionally set a CSP to allow iframe embedding
  headers.set('Content-Security-Policy', 'frame-ancestors *');

  // Explicitly remove the X-Frame-Options header to allow embedding.
  console.log('Deleting X-Frame-Options');
  headers.delete('X-Frame-Options');

  console.log('Final Headers:', [...headers.entries()]);

  return new Response(object.body, {
    headers,
  });
}

// NEW: A helper to generate consistent CORS headers.
function getCorsHeaders(corsOrigin) {
  const headers = new Headers();
  if (corsOrigin) {
    headers.set('Access-Control-Allow-Origin', corsOrigin);
    headers.set('Access-Control-Allow-Credentials', 'true');
  } else {
    headers.set('Access-Control-Allow-Origin', '*');
  }
  return headers;
}

// Helper function for CORS preflight (remains the same)
function handleOptions(request, corsOrigin) {
  if (corsOrigin) {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': corsOrigin,
        'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Cookie',
        'Access-Control-Allow-Credentials': 'true',
        'Access-Control-Max-Age': '86400',
      },
    });
  }
  return new Response(null, { headers: { Allow: 'GET, HEAD, OPTIONS' } });
}
