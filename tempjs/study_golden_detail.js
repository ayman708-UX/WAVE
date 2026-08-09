// Study goldenaudiobooks.com detail page for audio streams
const https = require('https');

function fetch(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' } }, res => {
      if (res.statusCode >= 300 && res.statusCode < 400) {
        return fetch(res.headers.location).then(resolve).catch(reject);
      }
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve(data));
    }).on('error', reject);
  });
}

async function main() {
  // First search to get a real URL
  const search = await fetch('https://goldenaudiobooks.com/?s=harry+potter');
  const urlMatch = search.match(/<h2[^>]*class="[^"]*title-post[^"]*"[^>]*>\s*<a[^>]*href="([^"]+)"/i);
  if (!urlMatch) { console.log('No results'); return; }
  
  const bookUrl = urlMatch[1];
  console.log('Fetching book:', bookUrl);
  const detail = await fetch(bookUrl);
  
  // Find ALL audio-related elements
  const audioTags = detail.match(/<audio[\s\S]*?<\/audio>/gi) || [];
  console.log(`<audio> tags: ${audioTags.length}`);
  
  // Try source tags
  const srcMatches = detail.match(/<source[^>]*src="([^"]+)"/gi) || [];
  console.log(`<source> tags: ${srcMatches.length}`);
  srcMatches.forEach(s => console.log('  ', s));
  
  // Try direct mp3 links
  const mp3Links = detail.match(/https?:\/\/[^\s"'<>]+\.mp3[^\s"'<>]*/gi) || [];
  console.log(`\nMP3 links: ${mp3Links.length}`);
  [...new Set(mp3Links)].slice(0, 10).forEach(s => console.log('  ', s));
  
  // Try iframe embeds
  const iframes = detail.match(/<iframe[^>]*src="([^"]+)"/gi) || [];
  console.log(`\niframes: ${iframes.length}`);
  iframes.forEach(s => console.log('  ', s));

  // Try collapse-o-matic (expandable sections)
  const collapsibles = detail.match(/class="[^"]*collapseomatic[^"]*"/gi) || [];
  console.log(`\nCollapsible sections: ${collapsibles.length}`);

  // Check for any wp-audio-shortcode
  const wpAudio = detail.match(/wp-audio-shortcode/gi) || [];
  console.log(`wp-audio-shortcode references: ${wpAudio.length}`);

  // Check for any data-src or data-mediaplayer
  const dataSrc = detail.match(/data-src="([^"]+)"/gi) || [];
  console.log(`data-src attributes: ${dataSrc.length}`);
  dataSrc.slice(0, 5).forEach(s => console.log('  ', s));
}

main().catch(console.error);
