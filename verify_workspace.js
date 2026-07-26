const fs = require('fs');
const p = 'C:\\Users\\liwan\\.hvigor\\project_caches\\5c7f5024a162612aa23f2261029cac9a\\workspace\\node_modules\\@ohos\\hvigor\\bin\\hvigor.js';
console.log('Exists:', fs.existsSync(p));
try {
  const r = fs.realpathSync(p);
  console.log('Realpath:', r);
} catch(e) {
  console.log('Realpath error:', e.message);
}

// Also check the junction itself
const j = 'C:\\Users\\liwan\\.hvigor\\project_caches\\5c7f5024a162612aa23f2261029cac9a\\workspace\\node_modules\\@ohos\\hvigor';
const s = fs.lstatSync(j);
console.log('isSymbolicLink:', s.isSymbolicLink());
console.log('readlink:', fs.readlinkSync(j));
try {
  console.log('Files:', fs.readdirSync(j).slice(0, 10));
} catch(e) {
  console.log('readdir error:', e.message);
}
