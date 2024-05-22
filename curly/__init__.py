# -*- coding: utf-8 -*-
"""
Asynchronous downloader using libcurl
=====================================

See README.md for more information.
"""

__version__ = "1.0.4"
from ._curly import (
    request, download_image, process, install, uninstall, stop,
    get_info, configure, CurlyResult, CurlyError, CurlyHTTPError)
