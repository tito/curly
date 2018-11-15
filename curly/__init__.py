# -*- coding: utf-8 -*-
"""
Asynchronous downloader using libcurl
=====================================

This network downloader is using pure C threads and libcurl for
downloading data from HTTP without pressuring the Python GIL.

The goal was to prevent micro lag on the Kivy UI running in the main
thread by preventing the GIL to be locked in another threads, or even
prevent completely Python threads and so GIL switch between threads.

Features:

- Asynchronously download HTTP URL
- Preload image
- Basic caching support


.. todo::

  - make it work under msvc (http://forum.blackvoxel.com/index.php?topic=84.0)
  - unittests


Basic usage
-----------

You have 2 ways to execute a download:

- use :func:`request` to download a resource at a specific URL
- use :func:`download_image` to download a resource and preload the
  image, if the request succedded and the image format is known

The download will be done in background, and the threads will emit a
result in a queue. You need to process as much as possible the queue
to have your callback called within your application:

- use :func:`install` to install a Kivy clock scheduler that will
  process the result every tick (you can :func:`uninstall` it at
  any times)
- or call yourself :func:`process` when you need too.


Request an URL and get the data
-------------------------------

::

    from curly import curl
    curl.install()

    def on_complete(result):
        result.raise_for_status()
        print("Data: {!r}".format(result.data))

    curl.request("https://kivy.org", on_complete)


Download an image
-----------------

TIP: check for the `AsyncCurlImage` in the
`kivy/examples/network/image_browser.py` to have an idea about how to use
it within an Image widget.

::

    from curly import curl
    curl.install()

    def on_complete(result):
        result.raise_for_status()
        print("Image is: {!r}", result.image)
        print("Texture is: {!r}", result.image.texture)

    url = "https://dummyimage.com/600x400/000/fff"
    curl.download_image(url, on_complete)

"""

__version__ = "1.0.0.dev0"
from ._curly import (
    request, download_image, process, install, uninstall, stop,
    CurlResult, HTTPError)
