// audioaz.com book detail - find the actual audio stream URLs
const https = require('https');

function fetch(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' }, timeout: 15000 }, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return fetch(res.headers.location.startsWith('http') ? res.headers.location : new URL(res.headers.location, url).toString()).then(resolve).catch(reject);
      }
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve(data));
    }).on('error', reject);
  });
}

async function main() {
  const page = await fetch('https://audioaz.com/en/audiobook/animal-farm');
  
  // Find audio tag and its source
  const audioSection = page.match(/<audio[\s\S]*?<\/audio>/gi) || [];
  console.log('Audio sections:', audioSection.length);
  audioSection.forEach(a => console.log(a.substring(0, 500)));
  
  // Find any source elements  
  const sources = page.match(/<source[^>]*>/gi) || [];
  console.log('\nSource tags:', sources.length);
  sources.forEach(s => console.log('  ', s));
  
  // Find any data-src, src= on audio-related elements
  const audioSrcs = page.match(/(?:src|data-src|data-url|data-file)="([^"]*(?:mp3|audio|stream|cdn|bucket|spaces|blob|archive\.org)[^"]*)"/gi) || [];
  console.log('\nAudio-like src attrs:', audioSrcs.length);
  audioSrcs.forEach(s => console.log('  ', s.substring(0, 200)));
  
  // Find archive.org references
  const archiveOrg = page.match(/archive\.org[^\s"'<>]*/gi) || [];
  console.log('\nArchive.org references:', archiveOrg.length);
  archiveOrg.slice(0, 5).forEach(s => console.log('  ', s));
  
  // Find __NEXT_DATA__ or similar SSR data
  const nextData = page.match(/<script[^>]*id="__NEXT_DATA__"[^>]*>([\s\S]*?)<\/script>/i);
  if (nextData) {
    console.log('\n__NEXT_DATA__ found! Length:', nextData[1].length);
    try {
      const data = JSON.parse(nextData[1]);
      const props = data?.props?.pageProps;
      if (props) {
        console.log('pageProps keys:', Object.keys(props));
        // Look for audio/chapters data
        const audiobook = props.audiobook || props.book || props.data;
        if (audiobook) {
          console.log('Audiobook keys:', Object.keys(audiobook));
          if (audiobook.chapters) console.log('Chapters count:', audiobook.chapters.length);
          if (audiobook.files) console.log('Files count:', audiobook.files.length);
          // Print first chapter
          const first = audiobook.chapters?.[0] || audiobook.files?.[0];
          if (first) console.log('First chapter/file:', JSON.stringify(first).substring(0, 300));
        }
      }
    } catch(e) { console.log('JSON parse error:', e.message); }
  }
  
  // Find any fetch/XHR/API calls in scripts
  const apiCalls = page.match(/fetch\s*\(\s*['"]([^'"]+)['"]/gi) || [];
  console.log('\nFetch API calls:', apiCalls.length);
  apiCalls.slice(0, 5).forEach(a => console.log('  ', a));
  
  // Look for _next/data pattern
  const nextDataPaths = page.match(/_next\/data\/[^"'\s]+/gi) || [];
  console.log('\n_next/data paths:', nextDataPaths.length);
  nextDataPaths.slice(0, 3).forEach(p => console.log('  ', p));
}

main().catch(console.error);
