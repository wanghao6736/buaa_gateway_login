#!/usr/bin/env python3
"""
Login gw.buaa.edu.cn in command-line mode.

Based on:
    https://github.com/luoboganer (2019-09-01)
    https://coding.net/u/huxiaofan1223/p/jxnu_srun/git
    https://blog.csdn.net/qq_41797946/article/details/89417722
Forked from:
    https://github.com/zzdyyy/buaa_gateway_login
"""

import getpass
import hashlib
import hmac
import json
import math
import random
import re
import time
from typing import Any

import requests
import urllib3

urllib3.disable_warnings()

BASE_URL = "https://gw.buaa.edu.cn/cgi-bin"
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Ubuntu Chromium/76.0.3809.100 "
    "Chrome/76.0.3809.100 Safari/537.36"
)
_BASE64_ALPHA = "LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA"
_BASE64_PAD = "="


def _random_num(jq_version: str = '1.12.4') -> str:
    return re.sub(r'\D', '', f"{jq_version}{random.random()}")


def _timestamp_ms() -> int:
    return int(time.time() * 1000)


def get_jsonp(url: str, params: dict[str, Any]) -> dict[str, Any]:
    """Send a JSONP request and decode the response."""
    callback_name = f"jQuery{_random_num()}_{_timestamp_ms()}"
    params["callback"] = callback_name
    resp = requests.get(
        url,
        params=params,
        headers={"User-Agent": USER_AGENT},
        verify=False,
    )
    payload = resp.text[len(callback_name) + 1: -1]
    return json.loads(payload)


def get_ip_token(username: str) -> tuple[str, str]:
    """Fetch client IP and challenge token from the gateway."""
    params = {
        "username": username,
        "ip": "0.0.0.0",
        "_": _timestamp_ms(),
    }
    res = get_jsonp(f"{BASE_URL}/get_challenge", params)
    return res["client_ip"], res["challenge"]


def _build_login_info(username: str, password: str, ip: str) -> str:
    return json.dumps({
        "username": username,
        "password": password,
        "ip": ip,
        "acid": "1",
        "enc_ver": "srun_bx1",
    })


# ── XXTEA / srun_bx1 encoding ─────────────────────────────────────────────────────────

def _char_code_at(msg: str, idx: int) -> int:
    return ord(msg[idx]) if idx < len(msg) else 0


def _str_to_ints(msg: str, include_length: bool) -> list[int]:
    """Pack a string into a list of 32-bit little-endian integers."""
    result = [
        _char_code_at(msg, i)
        | _char_code_at(msg, i + 1) << 8
        | _char_code_at(msg, i + 2) << 16
        | _char_code_at(msg, i + 3) << 24
        for i in range(0, len(msg), 4)
    ]
    if include_length:
        result.append(len(msg))
    return result


def _ints_to_str(ints: list[int], truncate: bool) -> str | None:
    """Unpack a list of 32-bit integers back to a string."""
    length = len(ints)
    raw_len = (length - 1) << 2
    if truncate:
        actual_len = ints[length - 1]
        if actual_len < raw_len - 3 or actual_len > raw_len:
            return None
        raw_len = actual_len

    chars = "".join(
        chr(v & 0xFF)
        + chr((v >> 8) & 0xFF)
        + chr((v >> 16) & 0xFF)
        + chr((v >> 24) & 0xFF)
        for v in ints
    )
    return chars[:raw_len] if truncate else chars


_XXTEA_DELTA = 0x86014019 | 0x183639A0
_XXTEA_MASK = 0xEFB8D130 | 0x10472ECF


def xxtea_encode(msg: str, key: str) -> str | None:
    """XXTEA-encrypt *msg* with *key* (srun portal variant)."""
    if not msg:
        return ""
    pwd = _str_to_ints(msg, True)
    pwdk = _str_to_ints(key, False)
    while len(pwdk) < 4:
        pwdk.append(0)

    n = len(pwd) - 1
    z = pwd[n]
    rounds = math.floor(6 + 52 / (n + 1))
    total = 0

    while rounds > 0:
        total = (total + _XXTEA_DELTA) & _XXTEA_MASK
        e = (total >> 2) & 3
        for p in range(n):
            y = pwd[p + 1]
            m = (z >> 5 ^ y << 2) + ((y >> 3 ^ z << 4) ^ (total ^ y)) + (pwdk[(p & 3) ^ e] ^ z)
            pwd[p] = (pwd[p] + m) & _XXTEA_MASK
            z = pwd[p]
        y = pwd[0]
        m = (z >> 5 ^ y << 2) + ((y >> 3 ^ z << 4) ^ (total ^ y)) + (pwdk[(n & 3) ^ e] ^ z)
        pwd[n] = (pwd[n] + m) & _XXTEA_MASK
        z = pwd[n]
        rounds -= 1

    return _ints_to_str(pwd, False)


# ── Custom Base64 encoding ─────────────────────────────────────────────────────────

def _safe_ord(s: str, i: int) -> int:
    code = ord(s[i])
    if code > 255:
        raise ValueError(f"Invalid character at index {i}: code point {code} > 255")
    return code


def srun_base64_encode(s: str) -> str:
    """Encode *s* using the srun portal's custom base64 alphabet."""
    if not s:
        return s

    result: list[str] = []
    imax = len(s) - len(s) % 3

    for i in range(0, imax, 3):
        b10 = (_safe_ord(s, i) << 16) | (_safe_ord(s, i + 1) << 8) | _safe_ord(s, i + 2)
        result.append(_BASE64_ALPHA[b10 >> 18])
        result.append(_BASE64_ALPHA[(b10 >> 12) & 63])
        result.append(_BASE64_ALPHA[(b10 >> 6) & 63])
        result.append(_BASE64_ALPHA[b10 & 63])

    remainder = len(s) - imax
    if remainder == 1:
        b10 = _safe_ord(s, imax) << 16
        result.append(
            _BASE64_ALPHA[b10 >> 18]
            + _BASE64_ALPHA[(b10 >> 12) & 63]
            + _BASE64_PAD + _BASE64_PAD
        )
    elif remainder == 2:
        b10 = (_safe_ord(s, imax) << 16) | (_safe_ord(s, imax + 1) << 8)
        result.append(
            _BASE64_ALPHA[b10 >> 18]
            + _BASE64_ALPHA[(b10 >> 12) & 63]
            + _BASE64_ALPHA[(b10 >> 6) & 63]
            + _BASE64_PAD
        )

    return "".join(result)


# ── Hashing helpers ─────────────────────────────────────────────────────────

def _hmac_md5(password: str, token: str) -> str:
    return hmac.new(token.encode(), password.encode(), hashlib.md5).hexdigest()


def _sha1(value: str) -> str:
    return hashlib.sha1(value.encode()).hexdigest()


# ── Login ─────────────────────────────────────────────────────────

def login(username: str, password: str) -> dict[str, Any]:
    """Authenticate against the BUAA srun gateway portal."""
    ip, token = get_ip_token(username)
    info = _build_login_info(username, password, ip)

    md5_password = _hmac_md5(password, token)
    encoded_info = "{SRBX1}" + srun_base64_encode(xxtea_encode(info, token))

    chksum_parts = [
        username,
        md5_password,
        "1",       # ac_id
        ip,
        "200",     # n
        "1",       # type
        encoded_info,
    ]
    chksum = _sha1(token + token.join(chksum_parts))

    params = {
        "action": "login",
        "username": username,
        "password": "{MD5}" + md5_password,
        "ac_id": 1,
        "ip": ip,
        "info": encoded_info,
        "n": "200",
        "type": "1",
        "os": "Linux.Hercules",
        "name": "Linux",
        "double_stack": "",
        "chksum": chksum,
        "_": _timestamp_ms(),
    }

    return get_jsonp(f"{BASE_URL}/srun_portal", params)


if __name__ == "__main__":
    import os
    import sys

    print("gw.buaa.edu.cn portal login...")
    uname = os.environ.get("BUAA_USERNAME")
    pwd = os.environ.get("BUAA_PASSWORD")

    result = login(uname, pwd)
    print(json.dumps(result, indent=4, ensure_ascii=False))
    if result.get("error") and result["error"] != "ok":
        sys.exit(1)
