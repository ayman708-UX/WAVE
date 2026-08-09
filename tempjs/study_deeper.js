// Study hdaudiobooks pagination and audioaz book detail, audiobooks4soul encrypted audio
const https = require('https');
const http = require('http');

function fetch(url, headers = {}, maxRedirects = 5) {
  return new Promise((resolve, reject) => {
    if (maxRedirects <= 0) return reject(new Error('Too many redirects'));
    const mod = url.startsWith('https') ? https : http;
    mod.get(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36', ...headers }, timeout: 15000 }, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        const loc = res.headers.location.startsWith('http') ? res.headers.location : new URL(res.headers.location, url).toString();
        return fetch(loc, headers, maxRedirects - 1).then(resolve).catch(reject);
      }
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    }).on('error', reject).on('timeout', () => reject(new Error('timeout')));
  });
}

async function main() {
  // === HDAUDIOBOOKS page 2 ===
  console.log('=== HDAUDIOBOOKS page 2 ===');
  try {
    const page2 = await fetch('https://hdaudiobooks.com/battlefield-earth/2/');
    console.log('Page 2 status:', page2.status, 'size:', page2.body.length);
    const audios = page2.body.match(/<audio[^>]*>/gi) || [];
    const sources = page2.body.match(/<source[^>]*src="([^"]+)"/gi) || [];
    const mp3s = [...new Set(page2.body.match(/https?:\/\/[^\s"'<>]+\.mp3/gi) || [])];
    console.log('audio:', audios.length, 'source:', sources.length, 'mp3:', mp3s.length);
    sources.slice(0, 3).forEach(s => console.log('  ', s.substring(0, 200)));
    mp3s.slice(0, 3).forEach(s => console.log('  MP3:', s));
    
    // Check for page links to see pagination pattern
    const pageLinks = page2.body.match(/href="[^"]*battlefield-earth\/(\d+)\/"/gi) || [];
    console.log('Page links:', [...new Set(pageLinks)]);
  } catch(e) { console.log('Error:', e.message); }

  // === AUDIOAZ book detail ===
  console.log('\n=== AUDIOAZ SEARCH RESULTS ===');
  try {
    const search = await fetch('https://audioaz.com/en/search?q=harry+potter');
    // Find book links
    const bookLinks = search.body.match(/href="(\/en\/audiobook\/[^"]+)"/gi) || [];
    console.log('Book links found:', bookLinks.length);
    bookLinks.slice(0, 5).forEach(l => console.log('  ', l));
    
    // Find book cards / items
    const cards = search.body.match(/class="[^"]*audiobook[^"]*"/gi) || [];
    console.log('Audiobook classes:', cards.length);
    
    // Extract first book detail URL
    const firstBook = search.body.match(/href="(\/en\/audiobook\/[^"]+)"/i);
    if (firstBook) {
      const bookUrl = 'https://audioaz.com' + firstBook[1];
      console.log('\nFetching book:', bookUrl);
      const detail = await fetch(bookUrl);
      console.log('Detail status:', detail.status, 'size:', detail.body.length);
      
      // Find audio/mp3
      const audios = detail.body.match(/<audio[^>]*>/gi) || [];
      const mp3s = [...new Set(detail.body.match(/https?:\/\/[^\s"'<>]+\.mp3/gi) || [])];
      console.log('audio tags:', audios.length, 'mp3 links:', mp3s.length);
      mp3s.slice(0, 5).forEach(s => console.log('  MP3:', s));
      
      // Find chapter links or listen page
      const chapterLinks = detail.body.match(/href="([^"]*chapter[^"]*)"/gi) || [];
      console.log('Chapter links:', chapterLinks.length);
      
      // Find listen/play links
      const listenLinks = detail.body.match(/href="([^"]*(?:listen|play)[^"]*)"/gi) || [];
      console.log('Listen/play links:', listenLinks.length);
      listenLinks.slice(0, 5).forEach(l => console.log('  ', l));
      
      // Look for JSON-LD or structured data
      const jsonLd = detail.body.match(/<script[^>]*type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi) || [];
      console.log('JSON-LD blocks:', jsonLd.length);
      
      // Look for player divs
      const playerDivs = detail.body.match(/class="[^"]*player[^"]*"/gi) || [];
      console.log('Player divs:', playerDivs.length);
      playerDivs.slice(0, 5).forEach(p => console.log('  ', p));
    }
  } catch(e) { console.log('Error:', e.message); }

  // === AUDIOBOOKS4SOUL decrypt ===
  console.log('\n=== AUDIOBOOKS4SOUL DECRYPT ===');
  try {
    const detail = await fetch('https://audiobooks4soul.com/the-ultimate-harry-potter-and-philosophy-audiobook/');
    
    // Find the audio player setup - look for JS that configures the playlist
    const simpSources = detail.body.match(/class="simp-source"[^>]*/gi) || [];
    console.log('simp-source elements:', simpSources.length);
    simpSources.slice(0, 3).forEach(s => console.log('  ', s.substring(0, 200)));
    
    // Find all data-src values
    const dataSrcs = detail.body.match(/data-src="([^"]+)"/gi) || [];
    console.log('data-src values:', dataSrcs.length);
    dataSrcs.slice(0, 5).forEach(s => console.log('  ', s.substring(0, 200)));
    
    // Find custom-story-audio plugin references
    const pluginRefs = detail.body.match(/custom-story-audio/gi) || [];
    console.log('custom-story-audio plugin refs:', pluginRefs.length);
    
    // Find the simp-player setup script
    const simpSetup = detail.body.match(/simpPlayer|simp_player|simpAudioPlayer/gi) || [];
    console.log('simpPlayer refs:', simpSetup.length);
    
    // Get the full simp-playlist HTML
    const playlistHtml = detail.body.match(/<div[^>]*class="[^"]*simp-playlist[^"]*"[\s\S]*?<\/div>/gi) || [];
    console.log('simp-playlist HTML blocks:', playlistHtml.length);
    if (playlistHtml.length > 0) {
      console.log('First playlist HTML (500 chars):', playlistHtml[0].substring(0, 500));
    }
    
    // Find any encrypt/data patterns
    const encryptedBlobs = detail.body.match(/data-(?:src|url|file|track)="([A-Za-z0-9+/=]{20,})"/gi) || [];
    console.log('Encrypted data blobs:', encryptedBlobs.length);
    encryptedBlobs.slice(0, 3).forEach(s => console.log('  ', s.substring(0, 200)));
  } catch(e) { console.log('Error:', e.message); }
}

main().catch(console.error);
