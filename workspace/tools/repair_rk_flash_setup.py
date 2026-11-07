"""Stage validated images and rebuild the two-row RKDevTool config with absolute paths.

Run after closing RKDevTool so it cannot save stale settings over this repair.
"""
from pathlib import Path
import hashlib
import json
import re
import shutil

root = Path(__file__).resolve().parents[1]
tool = Path(r'D:\RKDevTool')
source = root / 'fw/bins/rk2206_local_bridge/Firmware.img'
manifest = json.loads((root / 'logs/rk_firmware_manifest.json').read_text(encoding='utf-8'))
expected = manifest['images/Firmware.img']['sha256']
data = source.read_bytes()
assert hashlib.sha256(data).hexdigest() == expected, 'Firmware differs from validated package'
assert all(s in data for s in [b'SLE:%s P:%u RX:%lu OK:%lu',
                              b'[sy nearlink] UART0 RX=PB6', b'[sy 433] B0=%d door=%d'])
images = tool / 'images'
images.mkdir(exist_ok=True)
shutil.copy2(source, images / 'Firmware.img')
loader = Path(r'D:\jishe\sssss\.iot_design\firmware\rk2206_db_loader.bin')
assert loader.is_file()
shutil.copy2(loader, images / loader.name)

# RKDevTool 2.63 stores fixed-size UTF-16 fields in this binary config.
# Keep record sizes and every other byte from the proven two-row backup.
template = (root / 'fw/configs/rkdevtool_before_local_bridge.cfg').read_bytes()
paths = [s for s in re.findall(rb'(?:[\x20-\x7e]\x00){8,}', template)
         if s.decode('utf-16le').startswith('..')]
assert len(paths) == 2, 'Unexpected config template'
config = template
for old, name in zip(paths, ('rk2206_db_loader.bin', 'Firmware.img')):
    new = str(images / name).encode('utf-16le')
    assert len(new) <= len(old) and config.count(old) == 1
    config = config.replace(old, new + bytes(len(old) - len(new)), 1)
assert len(config) == len(template)
(root / 'fw/configs/rkdevtool_absolute.cfg').write_bytes(config)
(tool / 'config.cfg').write_bytes(config)

# Preserve the original INI encoding and set an absolute config filename too.
ini_path = tool / 'config.ini'
ini = ini_path.read_bytes()
encoding = 'utf-16' if ini.startswith(b'\xff\xfe') else 'latin1'
text = ini.decode(encoding)
text, count = re.subn(r'(?m)^DEFAULT_IMAGE_CONFIG=[^\r\n]*',
                     lambda _: 'DEFAULT_IMAGE_CONFIG=D:\\RKDevTool\\config.cfg', text)
assert count == 1, 'DEFAULT_IMAGE_CONFIG not found'
backup = tool / 'config.ini.bak_before_absolute_paths'
if not backup.exists():
    shutil.copy2(ini_path, backup)
ini_path.write_bytes(text.encode(encoding))
print('Repaired two-row config; absolute image paths:')
print(images / 'rk2206_db_loader.bin')
print(images / 'Firmware.img')
print('Firmware SHA256:', expected)
