// Study ALL audiobook sites at once
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
      res.on('end', () => resolve({ status: res.statusCode, body: data, url }));
    }).on('error', reject).on('timeout', () => reject(new Error('timeout')));
  });
}

async function studySite(name, homeUrl, searchUrl) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`=== ${name} ===`);
  console.log(`${'='.repeat(60)}`);
  
  try {
    // Homepage
    const home = await fetch(homeUrl);
    console.log(`Homepage status: ${home.status}, size: ${home.body.length}`);
    
    // Find post/article patterns
    const patterns = [
      { name: 'article.vce-post', re: /class="[^"]*vce-post[^"]*"/gi },
      { name: 'li.ilovewp-post', re: /class="[^"]*ilovewp-post[^"]*"/gi },
      { name: 'div.post', re: /<div[^>]*class="[^"]*\bpost\b[^"]*"/gi },
      { name: 'article', re: /<article[^>]*>/gi },
      { name: 'h2 a links', re: /<h2[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>([^<]+)<\/a>/gi },
      { name: 'entry-title', re: /class="[^"]*entry-title[^"]*"/gi },
      { name: 'post-title', re: /class="[^"]*post-title[^"]*"/gi },
      { name: 'wp-audio', re: /wp-audio-shortcode/gi },
      { name: 'audio tag', re: /<audio[^>]*>/gi },
      { name: 'source tag', re: /<source[^>]*src="([^"]+)"/gi },
      { name: 'mp3 links', re: /https?:\/\/[^\s"'<>]+\.mp3[^\s"'<>]*/gi },
      { name: 'iframe', re: /<iframe[^>]*src="([^"]+)"/gi },
    ];
    
    for (const p of patterns) {
      const matches = home.body.match(p.re) || [];
      if (matches.length > 0) {
        console.log(`  ${p.name}: ${matches.length} found`);
        if (matches.length <= 3) matches.forEach(m => console.log(`    ${m.substring(0, 150)}`));
      }
    }
    
    // Search
    if (searchUrl) {
      console.log(`\n  --- Search ---`);
      const sr = await fetch(searchUrl);
      console.log(`  Search status: ${sr.status}, size: ${sr.body.length}`);
      for (const p of patterns) {
        const matches = sr.body.match(p.re) || [];
        if (matches.length > 0) {
          console.log(`  ${p.name}: ${matches.length}`);
          if (p.name === 'h2 a links' && matches.length <= 5) {
            matches.forEach(m => console.log(`    ${m.substring(0, 150)}`));
          }
        }
      }
      // Extract first book URL from search
      const bookUrlMatch = sr.body.match(/<h2[^>]*>\s*<a[^>]*href="([^"]+)"/i) 
        || sr.body.match(/class="[^"]*entry-title[^"]*"[^>]*>\s*<a[^>]*href="([^"]+)"/i)
        || sr.body.match(/<a[^>]*href="(https?:\/\/[^"]*(?:audiobook|book)[^"]*)"[^>]*>/i);
      
      if (bookUrlMatch) {
        console.log(`\n  --- Detail Page: ${bookUrlMatch[1].substring(0, 100)} ---`);
        try {
          const detail = await fetch(bookUrlMatch[1]);
          console.log(`  Detail status: ${detail.status}, size: ${detail.body.length}`);
          const audioCount = (detail.body.match(/<audio[^>]*>/gi) || []).length;
          const sourceCount = (detail.body.match(/<source[^>]*src="([^"]+)"/gi) || []).length;
          const mp3Count = (detail.body.match(/https?:\/\/[^\s"'<>]+\.mp3/gi) || []).length;
          const iframeCount = (detail.body.match(/<iframe[^>]*>/gi) || []).length;
          console.log(`  audio: ${audioCount}, source: ${sourceCount}, mp3: ${mp3Count}, iframe: ${iframeCount}`);
          
          // Show first few source URLs
          const srcMatches = detail.body.match(/<source[^>]*src="([^"]+)"/gi) || [];
          srcMatches.slice(0, 3).forEach(s => console.log(`    ${s.substring(0, 200)}`));
          
          // Show first few mp3 URLs  
          const mp3s = [...new Set(detail.body.match(/https?:\/\/[^\s"'<>]+\.mp3[^\s"'<>]*/gi) || [])];
          mp3s.slice(0, 3).forEach(s => console.log(`    MP3: ${s.substring(0, 200)}`));
          
          // Show iframes
          const iframes = detail.body.match(/<iframe[^>]*src="([^"]+)"/gi) || [];
          iframes.slice(0, 3).forEach(s => console.log(`    IFRAME: ${s.substring(0, 200)}`));
        } catch(e) { console.log(`  Detail error: ${e.message}`); }
      }
    }
  } catch(e) {
    console.log(`  ERROR: ${e.message}`);
  }
}

async function main() {
  const sites = [
    ['fulllengthaudiobooks.com', 'https://fulllengthaudiobooks.com/', 'https://fulllengthaudiobooks.com/?s=harry+potter'],
    ['hdaudiobooks.com', 'https://hdaudiobooks.com/', 'https://hdaudiobooks.com/?s=harry+potter'],
    ['hotaudiobooks.com', 'https://hotaudiobooks.com/', 'https://hotaudiobooks.com/?s=harry+potter'],
    ['bookaudiobooks.com', 'https://bookaudiobooks.com/', 'https://bookaudiobooks.com/?s=harry+potter'],
    ['audiozaic.com', 'https://audiozaic.com/', 'https://audiozaic.com/?s=harry+potter'],
    ['audioaz.com', 'https://audioaz.com/en', 'https://audioaz.com/en/search/harry+potter'],
    ['audiobooks4soul.com', 'https://audiobooks4soul.com/home-1/', 'https://audiobooks4soul.com/?s=harry+potter'],
  ];

  for (const [name, home, search] of sites) {
    await studySite(name, home, search);
  }
}

main().catch(console.error);
