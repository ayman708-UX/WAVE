// audioaz.com deeper study - find the actual audiobook listing structure
const https = require('https');

function fetch(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' }, timeout: 15000 }, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        const loc = res.headers.location.startsWith('http') ? res.headers.location : new URL(res.headers.location, url).toString();
        return fetch(loc).then(resolve).catch(reject);
      }
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    }).on('error', reject);
  });
}

async function main() {
  const search = await fetch('https://audioaz.com/en/search?q=harry+potter');
  
  // Find ALL href links with /en/ in them
  const enLinks = search.body.match(/href="(\/en\/[^"]+)"/gi) || [];
  const unique = [...new Set(enLinks)];
  console.log('All /en/ links:', unique.length);
  unique.filter(l => !l.includes('/search') && !l.includes('.css') && !l.includes('.js')).slice(0, 20).forEach(l => console.log('  ', l));
  
  // Find audiobook cards / book items
  const bookItems = search.body.match(/<a[^>]*href="(\/en\/[^"]*(?:book|listen|audio)[^"]*)"[^>]*>/gi) || [];
  console.log('\nBook-like links:', bookItems.length);
  bookItems.slice(0, 10).forEach(l => console.log('  ', l.substring(0, 200)));
  
  // Find h3/h4 titles
  const h3s = search.body.match(/<h3[^>]*>[\s\S]*?<\/h3>/gi) || [];
  console.log('\nh3 tags:', h3s.length);
  h3s.forEach(h => console.log('  ', h.replace(/<[^>]+>/g, '').trim().substring(0, 100)));
  
  // Find any card/item structure
  const cards = search.body.match(/class="[^"]*(?:card|item|book|result)[^"]*"/gi) || [];
  console.log('\nCard/item/book classes:', [...new Set(cards)].slice(0, 15));
  
  // Find img tags with audiobook covers
  const imgs = search.body.match(/<img[^>]*alt="[^"]*(?:harry|potter)[^"]*"[^>]*/gi) || [];
  console.log('\nHP images:', imgs.length);
  imgs.slice(0, 3).forEach(i => console.log('  ', i.substring(0, 200)));
  
  // Look for data- attributes
  const dataAttrs = search.body.match(/data-(?:book|audio|id|slug)[^=]*="([^"]+)"/gi) || [];
  console.log('\nData attributes:', dataAttrs.length);
  dataAttrs.slice(0, 10).forEach(d => console.log('  ', d));

  // Try a direct book page 
  console.log('\n=== Try /en/audiobook/ paths ===');
  const home = await fetch('https://audioaz.com/en');
  const bookPaths = home.body.match(/href="(\/en\/audiobook\/[^"]+)"/gi) || [];
  console.log('Book paths on homepage:', bookPaths.length);
  bookPaths.slice(0, 5).forEach(l => console.log('  ', l));
  
  if (bookPaths.length > 0) {
    const firstPath = bookPaths[0].match(/href="([^"]+)"/)[1];
    const bookPage = await fetch('https://audioaz.com' + firstPath);
    console.log('\nBook page status:', bookPage.status, 'size:', bookPage.body.length);
    const mp3s = [...new Set(bookPage.body.match(/https?:\/\/[^\s"'<>]+\.mp3/gi) || [])];
    console.log('MP3s:', mp3s.length);
    mp3s.slice(0, 3).forEach(m => console.log('  ', m));
    
    const audioTags = bookPage.body.match(/<audio[^>]*>/gi) || [];
    console.log('Audio tags:', audioTags.length);
    
    // Listen page links
    const listenLinks = bookPage.body.match(/href="([^"]*listen[^"]*)"/gi) || [];
    console.log('Listen links:', listenLinks.length);
    listenLinks.slice(0, 5).forEach(l => console.log('  ', l));
    
    // Chapter links
    const chapters = bookPage.body.match(/href="([^"]*chapter[^"]*)"/gi) || [];
    console.log('Chapter links:', chapters.length);
    chapters.slice(0, 5).forEach(l => console.log('  ', l));
  }
}

main().catch(console.error);
