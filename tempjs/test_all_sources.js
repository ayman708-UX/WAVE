// Test script to verify full search -> detail -> stream extraction for ALL sources
const https = require('https');
const http = require('http');

function fetch(url, options = {}, maxRedirects = 5) {
  return new Promise((resolve, reject) => {
    if (maxRedirects <= 0) return reject(new Error('Too many redirects'));
    const mod = url.startsWith('https') ? https : http;
    const opts = {
      headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36', ...options.headers },
      method: options.method || 'GET',
      timeout: 15000
    };
    const req = mod.request(url, opts, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        const loc = res.headers.location.startsWith('http') ? res.headers.location : new URL(res.headers.location, url).toString();
        return fetch(loc, options, maxRedirects - 1).then(resolve).catch(reject);
      }
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve({ status: res.statusCode, body: data, headers: res.headers }));
    });
    req.on('error', reject).on('timeout', () => reject(new Error('timeout')));
    if (options.body) req.write(options.body);
    req.end();
  });
}

function extractStandardWpAudio(html) {
  const sources = html.match(/<source[^>]*src="([^"]+)"/gi) || [];
  return sources.map(s => s.match(/src="([^"]+)"/)[1]);
}

async function testGolden() {
  console.log('\n--- 1. goldenaudiobooks.com ---');
  const search = await fetch('https://goldenaudiobooks.com/?s=harry+potter');
  const bookMatch = search.body.match(/<h2[^>]*class="[^"]*title-post[^"]*"[^>]*>\s*<a[^>]*href="([^"]+)"/i);
  if (!bookMatch) throw new Error('No search results');
  console.log('Found book:', bookMatch[1]);
  const detail = await fetch(bookMatch[1]);
  const streams = extractStandardWpAudio(detail.body);
  console.log(`Success! Found ${streams.length} stream URLs (e.g. ${streams[0]})`);
  return streams.length > 0;
}

async function testFullLength() {
  console.log('\n--- 2. fulllengthaudiobooks.com ---');
  const search = await fetch('https://fulllengthaudiobooks.com/?s=harry+potter');
  const bookMatch = search.body.match(/<h2[^>]*class="[^"]*entry-title[^"]*"[^>]*>\s*<a[^>]*href="([^"]+)"/i);
  if (!bookMatch) throw new Error('No search results');
  console.log('Found book:', bookMatch[1]);
  const detail = await fetch(bookMatch[1]);
  const streams = extractStandardWpAudio(detail.body);
  console.log(`Success! Found ${streams.length} stream URLs (e.g. ${streams[0]})`);
  return streams.length > 0;
}

async function testHdAudiobooks() {
  console.log('\n--- 3. hdaudiobooks.com ---');
  const search = await fetch('https://hdaudiobooks.com/?s=harry+potter');
  const bookMatch = search.body.match(/<h2><a[^>]*href="([^"]+)"/i);
  if (!bookMatch) throw new Error('No search results');
  console.log('Found book:', bookMatch[1]);
  const detail = await fetch(bookMatch[1]);
  const streams = extractStandardWpAudio(detail.body);
  if (streams.length > 0) {
    console.log(`Success! Found ${streams.length} stream URLs (e.g. ${streams[0]})`);
    return true;
  }
  // Try page 2 if no streams on page 1
  const page2Url = bookMatch[1].endsWith('/') ? bookMatch[1] + '2/' : bookMatch[1] + '/2/';
  const detail2 = await fetch(page2Url);
  const streams2 = extractStandardWpAudio(detail2.body);
  console.log(`Success! (Page 2) Found ${streams2.length} stream URLs`);
  return streams2.length > 0;
}

async function testHotAudiobooks() {
  console.log('\n--- 4. hotaudiobooks.com ---');
  const search = await fetch('https://hotaudiobooks.com/?s=harry+potter');
  const bookMatch = search.body.match(/<h2[^>]*>\s*<a[^>]*href="([^"]+)"/i);
  if (!bookMatch) throw new Error('No search results');
  console.log('Found book:', bookMatch[1]);
  const detail = await fetch(bookMatch[1]);
  const streams = extractStandardWpAudio(detail.body);
  console.log(`Success! Found ${streams.length} stream URLs (e.g. ${streams[0]})`);
  return streams.length > 0;
}

async function testBookAudiobooks() {
  console.log('\n--- 5. bookaudiobooks.com ---');
  const search = await fetch('https://bookaudiobooks.com/?s=harry+potter');
  const bookMatch = search.body.match(/<h2[^>]*class="[^"]*entry-title[^"]*"[^>]*>\s*<a[^>]*href="([^"]+)"/i);
  if (!bookMatch) throw new Error('No search results');
  console.log('Found book:', bookMatch[1]);
  const detail = await fetch(bookMatch[1]);
  const streams = extractStandardWpAudio(detail.body);
  console.log(`Success! Found ${streams.length} stream URLs (e.g. ${streams[0]})`);
  return streams.length > 0;
}

async function testAudiozaic() {
  console.log('\n--- 6. audiozaic.com ---');
  const search = await fetch('https://audiozaic.com/?s=harry+potter');
  const bookMatch = search.body.match(/<article[^>]*class="[^"]*vce-post[^"]*"[\s\S]*?<h2[^>]*class="[^"]*entry-title[^"]*"[^>]*>\s*<a[^>]*href="([^"]+)"/i);
  if (!bookMatch) throw new Error('No search results');
  console.log('Found book:', bookMatch[1]);
  const detail = await fetch(bookMatch[1]);
  const listenBtn = detail.body.match(/window\.open\('([^']+)'/);
  if (!listenBtn) throw new Error('No listen button found');
  let listenUrl = listenBtn[1];
  if (listenUrl.startsWith('/')) listenUrl = 'https://audiozaic.com' + listenUrl;
  console.log('Listen URL:', listenUrl);
  const audioPage = await fetch(listenUrl);
  const streams = extractStandardWpAudio(audioPage.body);
  console.log(`Success! Found ${streams.length} stream URLs (e.g. ${streams[0]})`);
  return streams.length > 0;
}

async function testAudioAZ() {
  console.log('\n--- 7. audioaz.com ---');
  const search = await fetch('https://audioaz.com/en/search?q=harry+potter');
  const bookMatch = search.body.match(/href="(\/en\/audiobook\/[^"]+)"/i) || search.body.match(/href="(\/en\/archive\/[^"]+)"/i);
  if (!bookMatch) throw new Error('No search results');
  const bookUrl = 'https://audioaz.com' + bookMatch[1];
  console.log('Found book:', bookUrl);
  const detail = await fetch(bookUrl);
  const sources = detail.body.match(/<source[^>]*src="([^"]+)"/gi) || [];
  const streams = sources.map(s => s.match(/src="([^"]+)"/)[1]);
  console.log(`Success! Found ${streams.length} stream URLs (e.g. ${streams[0]})`);
  return streams.length > 0;
}

async function testAudiobooks4Soul() {
  console.log('\n--- 8. audiobooks4soul.com ---');
  const search = await fetch('https://audiobooks4soul.com/?s=harry+potter');
  const bookMatch = search.body.match(/<h2[^>]*class="[^"]*entry-title[^"]*"[^>]*>\s*<a[^>]*href="([^"]+)"/i);
  if (!bookMatch) throw new Error('No search results');
  console.log('Found book:', bookMatch[1]);
  const detail = await fetch(bookMatch[1]);
  const encryptedBlobs = detail.body.match(/<span class='simp-source' data-src='([^']+)'><i[^>]*><\/i> ([^<]+)<\/span>/gi) || [];
  if (encryptedBlobs.length === 0) throw new Error('No encrypted tracks found');
  
  let validStream = null;
  for (const blobHtml of encryptedBlobs) {
    const match = blobHtml.match(/data-src='([^']+)'><i[^>]*><\/i>\s*([^<]+)<\/span>/);
    if (!match) continue;
    const [_, encrypted, title] = match;
    if (title.toLowerCase().includes('soulful_exploration')) continue; // Skip promo
    
    // Decrypt
    const decryptRes = await fetch(`https://audiobooks4soul.com/wp-content/plugins/custom-story-audio/inc/security/decrypt.php?encrypted=${encodeURIComponent(encrypted)}`);
    if (decryptRes.status === 200 && decryptRes.body.startsWith('http')) {
      validStream = decryptRes.body.trim();
      break;
    }
  }
  
  if (validStream) {
    console.log(`Success! Found encrypted stream URL -> decrypted to: ${validStream}`);
    return true;
  }
  return false;
}

async function testAudionestApp() {
  console.log('\n--- 9. audionestapp.com ---');
  const meiliKey = 'MWJiNWM0MjA2N2ZkM2RiMDNhNWFmNGNk';
  const fbKey = 'AIzaSyAG-z_yl0_55NEYTEKGoVJyixtHG-FhnfA';
  
  // Search
  const searchReq = JSON.stringify({ q: 'harry potter', limit: 1 });
  const search = await fetch('https://search.audionestapp.com/indexes/trackfiles/search', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${meiliKey}`, 'Content-Type': 'application/json', 'Content-Length': searchReq.length },
    body: searchReq
  });
  const searchData = JSON.parse(search.body);
  if (!searchData.hits || searchData.hits.length === 0) throw new Error('No search results');
  const bookId = searchData.hits[0].id;
  console.log(`Found book ID: ${bookId} (${searchData.hits[0].title})`);
  
  // Auth
  const authReq = JSON.stringify({ returnSecureToken: true });
  const auth = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${fbKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Content-Length': authReq.length },
    body: authReq
  });
  const authData = JSON.parse(auth.body);
  const token = authData.idToken;
  
  // Firestore
  const fsReq = JSON.stringify({
    structuredQuery: {
      from: [{ collectionId: 'TrackFiles' }],
      where: { fieldFilter: { field: { fieldPath: 'book_id' }, op: 'EQUAL', value: { integerValue: String(bookId) } } },
      limit: 1
    }
  });
  const fs = await fetch('https://firestore.googleapis.com/v1/projects/learningfirebase-ae02f/databases/(default)/documents:runQuery', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(fsReq) },
    body: fsReq
  });
  const fsData = JSON.parse(fs.body);
  const doc = fsData.find(d => d.document)?.document;
  if (!doc) throw new Error('No firestore document');
  const urls = doc.fields.urlLink.arrayValue.values.map(v => v.stringValue);
  console.log(`Success! Found ${urls.length} stream URLs from Firestore (e.g. ${urls[0].substring(0, 80)}...)`);
  return urls.length > 0;
}

async function testAudiobookBay() {
  console.log('\n--- 10. audiobookbay.lu ---');
  const search = await fetch('https://audiobookbay.lu/?s=harry+potter');
  const bookMatch = search.body.match(/<div class="postTitle">\s*<h2>\s*<a href="([^"]+)"/i);
  if (!bookMatch) throw new Error('No search results');
  let bookUrl = bookMatch[1];
  if (bookUrl.startsWith('/')) bookUrl = 'https://audiobookbay.lu' + bookUrl;
  console.log('Found book:', bookUrl);
  
  const detail = await fetch(bookUrl);
  const hashMatch = detail.body.match(/Info Hash:<\/td>\s*<td[^>]*>\s*([a-fA-F0-9]{40})\s*<\/td>/i);
  if (!hashMatch) throw new Error('No Info Hash found');
  const trackers = [...detail.body.matchAll(/(?:Announce URL|Tracker):<\/td>\s*<td[^>]*>\s*([^<]+?)\s*<\/td>/gi)].map(m => m[1].trim());
  
  const magnet = `magnet:?xt=urn:btih:${hashMatch[1]}&tr=${trackers.map(encodeURIComponent).join('&tr=')}`;
  console.log(`Success! Generated Magnet URI: magnet:?xt=urn:btih:${hashMatch[1]}... with ${trackers.length} trackers`);
  return magnet.startsWith('magnet:?');
}

async function run() {
  const results = {};
  const tests = [
    { name: 'goldenaudiobooks', fn: testGolden },
    { name: 'fulllengthaudiobooks', fn: testFullLength },
    { name: 'hdaudiobooks', fn: testHdAudiobooks },
    { name: 'hotaudiobooks', fn: testHotAudiobooks },
    { name: 'bookaudiobooks', fn: testBookAudiobooks },
    { name: 'audiozaic', fn: testAudiozaic },
    { name: 'audioaz', fn: testAudioAZ },
    { name: 'audiobooks4soul', fn: testAudiobooks4Soul },
    { name: 'audionestapp', fn: testAudionestApp },
    { name: 'audiobookbay', fn: testAudiobookBay }
  ];
  
  let successCount = 0;
  for (const t of tests) {
    try {
      const res = await t.fn();
      results[t.name] = res ? 'SUCCESS' : 'FAILED (no streams)';
      if (res) successCount++;
    } catch(e) {
      results[t.name] = 'ERROR: ' + e.message;
    }
  }
  
  console.log('\n\n============================');
  console.log('      FINAL RESULTS         ');
  console.log('============================');
  for (const [name, status] of Object.entries(results)) {
    console.log(`${name.padEnd(25)}: ${status}`);
  }
  console.log(`\nSuccessfully scraped ${successCount} out of ${tests.length} sources.`);
}

run();
