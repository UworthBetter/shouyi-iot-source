"""Build the direct, offline SLE gateway without changing archived cloud images."""
from pathlib import Path
import subprocess
import shutil
import hashlib

root = Path(__file__).resolve().parents[1]
sdk = Path(r"D:\sdk\nearlink\fbb_ws63\src")
config = sdk / "build/config/target_config/ws63/menuconfig/acore/ws63_liteos_app.config"
saved = config.read_bytes()
try:
    config.write_bytes((root / "fw/configs/ws63_gateway_direct.config").read_bytes())
    # Remove archive members from a previously built relay variant.
    (sdk / "output/ws63/acore/ws63-liteos-app/application/samples/libsamples.a").unlink(missing_ok=True)
    log = root / "logs/ws63_local_bridge_build.log"
    with log.open("w", encoding="utf-8") as out:
        result = subprocess.run([r"D:\Git\bin\bash.exe", str(root / "tools/build_ws63.sh"),
                                 "ws63-liteos-app"], stdout=out, stderr=subprocess.STDOUT)
    if result.returncode:
        print(log.read_text(encoding="utf-8", errors="replace")[-6000:])
        raise SystemExit(result.returncode)
    source = sdk / "output/ws63/fwpkg/ws63-liteos-app/ws63-liteos-app_all.fwpkg"
    dest = root / "fw/bins/ws63_local_bridge_all.fwpkg"
    shutil.copy2(source, dest)
    shutil.copy2(config, root / "fw/configs/ws63_local_bridge.config")
    print("Built:", dest)
    print("SHA256:", hashlib.sha256(dest.read_bytes()).hexdigest())
finally:
    config.write_bytes(saved)
