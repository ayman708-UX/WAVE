const https = require('https');
const http = require('http');

function fetch(url, options = {}, maxRedirects = 5) {
  return new Promise((resolve, reject) => {
    if (maxRedirects <= 0) return reject(new Error('Too many redirects'));
    const mod = url.startsWith('https') ? https : http;
    const req = mod.request(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36', 'Referer': 'https://audiobooks4soul.com/' }, ...options }, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return fetch(res.headers.location.startsWith('http') ? res.headers.location : new URL(res.headers.location, url).toString(), options, maxRedirects - 1).then(resolve).catch(reject);
      }
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    req.end();
  });
}

async function testHDAudiobooks() {
  console.log('\n--- hdaudiobooks.com ---');
  const home = await fetch('https://hdaudiobooks.com/');
  const bookMatch = home.body.match(/<h2>\s*<a[^>]*href="([^"]+)"/i);
  if (!bookMatch) throw new Error('Could not find a book on the homepage');
  
  console.log('Testing book:', bookMatch[1]);
  let detail = await fetch(bookMatch[1]);
  
  let streams = [...new Set(detail.body.match(/https?:\/\/[^\s"'<>]+\.mp3/gi) || [])];
  
  if (streams.length === 0) {
    const sources = detail.body.match(/<source[^>]*src="([^"]+)"/gi) || [];
    streams = sources.map(s => s.match(/src="([^"]+)"/)[1]);
  }
  
  if (streams.length === 0) {
    console.log('No streams on page 1, checking page 2...');
    let page2Url = bookMatch[1];
    if (!page2Url.endsWith('/')) page2Url += '/';
    page2Url += '2/';
    const detail2 = await fetch(page2Url);
    
    streams = [...new Set(detail2.body.match(/https?:\/\/[^\s"'<>]+\.mp3/gi) || [])];
    if (streams.length === 0) {
        const sources = detail2.body.match(/<source[^>]*src="([^"]+)"/gi) || [];
        streams = sources.map(s => s.match(/src="([^"]+)"/)[1]);
    }
  }

  // Also check iframes
  if (streams.length === 0) {
     const iframes = detail.body.match(/<iframe[^>]*src="([^"]+)"/gi) || [];
     console.log('Found iframes:', iframes.length);
     if (iframes.length > 0) {
         console.log('First iframe src:', iframes[0].match(/src="([^"]+)"/)[1]);
         // HDAudiobooks sometimes uses wp-json oembeds, or soundcloud embeds.
     }
  }

  console.log(`Found ${streams.length} streams. First: ${streams[0] || 'None'}`);
  return streams.length > 0;
}

async function testAudiobooks4Soul() {
  console.log('\n--- audiobooks4soul.com ---');
  const search = await fetch('https://audiobooks4soul.com/?s=harry+potter');
  
  const bookMatch = search.body.match(/class="[^"]*(?:entry-title|post-title)[^"]*"[^>]*>\s*<a[^>]*href="([^"]+)"/i);
  if (!bookMatch) throw new Error('Could not find search result');
  
  console.log('Found book:', bookMatch[1]);
  const detail = await fetch(bookMatch[1]);
  
  const playlistMatch = detail.body.match(/<div[^>]*class="[^"]*simp-playlist[^"]*"[\s\S]*?<\/div>/i);
  if (!playlistMatch) throw new Error('No simp-playlist found');
  
  const encryptedBlobs = playlistMatch[0].match(/data-src=(?:'|")([^'"]+)(?:'|")/gi) || [];
  console.log(`Found ${encryptedBlobs.length} encrypted tracks.`);
  
  let validStream = null;
  for (const blob of encryptedBlobs.slice(0, 3)) { // Test first 3
    const encrypted = blob.match(/data-src=(?:'|")([^'"]+)(?:'|")/)[1];
    
    const decryptUrl = `https://audiobooks4soul.com/wp-content/plugins/custom-story-audio/inc/security/decrypt.php?encrypted=${encodeURIComponent(encrypted)}`;
    console.log('Decrypting URL:', decryptUrl);
    const decryptRes = await fetch(decryptUrl);
    
    console.log(`Decrypt Status: ${decryptRes.status}, Body: ${decryptRes.body.substring(0, 150)}`);
    
    if (decryptRes.status === 200 && decryptRes.body.startsWith('http')) {
      if (!decryptRes.body.includes('Soulful_Exploration')) {
          validStream = decryptRes.body.trim();
          break;
      }
    }
  }
  
  if (validStream) {
    console.log(`Successfully decrypted stream: ${validStream}`);
    return true;
  } else {
    console.log('Failed to decrypt a valid stream.');
    return false;
  }
}

async function run() {
  await testHDAudiobooks();
  await testAudiobooks4Soul();
}

run();
