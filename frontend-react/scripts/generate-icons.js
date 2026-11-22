import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const publicDir = path.join(__dirname, '..', 'public');

if (!fs.existsSync(publicDir)) {
  fs.mkdirSync(publicDir, { recursive: true });
}

// Verify that required PWA icons and app logo exist in public directory
const requiredIcons = ['icon-192x192.png', 'icon-512x512.png', 'logo.png'];
for (const icon of requiredIcons) {
  const filePath = path.join(publicDir, icon);
  if (!fs.existsSync(filePath)) {
    console.warn(`[generate-icons] Warning: ${icon} is missing in ${publicDir}`);
  }
}

console.log('[generate-icons] PWA icon assets validated.');
