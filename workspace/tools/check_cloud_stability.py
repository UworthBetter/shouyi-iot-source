"""Read device status and reported properties using the existing local login helper.

Credentials stay in the existing helper; this script never prints its namespace.
"""
import contextlib
import io
import json
import runpy
import sys

helper = sys.argv[1]
with contextlib.redirect_stdout(io.StringIO()):
    session = runpy.run_path(helper)

device = "6ad6dbb77f2e6c302fa4ef57_sy-nearlink-001"
base = f'{session["APP_EP"]}/v5/iot/{session["project_id"]}/devices/{device}'
info = session["get"](base)
shadow = session["get"](base + "/shadow")
reports = []
for entry in shadow.get("shadow", []):
    service = entry.get("service") or entry
    reported = service.get("reported") or {}
    reports.append({
        "service_id": service.get("service_id"),
        "event_time": reported.get("event_time"),
        "properties": reported.get("properties", {}),
    })
print(json.dumps({"device": device, "status": info.get("status"), "reported": reports},
                 ensure_ascii=False, indent=2))
