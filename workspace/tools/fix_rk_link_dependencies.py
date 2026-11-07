"""Repair the SDK link target so updated libraries cannot reuse an old ELF."""
from pathlib import Path
import shutil

makefile = Path('/root/txsmart/device/rockchip/rk2206/sdk_liteos/Makefile')
text = makefile.read_text(encoding='utf-8')
old = '$(BUILD_DIR)/$(TARGET).elf:\n'
new = ('# Relink when application libraries, linker layout, or link flags change.\n'
       '$(BUILD_DIR)/$(TARGET).elf: $(wildcard $(BUILD_DIR)/libs/*.a) $(LDSCRIPT) Makefile\n')
if new not in text:
    assert text.count(old) == 1
    backup = Path(str(makefile) + '.bak_pre_link_dependencies')
    if not backup.exists():
        shutil.copy2(makefile, backup)
    makefile.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')
print('SDK ELF target now depends on linked libraries and linker inputs')
