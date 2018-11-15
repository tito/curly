# -*- coding: utf-8 -*-
"""
Demonstration about having a Asynchronous Image viewer
======================================================

It uses the API of http://www.splashbase.co/ and download
around 50 images.

"""

from kivy.app import App
from kivy.lang import Builder
from kivy.uix.relativelayout import RelativeLayout
from kivy.uix.image import Image
from kivy.properties import StringProperty
import curly as curl
import os
from os.path import join, exists, dirname
from kivy.animation import Animation

CACHE_DIR = join(dirname(__file__), "cache")
if not exists(CACHE_DIR):
    os.makedirs(CACHE_DIR)

Builder.load_string("""
<AsyncCurlImage>:
    allow_stretch: True

<ImageList>:
    RecycleView:
        id: rv
        viewclass: "AsyncCurlImage"
        RecycleGridLayout:
            cols: 3
            padding: dp(10)
            spacing: dp(10)
            default_size: None, root.width / self.cols
            default_size_hint: 1, None
            size_hint_y: None
            height: self.minimum_height
            orientation: 'vertical'
""")


class AsyncCurlImage(Image):
    url = StringProperty()
    _anim = None
    CACHE = {}

    def on_url(self, instance, url):
        cache_fn = join(CACHE_DIR, url.rsplit("/", 1)[-1])
        if url in self.CACHE:
            self.texture = self.CACHE[url]
            self.animate()
            return
        self.opacity = 0
        curl.download_image(
            url, self.on_url_downloaded, cache_fn=cache_fn, preload_image=True)

    def on_url_downloaded(self, result):
        result.raise_for_status()
        if result.url != self.url:
            return
        self.texture = result.image.texture
        self.CACHE[result.url] = self.texture
        self.animate()

    def animate(self):
        if self._anim is not None:
            self._anim.stop_all(self)
        self._anim = Animation(opacity=1., d=.1)
        self._anim.start(self)


class ImageList(RelativeLayout):
    def load(self):
        curl.request(
            "http://www.splashbase.co/api/v1/images/latest",
            self._on_api_callback)
        for keyword in ["dog", "mountain", "sea", "city"]:
            curl.request(
                "http://www.splashbase.co/api/v1/images/search?query={}".format(keyword),
                self._on_api_callback)

    def _on_api_callback(self, result):
        result.raise_for_status()
        data = result.json()
        for result in data["images"]:
            self.ids.rv.data.append({"url": result["url"]})


class ImageBrowser(App):
    def build(self):
        curl.install()
        root = ImageList()
        root.load()
        return root


ImageBrowser().run()
