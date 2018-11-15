# Curly

Curly is a minimal wrapper around libcurl, made to download data and images
using pure C threads and libcurl, and release some pressure on Python GIL.

The goal is to prevent micro lag on the Kivy UI running in the main
thread by preventing the GIL to be locked in another threads, or even
prevent completely Python threads and so GIL switch between threads.

Features:

- Asynchronously download HTTP URL (no GIL)
- Basic caching support (no GIL)
- Preload image (GIL required for now)

.. todo::

  - make it work under msvc (http://forum.blackvoxel.com/index.php?topic=84.0)
  - unittests
  - Android support
  - iOS support


## Requirements

- libcurl
- SDL2
- SDL2_image


## Installation

There is no release yet, so you must install it by sources.


## Basic usage

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


## Request an URL and get the data

```python
from curly import curl
curl.install()

def on_complete(result):
    result.raise_for_status()
    print("Data: {!r}".format(result.data))

curl.request("https://kivy.org", on_complete)
```

## Download an image

TIP: check for the `AsyncCurlImage` in the
`examples/image_browser.py` to have an idea about how to use it within
an Image widget.

```python
from curly import curl
curl.install()

def on_complete(result):
    result.raise_for_status()
    print("Image is: {!r}", result.image)
    print("Texture is: {!r}", result.image.texture)

url = "https://dummyimage.com/600x400/000/fff"
curl.download_image(url, on_complete)
```
