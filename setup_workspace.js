const fs = require('fs');
const path = require('path');

const cacheId = '5c7f5024a162612aa23f2261029cac9a';
const workspaceRoot = `C:\\Users\\liwan\\.hvigor\\project_caches\\${cacheId}\\workspace`;
const ohosDir = `${workspaceRoot}\\node_modules\\@ohos`;
const parentDir = 'C:\\xm';
const hvigorDir = `${parentDir}\\hvigor`;
const hvigorPluginDir = `${parentDir}\\hvigor-ohos-plugin`;

// 1. Delete existing workspace
if (fs.existsSync(workspaceRoot)) {
  fs.rmSync(workspaceRoot, { recursive: true, force: true });
  console.log('Deleted existing workspace');
}

// 2. Create directories
fs.mkdirSync(ohosDir, { recursive: true });
console.log('Created @ohos directory');

// 3. Create workspace package.json (empty deps, to match hvigor-config.json5)
const pkg = { dependencies: {} };
fs.writeFileSync(`${workspaceRoot}\\package.json`, JSON.stringify(pkg, null, 2));
console.log('Created workspace package.json');

// 4. Create junctions using PowerShell (more reliable than fs.symlinkSync)
const { execSync } = require('child_process');
execSync(`cmd.exe /c mklink /J "${ohosDir}\\hvigor" "${hvigorDir}"`, { stdio: 'pipe' });
console.log('Created junction: @ohos/hvigor ->', hvigorDir);

execSync(`cmd.exe /c mklink /J "${ohosDir}\\hvigor-ohos-plugin" "${hvigorPluginDir}"`, { stdio: 'pipe' });
console.log('Created junction: @ohos/hvigor-ohos-plugin ->', hvigorPluginDir);

// 5. Verify
const testPath = `${ohosDir}\\hvigor\\bin\\hvigor.js`;
if (fs.existsSync(testPath)) {
  console.log('VERIFIED: hvigor.js is accessible via junction!');
} else {
  console.error('FAILED: hvigor.js NOT accessible via junction!');
  process.exit(1);
}

console.log('\\nWorkspace setup complete!');
