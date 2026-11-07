#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""IoTDA MQTT 认证公式爆破: 用已知 secret 在线验证 clientId/password 组合, 找出 CONNACK rc=0 的那个"""
import hmac, hashlib, socket, time, datetime

DEV = "6ad6dbb77f2e6c302fa4ef57_sy-nearlink-001"
SECRET = "shouyi-nl-2026"
HOST, PORT = "121.36.42.100", 1883

def hm(key, msg):
    return hmac.new(key.encode(), msg.encode(), hashlib.sha256).hexdigest()

def build_connect(client_id, username, password):
    def s(b):
        return len(b).to_bytes(2, "big") + b
    vb = s(b"MQTT") + bytes([0x04])
    vb += bytes([0xC2])  # username+password+clean
    vb += (60).to_bytes(2, "big")
    vb += s(client_id.encode()) + s(username.encode()) + s(password.encode())
    return bytes([0x10, len(vb)]) + vb

def try_connect(client_id, password, timeout=6):
    try:
        sock = socket.create_connection((HOST, PORT), timeout=timeout)
    except Exception as e:
        return "TCP_FAIL:%s" % e
    sock.settimeout(timeout)
    try:
        sock.sendall(build_connect(client_id, DEV, password))
        data = sock.recv(4)
        if len(data) >= 4 and data[0] == 0x20:
            return data[3]  # CONNACK rc
        return "BAD_RESP:%s" % data.hex()
    except Exception as e:
        return "TIMEOUT"
    finally:
        try:
            sock.close()
        except Exception:
            pass

ts = datetime.datetime.now().strftime("%Y%m%d%H")
inner_hex = hm(SECRET, DEV)
inner_raw = hmac.new(SECRET.encode(), DEV.encode(), hashlib.sha256).digest()

pwds = {
    "F1 key=secret msg=ts": hm(SECRET, ts),
    "F2 key=ts msg=secret": hm(ts, SECRET),
    "F3 key=innerhex msg=ts": hm(inner_hex, ts),
    "F4 key=innerraw msg=ts": hmac.new(inner_raw, ts.encode(), hashlib.sha256).hexdigest(),
    "F5 key=secret msg=dev+ts": hm(SECRET, DEV + ts),
    "F6 key=secret msg=ts+dev": hm(SECRET, ts + DEV),
    "F7 innerhex msg=dev+ts": hm(inner_hex, DEV + ts),
    "F8 plain secret": SECRET,
    "F9 key=dev msg=ts": hm(DEV, ts),
}

ids = {
    "C1 dev_0_0_ts": DEV + "_0_0_" + ts,
    "C2 dev_0_ts": DEV + "_0_" + ts,
    "C3 dev_0_0": DEV + "_0_0",
}

print("device:", DEV, "ts:", ts)
for iname, cid in ids.items():
    for pname, pwd in pwds.items():
        rc = try_connect(cid, pwd)
        mark = "  <<< SUCCESS" if rc == 0 else ""
        print("%s + %s -> rc=%s%s" % (iname, pname, rc, mark))
        if rc == 0:
            print("\nWINNER: clientId=%s\npassword=%s" % (cid, pwd))
            raise SystemExit(0)
        time.sleep(0.3)
print("all combos failed")
