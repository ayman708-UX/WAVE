// Study goldenaudiobooks.com - homepage browse + book detail page + search
const https = require('https');
const http = require('http');

function fetch(url) {
  return new Promise((resolve, reject) => {
    const mod = url.startsWith('https') ? https : http;
    mod.get(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' } }, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve(data));
    }).on('error', reject);
  });
}

async function main() {
  // 1. Study homepage structure
  console.log('=== HOMEPAGE ===');
  const home = await fetch('https://goldenaudiobooks.com/');
  
  // Find post listings
  const postPattern = /<li class="[^"]*ilovewp-post[^"]*"[\s\S]*?<\/li>/gi;
  const posts = home.match(postPattern) || [];
  console.log(`Found ${posts.length} posts on homepage`);
  
  if (posts.length > 0) {
    console.log('\nFirst post HTML sample:');
    console.log(posts[0].substring(0, 500));
  }

  // Find title+link pattern
  const titlePattern = /<h2[^>]*class="[^"]*title-post[^"]*"[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>([^<]+)<\/a>/gi;
  let match;
  const books = [];
  while ((match = titlePattern.exec(home)) !== null) {
    books.push({ url: match[1], title: match[2].trim() });
  }
  console.log(`\nFound ${books.length} book links on homepage`);
  books.slice(0, 5).forEach(b => console.log(`  - ${b.title} -> ${b.url}`));

  // Find cover images
  const imgPattern = /<div[^>]*class="[^"]*post-cover[^"]*"[^>]*>[\s\S]*?<img[^>]*(?:data-src|src)="([^"]+)"/gi;
  const covers = [];
  while ((match = imgPattern.exec(home)) !== null) {
    covers.push(match[1]);
  }
  console.log(`\nFound ${covers.length} cover images`);
  covers.slice(0, 3).forEach(c => console.log(`  - ${c}`));

  // 2. Study a book detail page
  if (books.length > 0) {
    console.log('\n=== BOOK DETAIL PAGE ===');
    console.log(`Fetching: ${books[0].url}`);
    const detail = await fetch(books[0].url);
    
    // Find audio elements
    const audioPattern = /<audio[^>]*class="[^"]*wp-audio-shortcode[^"]*"[\s\S]*?<\/audio>/gi;
    const audios = detail.match(audioPattern) || [];
    console.log(`Found ${audios.length} audio players`);
    
    // Extract source URLs
    const srcPattern = /<source[^>]*src="([^"]+)"/gi;
    const streams = [];
    while ((match = srcPattern.exec(detail)) !== null) {
      streams.push(match[1]);
    }
    console.log(`Found ${streams.length} stream URLs`);
    streams.slice(0, 5).forEach(s => console.log(`  - ${s}`));
  }

  // 3. Study search
  console.log('\n=== SEARCH ===');
  const search = await fetch('https://goldenaudiobooks.com/?s=harry+potter');
  const searchTitles = [];
  const searchPattern = /<h2[^>]*class="[^"]*title-post[^"]*"[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>([^<]+)<\/a>/gi;
  while ((match = searchPattern.exec(search)) !== null) {
    searchTitles.push({ url: match[1], title: match[2].trim() });
  }
  console.log(`Search results: ${searchTitles.length}`);
  searchTitles.slice(0, 5).forEach(b => console.log(`  - ${b.title}`));
}

main().catch(console.error);
