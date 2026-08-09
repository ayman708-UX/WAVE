// Study audiozaic detail page (uses listen button -> file-audio page)
// Study audioaz.com API structure  
// Study audiobooks4soul.com detail page
// Study audionest API
const https = require('https');
const http = require('http');

function fetch(url, maxRedirects = 5) {
  return new Promise((resolve, reject) => {
    if (maxRedirects <= 0) return reject(new Error('Too many redirects'));
    const mod = url.startsWith('https') ? https : http;
    mod.get(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' }, timeout: 15000 }, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        const loc = res.headers.location.startsWith('http') ? res.headers.location : new URL(res.headers.location, url).toString();
        return fetch(loc, maxRedirects - 1).then(resolve).catch(reject);
      }
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    }).on('error', reject).on('timeout', () => reject(new Error('timeout')));
  });
}

function postJson(url, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const data = JSON.stringify(body);
    const opts = {
      hostname: u.hostname, port: u.port || 443, path: u.pathname + u.search,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data), ...headers },
      timeout: 15000
    };
    const req = https.request(opts, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => resolve({ status: res.statusCode, body: d }));
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function main() {
  // === 1. AUDIOZAIC DETAIL ===
  console.log('=== AUDIOZAIC DETAIL ===');
  try {
    const detail = await fetch('https://audiozaic.com/harry-potter-and-the-deathly-hallows-audiobook/');
    // Find listen button
    const listenBtn = detail.body.match(/id="listen-button"[^>]*onclick="([^"]+)"/i) 
      || detail.body.match(/window\.open\('([^']+)'/i);
    console.log('Listen button onclick:', listenBtn ? listenBtn[1]?.substring(0, 200) : 'NOT FOUND');
    
    // Find listen URL from onclick 
    const listenUrlMatch = detail.body.match(/window\.open\('([^']+)'/);
    if (listenUrlMatch) {
      let listenUrl = listenUrlMatch[1];
      if (listenUrl.startsWith('/')) listenUrl = 'https://audiozaic.com' + listenUrl;
      console.log('Listen URL:', listenUrl);
      
      // Fetch the audio page
      const audioPage = await fetch(listenUrl);
      console.log('Audio page status:', audioPage.status, 'size:', audioPage.body.length);
      
      // Find tracks
      const tracks = audioPage.body.match(/class="[^"]*track[^"]*"/gi) || [];
      console.log('Track divs:', tracks.length);
      
      const songtitles = audioPage.body.match(/class="songtitle"[^>]*>([^<]+)/gi) || [];
      console.log('Song titles:', songtitles.length);
      songtitles.slice(0, 3).forEach(s => console.log('  ', s.substring(0, 100)));
      
      const audioSources = audioPage.body.match(/<audio[^>]*>[\s\S]*?<source[^>]*src="([^"]+)"/gi) || [];
      console.log('Audio sources:', audioSources.length);
      audioSources.slice(0, 3).forEach(s => console.log('  ', s.substring(0, 200)));
      
      // Direct mp3/audio URLs
      const mp3s = [...new Set(audioPage.body.match(/https?:\/\/[^\s"'<>]+\.(?:mp3|m4a|ogg|opus)/gi) || [])];
      console.log('Audio file URLs:', mp3s.length);
      mp3s.slice(0, 5).forEach(s => console.log('  ', s));
    }
  } catch(e) { console.log('Error:', e.message); }

  // === 2. AUDIOAZ.COM ===
  console.log('\n=== AUDIOAZ.COM ===');
  try {
    const home = await fetch('https://audioaz.com/en');
    console.log('Home status:', home.status, 'size:', home.body.length);
    
    // Check for API endpoints or AJAX
    const apiMatches = home.body.match(/api[^\s"'<>]*|ajax[^\s"'<>]*/gi) || [];
    console.log('API/AJAX references:', [...new Set(apiMatches)].slice(0, 10));
    
    // Check for search form
    const searchForm = home.body.match(/<form[^>]*action="([^"]*search[^"]*)"/gi) || [];
    console.log('Search forms:', searchForm.length);
    searchForm.forEach(s => console.log('  ', s.substring(0, 200)));
    
    // Try different search URLs
    for (const searchUrl of [
      'https://audioaz.com/en/search?q=harry+potter',
      'https://audioaz.com/en/search/harry+potter',
      'https://audioaz.com/en?s=harry+potter',
    ]) {
      const sr = await fetch(searchUrl);
      if (sr.status === 200 && sr.body.length > 1000) {
        console.log(`Search ${searchUrl} -> status ${sr.status}, size ${sr.body.length}`);
        const titles = sr.body.match(/<h[23][^>]*>[\s\S]*?<\/h[23]>/gi) || [];
        console.log(`  Titles found: ${titles.length}`);
        titles.slice(0, 3).forEach(t => console.log('  ', t.substring(0, 150)));
        break;
      } else {
        console.log(`Search ${searchUrl} -> status ${sr.status}`);
      }
    }
  } catch(e) { console.log('Error:', e.message); }

  // === 3. AUDIOBOOKS4SOUL DETAIL ===
  console.log('\n=== AUDIOBOOKS4SOUL DETAIL ===');
  try {
    const search = await fetch('https://audiobooks4soul.com/?s=harry+potter');
    // Find first book URL
    const bookMatch = search.body.match(/class="[^"]*entry-title[^"]*"[^>]*>\s*<a[^>]*href="([^"]+)"/i);
    if (bookMatch) {
      console.log('First result URL:', bookMatch[1]);
      const detail = await fetch(bookMatch[1]);
      console.log('Detail status:', detail.status, 'size:', detail.body.length);
      
      // Check for audio/source/iframe
      const audios = detail.body.match(/<audio[^>]*>/gi) || [];
      console.log('Audio tags:', audios.length);
      audios.slice(0, 2).forEach(a => console.log('  ', a.substring(0, 200)));
      
      // Check for simp-playlist (encrypted src like ezaudiobookforsoul)
      const simpPlaylist = detail.body.match(/simp-playlist/gi) || [];
      console.log('simp-playlist:', simpPlaylist.length);
      
      const simpSource = detail.body.match(/simp-source[^>]*data-src="([^"]+)"/gi) || [];
      console.log('simp-source data-src:', simpSource.length);
      simpSource.slice(0, 3).forEach(s => console.log('  ', s.substring(0, 200)));

      // Check for decrypt endpoint  
      const decryptMatch = detail.body.match(/decrypt\.php/gi) || [];
      console.log('decrypt.php references:', decryptMatch.length);
      
      // Check for wp-audio
      const wpAudio = detail.body.match(/wp-audio/gi) || [];
      console.log('wp-audio references:', wpAudio.length);
      
      // Check for any embedded player
      const iframes = detail.body.match(/<iframe[^>]*src="([^"]+)"/gi) || [];
      console.log('iframes:', iframes.length);
      iframes.slice(0, 3).forEach(s => console.log('  ', s.substring(0, 200)));
    }
  } catch(e) { console.log('Error:', e.message); }

  // === 4. AUDIONEST API TEST ===
  console.log('\n=== AUDIONEST API ===');
  try {
    const meiliKey = 'MWJiNWM0MjA2N2ZkM2RiMDNhNWFmNGNk';
    const res = await postJson('https://search.audionestapp.com/indexes/trackfiles/search', 
      { q: 'harry potter', limit: 5 },
      { 'Authorization': `Bearer ${meiliKey}` }
    );
    console.log('Meilisearch status:', res.status);
    if (res.status === 200) {
      const data = JSON.parse(res.body);
      console.log('Total hits:', data.hits?.length);
      (data.hits || []).slice(0, 3).forEach(h => {
        console.log(`  - id=${h.id} title="${h.title}" thumb=${(h.thumbnailUrl||'').substring(0,80)}`);
      });
    }
  } catch(e) { console.log('Error:', e.message); }

  // === 5. HDAUDIOBOOKS DETAIL (no audio found earlier, investigate) ===
  console.log('\n=== HDAUDIOBOOKS DETAIL (deeper) ===');
  try {
    const detail = await fetch('https://hdaudiobooks.com/battlefield-earth/');
    // Check for collapsible/hidden sections
    const collapse = detail.body.match(/collaps[eo]matic/gi) || [];
    console.log('Collapse-o-matic:', collapse.length);
    
    // Check for any JS-loaded audio
    const scriptBlocks = detail.body.match(/<script[^>]*>[\s\S]*?<\/script>/gi) || [];
    console.log('Script blocks:', scriptBlocks.length);
    
    // Check for links to external audio pages
    const listenLinks = detail.body.match(/listen|play|audio|stream/gi) || [];
    console.log('"listen/play/audio/stream" references:', listenLinks.length);
    
    // Check for hidden iframes or embeds
    const embeds = detail.body.match(/<embed[^>]*>/gi) || [];
    console.log('Embeds:', embeds.length);
    
    // Any external links
    const externalAudioLinks = detail.body.match(/href="([^"]*(?:ipaudio|mp3|audio)[^"]*)"/gi) || [];
    console.log('External audio links:', externalAudioLinks.length);
    externalAudioLinks.slice(0, 5).forEach(l => console.log('  ', l.substring(0, 200)));

    // Any wp-audio, source, or audio elements hidden in collapsed content
    const collContent = detail.body.match(/class="[^"]*collapseomatic_content[^"]*"[\s\S]*?(?=class="[^"]*collapseomatic_content|$)/gi) || [];
    console.log('Collapsed content blocks:', collContent.length);
    if (collContent.length > 0) {
      const innerAudios = collContent[0].match(/<audio[\s\S]*?<\/audio>/gi) || [];
      const innerSources = collContent[0].match(/<source[^>]*src="([^"]+)"/gi) || [];
      console.log('  Audio in collapsed:', innerAudios.length, 'Sources:', innerSources.length);
      innerSources.slice(0, 3).forEach(s => console.log('    ', s.substring(0, 200)));
    }
  } catch(e) { console.log('Error:', e.message); }
}

main().catch(console.error);
