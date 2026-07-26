/**
 * Download JDK runtimes for HMCL-HarmonyOS
 *
 * Downloads OHOS ARM64 JDK ZIPs from mc-ohos-resources (by LZZLHY)
 * and places them in entry/src/main/resources/rawfile/ for HAP bundling.
 *
 * JDKs are GPL-2.0 licensed builds.
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

const JDKS = [
  {
    name: 'JDK 8 (MC 1.0-1.16.5)',
    url: 'https://github.com/LZZLHY/mc-ohos-resources/releases/download/v8u452-ohos-3/jdk8-ohos-full.zip',
    file: 'jdk8-ohos-full.zip',
    size: 39570295,
    sha256: '478fa9a5a0dfe80bbfcd8d980b2978d4f878d69a38b17f57703daf9a3bff8f6f',
  },
  {
    name: 'JDK 17 (MC 1.17-1.20.4)',
    url: 'https://github.com/LZZLHY/mc-ohos-resources/releases/download/v17.0.13-ohos-4/jdk17-ohos-full-v4.zip',
    file: 'jdk17-ohos-full-v4.zip',
    size: 114006672,
    sha256: '822bf2c75042d46c0190bf184f364768874fb39610062c469bd43d40ea78966f',
  },
  {
    name: 'JDK 21 (MC 1.20.5-1.21.x)',
    url: 'https://github.com/LZZLHY/mc-ohos-resources/releases/download/v21.0.5-ohos-6/jdk21-ohos-full.zip',
    file: 'jdk21-ohos-full.zip',
    size: 117797892,
    sha256: '99ed88eec9afe38f78491e871d9f4023cd03e3525b6550a6a65273baddfb2932',
  },
];

const RAWFILE_DIR = path.resolve(
  __dirname,
  '..',
  'entry',
  'src',
  'main',
  'resources',
  'rawfile',
);

function downloadFile(url, destPath) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(destPath);
    const req = https.get(url, (res) => {
      const total = parseInt(res.headers['content-length'], 10);
      let downloaded = 0;

      res.pipe(file);

      res.on('data', (chunk) => {
        downloaded += chunk.length;
        if (total) {
          const pct = ((downloaded / total) * 100).toFixed(1);
          process.stdout.write(`\r  ${pct}% (${(downloaded / 1024 / 1024).toFixed(1)}MB / ${(total / 1024 / 1024).toFixed(1)}MB)`);
        }
      });

      file.on('finish', () => {
        file.close();
        process.stdout.write('\n');
        resolve();
      });
    });

    req.on('error', (err) => {
      fs.unlinkSync(destPath);
      reject(err);
    });

    file.on('error', (err) => {
      fs.unlinkSync(destPath);
      reject(err);
    });
  });
}

async function main() {
  console.log('=== HMCL-HarmonyOS JDK Downloader ===\n');
  console.log(`Rawfile directory: ${RAWFILE_DIR}\n`);

  // Create rawfile directory if needed
  if (!fs.existsSync(RAWFILE_DIR)) {
    fs.mkdirSync(RAWFILE_DIR, { recursive: true });
  }

  for (const jdk of JDKS) {
    const destPath = path.join(RAWFILE_DIR, jdk.file);

    if (fs.existsSync(destPath)) {
      const stats = fs.statSync(destPath);
      if (stats.size === jdk.size) {
        console.log(`✅ ${jdk.name} — already exists (${(stats.size / 1024 / 1024).toFixed(1)}MB)`);
        continue;
      }
      console.log(`⚠  ${jdk.name} — re-downloading (size mismatch)`);
    } else {
      console.log(`⬇  Downloading ${jdk.name}...`);
    }

    console.log(`   ${jdk.url}`);
    await downloadFile(jdk.url, destPath);

    const stats = fs.statSync(destPath);
    console.log(`   → ${(stats.size / 1024 / 1024).toFixed(1)}MB downloaded\n`);
  }

  console.log('=== All JDK runtimes downloaded ===');
  console.log(`Total rawfile size: ${(fs.statSync(RAWFILE_DIR).size / 1024 / 1024).toFixed(0)}MB`);
}

main().catch((err) => {
  console.error('Download failed:', err.message);
  process.exit(1);
});
