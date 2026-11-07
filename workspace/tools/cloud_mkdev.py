#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""创建 IoTDA 设备 sy-nearlink-001（复用 sy-rk2206-001 的产品，即 monitor 物模型）"""
import json, ssl, urllib.request, sys

IAM = "https://iam.cn-north-4.myhuaweicloud.com/v3/auth/tokens"
APP_EP = "https://2eb62113b2.st1.iotda-app.cn-north-4.myhuaweicloud.com"
REF_DEVICE = "6ad6dbb77f2e6c302fa4ef57_sy-rk2206-001"
NEW_NODE = "sy-nearlink-001"
NEW_DEVICE = "6ad6dbb77f2e6c302fa4ef57_" + NEW_NODE
SECRET = "shouyi-nl-2026"

body = {
    "auth": {"identity": {"methods": ["password"], "password": {"user": {
        "name": "shouyi-app", "password": "mmy262455",
        "domain": {"name": "hid_gk2lr21z__-uc0-"}}}},
        "scope": {"project": {"name": "cn-north-4"}}}
}

req = urllib.request.Request(IAM, data=json.dumps(body).encode(),
                             headers={"Content-Type": "application/json"}, method="POST")
ctx = ssl.create_default_context()
resp = urllib.request.urlopen(req, timeout=20, context=ctx)
token = resp.headers.get("X-Subject-Token")
project_id = json.loads(resp.read().decode())["token"]["project"]["id"]
print("TOKEN_OK project:", project_id)

def get(url):
    r = urllib.request.Request(url, headers={"X-Auth-Token": token})
    return json.loads(urllib.request.urlopen(r, timeout=20, context=ctx).read().decode())

def post(url, payload):
    r = urllib.request.Request(url, data=json.dumps(payload).encode(),
                               headers={"X-Auth-Token": token, "Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(r, timeout=20, context=ctx).read().decode())

ref = get(f"{APP_EP}/v5/iot/{project_id}/devices/{REF_DEVICE}")
product_id = ref.get("product_id")
print("REF product_id:", product_id)

# 已存在则直接报出来
try:
    d = get(f"{APP_EP}/v5/iot/{project_id}/devices/{NEW_DEVICE}")
    print("DEVICE_EXISTS:", d.get("device_id"), "status:", d.get("status"))
    print("USE secret from console or as previously set")
    sys.exit(0)
except Exception:
    pass

created = post(f"{APP_EP}/v5/iot/{project_id}/devices", {
    "device_id": NEW_DEVICE,
    "node_id": NEW_NODE,
    "product_id": product_id,
    "device_name": "shouyi-nearlink-gw",
    "auth_info": {"secret": SECRET},
})
print("DEVICE_CREATED:", created.get("device_id"))
print("SECRET:", SECRET)
print("MQTT: clientId=%s_0_0 username=%s password=%s" % (NEW_DEVICE, NEW_DEVICE, SECRET))
