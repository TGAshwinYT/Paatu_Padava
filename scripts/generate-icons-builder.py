import os
from PIL import Image
import base64
import io

source_path = r'C:\Users\Ash\.gemini\antigravity\brain\154c28a1-b872-4f39-a762-f2f140700f34\media__1775535301746.jpg'
frontend_dir = r'd:\Library\Ashwin\Offical\TamilGaming\Music\Music 2\Paatu_Paaduva\frontend'
scripts_dir = os.path.join(frontend_dir, 'scripts')
os.makedirs(scripts_dir, exist_ok=True)
js_file_path = os.path.join(scripts_dir, 'generate-icons.js')

try:
    img = Image.open(source_path)
    
    # Generate 192x192 base64
    icon192 = img.resize((192, 192), Image.Resampling.LANCZOS)
    icon192_bytes = io.BytesIO()
    icon192.save(icon192_bytes, format='PNG', optimize=True)
    icon192_b64 = base64.b64encode(icon192_bytes.getvalue()).decode('utf-8')
    
    # Generate 512x512 base64
    icon512 = img.resize((512, 512), Image.Resampling.LANCZOS)
    icon512_bytes = io.BytesIO()
    icon512.save(icon512_bytes, format='PNG', optimize=True)
    icon512_b64 = base64.b64encode(icon512_bytes.getvalue()).decode('utf-8')

    # Generate logo (same as 512 for now)
    logo_b64 = icon512_b64

    # Generate Node.js script
    js_content = f"""
import fs from 'fs';
import path from 'path';
import {{ fileURLToPath }} from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const publicDir = path.join(__dirname, '..', 'public');

if (!fs.existsSync(publicDir)) {{
    fs.mkdirSync(publicDir, {{ recursive: true }});
}}

const icon192 = "{icon192_b64}";
const icon512 = "{icon512_b64}";
const logo = "{logo_b64}";

fs.writeFileSync(path.join(publicDir, 'icon-192x192.png'), Buffer.from(icon192, 'base64'));
fs.writeFileSync(path.join(publicDir, 'icon-512x512.png'), Buffer.from(icon512, 'base64'));
fs.writeFileSync(path.join(publicDir, 'logo.png'), Buffer.from(logo, 'base64'));

console.log('Icons correctly generated from base64 strings.');
"""

    with open(js_file_path, 'w', encoding='utf-8') as f:
        f.write(js_content)
        
    print(f"Successfully generated {js_file_path}")

except Exception as e:
    print(f"Error: {e}")
