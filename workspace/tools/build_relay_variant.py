"""Build one WS63 variant, archive its firmware, and restore the active config."""
import argparse
import hashlib
import subprocess
import shutil
import prepare_relay as relay

parser = argparse.ArgumentParser()
parser.add_argument("variant", choices=["relay", "gateway-relay", "direct"])
args = parser.parse_args()
names = {"relay": "ws63_relay_all.fwpkg", "gateway-relay": "ws63_gateway_via_relay_all.fwpkg",
         "direct": "ws63_gateway_direct_all.fwpkg"}
saved = relay.CONFIG.read_bytes()
log = relay.ROOT / "logs" / f"ws63_{args.variant}_build.log"
try:
    relay.install()
    relay.select(args.variant)
    # The SDK archive rule appends members. Remove this generated archive so
    # objects from a previously selected sample cannot remain linked into it.
    archive = relay.SDK / "output/ws63/acore/ws63-liteos-app/application/samples/libsamples.a"
    archive.unlink(missing_ok=True)
    with log.open("w", encoding="utf-8") as output:
        result = subprocess.run([r"D:\Git\bin\bash.exe", str(relay.ROOT / "tools/build_ws63.sh"),
                                 "ws63-liteos-app"], cwd=relay.ROOT, stdout=output,
                                stderr=subprocess.STDOUT)
    if result.returncode != 0:
        print(log.read_text(encoding="utf-8", errors="replace")[-6000:])
        raise SystemExit(result.returncode)
    source = relay.SDK / "output/ws63/fwpkg/ws63-liteos-app/ws63-liteos-app_all.fwpkg"
    destination = relay.ROOT / "fw/bins" / names[args.variant]
    shutil.copy2(source, destination)
    shutil.copy2(relay.CONFIG, relay.ARCHIVE / f"ws63_{args.variant}.config")
    symbols = relay.ROOT / "fw/symbols" / args.variant
    symbols.mkdir(parents=True, exist_ok=True)
    for name in ("ws63-liteos-app.elf", "ws63-liteos-app.map"):
        debug_file = relay.SDK / "output/ws63/acore/ws63-liteos-app" / name
        if debug_file.exists():
            shutil.copy2(debug_file, symbols / name)
    print("Build succeeded:", destination)
    print("SHA256:", hashlib.sha256(destination.read_bytes()).hexdigest())
finally:
    relay.CONFIG.write_bytes(saved)
