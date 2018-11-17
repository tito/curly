
import os
os.environ["KIVY_NO_ARGS"] = "1"
import curly
import pytest
from time import time, sleep


URL = "https://httpbin.org/anything"
TIMEOUT = 5

def curly_request(*largs, **kwargs):
    result = {"req": None}

    def _callback(req):
        result["req"] = req

    kwargs["callback"] = _callback
    curly.request(*largs, **kwargs)

    start = time()
    while time() - start < TIMEOUT:
        curly.process()
        if result["req"]:
            return result["req"]
        sleep(.1)

    raise Exception("Timeout")


def test_basic():
    req = curly_request(URL)
    assert req is not None
    req.raise_for_status()
    assert req.url == URL
    assert req.curl_ret == 0
    assert req.status_code == 200
    assert isinstance(req.headers, dict)
    assert "content-type" in req.headers
    assert "content-length" in req.headers


def test_invalid_url():
    req = curly_request("azmodiajzmdoijzamoij")
    with pytest.raises(curly.CurlyError):
        req.raise_for_status()

    try:
        req.raise_for_status()
        assert 0
    except curly.CurlyError as c:
        assert c.code == 6
