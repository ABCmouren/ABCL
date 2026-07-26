const fs = require('fs');
const path = require('path');
const cacheOhos = 'C:\\Users\\liwan\\.hvigor\\project_caches\\5c7f5024a162612aa23f2261029cac9a\\workspace\\node_modules\\@ohos';
const target = 'C:\\xm\\HMCL-HarmonyOS\\hvigor';
const dest = cacheOhos + '\\hvigor';

// Create directories
fs.mkdirSync(cacheOhos, { recursive: true });
console.log('Created:', cacheOhos);

try {
  fs.symlinkSync(target, dest, 'junction');
  console.log('Junction created successfully');
  console.log('Readlink:', fs.readlinkSync(dest));
} catch(e) {
  console.log('symlinkSync error:', e.code, e.message);
  
  // Fallback: try without type
  try {
    fs.symlinkSync(target, dest);
    console.log('Symlink (no type) created');
    console.log('Readlink:', fs.readlinkSync(dest));
  } catch(e2) {
    console.log('Second attempt error:', e2.code, e2.message);
  }
}
