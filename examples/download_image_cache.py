# -*- coding: utf-8 -*-

import time
import curly as curl

counter = 0

def on_complete_image(result):
    global counter
    counter += 1
    print("on_complete_image", result.url, result.error, result.image)

curl.download_image(
    "http://invalid/",
    on_complete_image,
    cache_fn="./test.png")

while True:
    curl.process()
    if counter == 1:
        break
    time.sleep(.1)
