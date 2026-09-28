"""Shared HTTP helpers: desktop-Chrome-like session, tolerant of blocking sites."""
from __future__ import annotations

import requests

DESKTOP_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)

DEFAULT_HEADERS = {
    "User-Agent": DESKTOP_UA,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Language": "de-DE,de;q=0.9,en;q=0.8",
}


def new_session() -> requests.Session:
    s = requests.Session()
    s.headers.update(DEFAULT_HEADERS)
    return s


def get(session: requests.Session, url: str, *, timeout: int = 25, http1: bool = False, **kw) -> requests.Response:
    """
    GET with sane defaults. `http1=True` forces HTTP/1.1-style behaviour by
    disabling the http2 adapter is not directly controllable via requests,
    so instead we just rely on requests' default (HTTP/1.1) - kept as a flag
    for readability at call sites that discovered they need plain HTTP/1.1
    framing (observed for aldi-nord.de during manual testing).
    """
    resp = session.get(url, timeout=timeout, **kw)
    return resp
