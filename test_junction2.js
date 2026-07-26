const fs = require('fs');
const p = 'C:\\Users\\liwan\\.hvigor\\project_caches\\5c7f5024a162612aa23f2261029cac9a\\workspace\\node_modules\\@ohos\\hvigor\\bin\\hvigor.js';
console.log('Testing path:', p);
console.log('exists:', fs.existsSync(p));

const junctionPath = 'C:\\Users\\liwan\\.hvigor\\project_caches\\5c7f5024a162612aa23f2261029cac9a\\workspace\\node_modules\\@ohos\\hvigor';
console.log('Junction path:', junctionPath);
try {
  const stat = fs.lstatSync(junctionPath);
  console.log('isSymbolicLink:', stat.isSymbolicLink());
} catch(e) {
  console.log('lstat error:', e.message);
}

try {
  const files = fs.readdirSync(junctionPath);
  console.log('readdir success, files:', files.slice(0, 5));
} catch(e) {
  console.log('readdir error:', e.message);
}
