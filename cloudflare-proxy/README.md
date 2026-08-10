# Cloudflare Worker HTTP Proxy (`wave-proxy`)

A lightweight, high-performance Cloudflare Worker proxy that forwards API requests using Cloudflare's server IP network.

## Features

- **Endpoint Format**: Accepts requests in the format `https://<worker-subdomain>.workers.dev/proxy?url=https://api.example.com/data` or `/?url=...`.
- **Server IP Requesting**: Sends upstream requests using Cloudflare Worker's server IP instead of the client/user's IP.
- **CORS Handling**: Injects open CORS headers (`Access-Control-Allow-Origin: *`) and handles `OPTIONS` preflight requests seamlessly.
- **Header & Body Forwarding**: Forwards request methods (GET, POST, PUT, DELETE), client headers (Authorization, User-Agent, Content-Type, etc.), and request bodies for POST/PUT.

## Usage

```http
GET https://wave-proxy.<your-subdomain>.workers.dev/proxy?url=https://api.octavestreaming.com/api/playback-token
```

```http
POST https://wave-proxy.<your-subdomain>.workers.dev/proxy?url=https://api.example.com/login
Content-Type: application/json

{
  "username": "user",
  "password": "pass"
}
```

## How to Deploy

1. Open a terminal in this folder:
   ```bash
   cd cloudflare-proxy
   ```

2. Login to your Cloudflare account (if not already logged in):
   ```bash
   npx wrangler login
   ```

3. Deploy to Cloudflare Workers:
   ```bash
   npx wrangler deploy
   ```

Once deployed, Wrangler will output your live URL (e.g., `https://wave-proxy.<your-subdomain>.workers.dev`).
