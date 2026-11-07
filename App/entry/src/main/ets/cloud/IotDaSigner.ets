/**
 * @file    IotDaSigner.ets
 * @brief   华为云 AK/SK 请求签名（SDK-HMAC-SHA256）
 *
 * 为什么用 AK/SK 而不是 IAM token：
 *   token 24 小时过期，答辩现场一旦过期全盘 401；
 *   AK/SK 长期有效，签名在本地算，不依赖任何登录态。
 *
 * 签名规范（华为云官方 SDK-HMAC-SHA256）：
 *   CanonicalRequest =
 *       Method + '\n' + URI + '\n' + Query + '\n' +
 *       CanonicalHeaders + '\n' + SignedHeaders + '\n' +
 *       Hex(SHA256(Payload))
 *   StringToSign =
 *       'SDK-HMAC-SHA256' + '\n' + X-Sdk-Date + '\n' +
 *       Hex(SHA256(CanonicalRequest))
 *   Signature = Hex(HMAC-SHA256(SK, StringToSign))
 *   Authorization: SDK-HMAC-SHA256 Access=AK, SignedHeaders=..., Signature=...
 *
 * 注意 CanonicalHeaders 每行自带 '\n'，拼接时还会再加一个 '\n'，
 * 所以中间会出现一个空行 —— 这是规范要求，不是 bug。
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';

const HEX_CHARS: string = '0123456789abcdef';

/** 字节数组转小写十六进制 */
function toHex(bytes: Uint8Array): string {
  let out: string = '';
  for (let i: number = 0; i < bytes.length; i++) {
    const b: number = bytes[i];
    out += HEX_CHARS.charAt((b >> 4) & 0x0F) + HEX_CHARS.charAt(b & 0x0F);
  }
  return out;
}

/** 字符串转 UTF-8 字节 */
function toBytes(text: string): Uint8Array {
  const buf = buffer.from(text, 'utf-8');
  return new Uint8Array(buf.buffer);
}

/** SHA256 -> hex */
async function sha256Hex(text: string): Promise<string> {
  const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
  await md.update({ data: toBytes(text) });
  const digest: cryptoFramework.DataBlob = await md.digest();
  return toHex(digest.data);
}

/** HMAC-SHA256 -> hex */
async function hmacSha256Hex(key: string, msg: string): Promise<string> {
  // mac.init() 需要 SymKey 而不是 DataBlob，所以先用 HMAC 密钥生成器转换
  const kg: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
  const keyBlob: cryptoFramework.DataBlob = { data: toBytes(key) };
  const symKey: cryptoFramework.SymKey = await kg.convertKey(keyBlob);

  const mac: cryptoFramework.Mac = cryptoFramework.createMac('SHA256');
  await mac.init(symKey);
  await mac.update({ data: toBytes(msg) });
  const out: cryptoFramework.DataBlob = await mac.doFinal();
  return toHex(out.data);
}

/** 当前 UTC 时间 -> 20261021T070316Z */
function sdkDate(): string {
  const d: Date = new Date();
  const p2 = (n: number): string => n < 10 ? `0${n}` : `${n}`;
  return `${d.getUTCFullYear()}${p2(d.getUTCMonth() + 1)}${p2(d.getUTCDate())}` +
    `T${p2(d.getUTCHours())}${p2(d.getUTCMinutes())}${p2(d.getUTCSeconds())}Z`;
}

/** 签名结果：直接塞进 HTTP 请求头 */
export class SignedHeaders {
  host: string = '';
  sdkDate: string = '';
  authorization: string = '';
  contentType: string = 'application/json';
}

export class IotDaSigner {
  private ak: string = '';
  private sk: string = '';

  constructor(ak: string, sk: string) {
    this.ak = ak;
    this.sk = sk;
  }

  isConfigured(): boolean {
    return this.ak.length > 0 && this.sk.length > 0;
  }

  /**
   * 生成签名头。
   * @param method  GET / POST / PUT / DELETE
   * @param host    不带 https:// 的域名
   * @param uri     以 / 开头的路径，不含查询串
   * @param query   查询串（不带 ?），没有传空串
   * @param payload 请求体原文，GET 传空串
   */
  async sign(method: string, host: string, uri: string,
             query: string, payload: string): Promise<SignedHeaders> {
    const date: string = sdkDate();

    // CanonicalHeaders：按 header 名小写字典序，每行以 \n 结尾
    const canonicalHeaders: string = `host:${host}\n` + `x-sdk-date:${date}\n`;
    const signedHeaders: string = 'host;x-sdk-date';

    const payloadHash: string = await sha256Hex(payload);
    const canonicalRequest: string =
      `${method}\n${uri}\n${query}\n${canonicalHeaders}\n${signedHeaders}\n${payloadHash}`;

    const crHash: string = await sha256Hex(canonicalRequest);
    const stringToSign: string = `SDK-HMAC-SHA256\n${date}\n${crHash}`;
    const signature: string = await hmacSha256Hex(this.sk, stringToSign);

    const h: SignedHeaders = new SignedHeaders();
    h.host = host;
    h.sdkDate = date;
    h.authorization =
      `SDK-HMAC-SHA256 Access=${this.ak}, SignedHeaders=${signedHeaders}, Signature=${signature}`;
    return h;
  }
}
