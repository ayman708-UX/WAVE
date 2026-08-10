export default {
  async fetch(request, env, ctx) {
    // Handle CORS preflight OPTIONS request
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: getCorsHeaders(),
      });
    }

    const requestUrl = new URL(request.url);
    
    // Extract target URL from query parameter: /proxy?url=... or /?url=...
    let targetUrlParam = requestUrl.searchParams.get('url');

    if (!targetUrlParam) {
      // Fallback: Check path if URL passed directly e.g. /https://example.com
      const pathUrl = requestUrl.pathname.slice(1) + requestUrl.search;
      if (pathUrl.startsWith('http://') || pathUrl.startsWith('https://')) {
        targetUrlParam = pathUrl;
      }
    }

    if (!targetUrlParam) {
      return new Response(
        JSON.stringify({
          error: 'Missing "url" query parameter.',
          usage: `${requestUrl.origin}/proxy?url=https://api.example.com/data`,
        }),
        {
          status: 400,
          headers: {
            'Content-Type': 'application/json',
            ...getCorsHeaders(),
          },
        }
      );
    }

    try {
      // Ensure target URL is valid
      const targetUrl = new URL(targetUrlParam);

      // Copy incoming headers excluding Cloudflare & host headers
      const forwardingHeaders = new Headers();
      const forbiddenHeaders = [
        'host',
        'cf-ray',
        'cf-connecting-ip',
        'cf-ipcountry',
        'cf-visitor',
        'x-forwarded-proto',
        'x-forwarded-for',
        'x-real-ip',
        'connection',
      ];

      for (const [key, value] of request.headers.entries()) {
        if (!forbiddenHeaders.includes(key.toLowerCase())) {
          forwardingHeaders.set(key, value);
        }
      }

      // Default User-Agent if client didn't specify one
      if (!forwardingHeaders.has('User-Agent')) {
        forwardingHeaders.set(
          'User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
        );
      }

      // Prepare fetch options
      const fetchOptions = {
        method: request.method,
        headers: forwardingHeaders,
        redirect: 'follow',
      };

      // Pass request body for non-GET/HEAD methods
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        fetchOptions.body = request.body;
      }

      // Perform fetch request using Cloudflare's server IP
      const originResponse = await fetch(targetUrl.toString(), fetchOptions);

      // Build response headers with injected CORS headers
      const responseHeaders = new Headers(originResponse.headers);
      const corsHeaders = getCorsHeaders();

      for (const [key, value] of Object.entries(corsHeaders)) {
        responseHeaders.set(key, value);
      }

      responseHeaders.set(
        'Access-Control-Expose-Headers',
        '*'
      );

      return new Response(originResponse.body, {
        status: originResponse.status,
        statusText: originResponse.statusText,
        headers: responseHeaders,
      });
    } catch (err) {
      return new Response(
        JSON.stringify({
          error: 'Proxy Fetch Failed',
          details: err.message,
        }),
        {
          status: 502,
          headers: {
            'Content-Type': 'application/json',
            ...getCorsHeaders(),
          },
        }
      );
    }
  },
};

function getCorsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS, HEAD',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Max-Age': '86400',
  };
}
