"""Reject stale ELF/BIN/packaged firmware before archiving a local bridge build."""
from pathlib import Path
import hashlib
import json

out = Path('/root/txsmart/out/rk2206/isoftstone-rk2206')
app_library = out / 'libs/libiot_smart_home_example.a'
files = {name: out / name for name in ('liteos.elf', 'liteos.bin', 'images/Firmware.img')}
markers = [b'SLE:%s P:%u RX:%lu OK:%lu', b'[sy nearlink] UART0 RX=PB6',
           b'[sy 433] B0=%d door=%d']
report = {}
for name, path in files.items():
    data = path.read_bytes()
    missing = [marker.decode() for marker in markers if marker not in data]
    if missing:
        raise SystemExit(f'REJECT {name}: missing new application markers: {missing}')
    if path.stat().st_mtime_ns < app_library.stat().st_mtime_ns:
        raise SystemExit(f'REJECT {name}: older than application library')
    report[name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
binary = files['liteos.bin'].read_bytes()
image = files['images/Firmware.img'].read_bytes()
offset = image.find(binary)
if offset < 0:
    raise SystemExit('REJECT: packaged firmware does not contain the freshly linked BIN byte-for-byte')
report['packed_bin_offset'] = offset
manifest = Path(__file__).resolve().parents[1] / 'logs/rk_firmware_manifest.json'
manifest.write_text(json.dumps(report, indent=2), encoding='utf-8')
print('PASS: new code present in ELF, BIN, and packaged firmware; exact BIN containment verified')
print(json.dumps(report, indent=2))
