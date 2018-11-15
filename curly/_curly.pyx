# -*- coding: utf-8 -*-

# Cython import
from libc.stdio cimport printf, FILE, fopen, fwrite, fclose
from libc.stdlib cimport malloc, calloc, free, realloc
from libc.string cimport memset, strdup, memcpy, strlen
from cpython.ref cimport PyObject, Py_XINCREF, Py_XDECREF
from posix.unistd cimport access, F_OK
from libcpp cimport bool

# Python import
from kivy.core.image import Image as CoreImage
from kivy.core.image import ImageLoaderBase, ImageData
from kivy.clock import Clock
import json

include "_include.pxi"
include "_queue.pxi"


cdef queue_ctx ctx_download
cdef queue_ctx ctx_result
cdef queue_ctx ctx_thread
cdef int dl_running = 0
cdef int dl_stop = 0
cdef SDL_sem *dl_sem
cdef SDL_atomic_t dl_done


cdef size_t _curl_write_data(void *ptr, size_t size, size_t nmemb, dl_queue_data *data):
    cdef:
        size_t index = data.size
        size_t n = (size * nmemb)
        char* tmp
    data.size += (size * nmemb)
    tmp = <char *>realloc(data.data, data.size + 1)

    if tmp != NULL:
        data.data = tmp
    else:
        if data.data != NULL:
            free(data.data)
        return 0

    memcpy((data.data + index), ptr, n)
    data.data[data.size] = '\0'
    return size * nmemb


cdef size_t _curl_write_header(void *ptr, size_t size, size_t nmemb, dl_queue_data *data):
    cdef char *tmp

    tmp = <char *>malloc(size * nmemb + 1)
    memcpy(tmp, ptr, size * nmemb)
    tmp[size * nmemb] = '\0'

    data.resp_headers = curl_slist_append(
        data.resp_headers, tmp)

    free(tmp)
    return size * nmemb


cdef int dl_run_job(void *arg) nogil:
    cdef:
        dl_queue_data *data
        CURL *curl
        SDL_RWops *rw
        int require_download
        FILE *fp


    curl = curl_easy_init()
    if not curl:
        return -1

    while SDL_AtomicGet(&dl_done) == 0:
        SDL_SemWait(dl_sem)
        data = <dl_queue_data *>queue_pop_first(&ctx_download)
        if data == NULL:
            continue

        require_download = 1

        if data.cache_fn != NULL and access(data.cache_fn, F_OK) != -1:
            require_download = 0

        if require_download:
            # download from url
            curl_easy_setopt(curl, CURLOPT_URL, data.url)
            curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, _curl_write_data)
            curl_easy_setopt(curl, CURLOPT_WRITEDATA, data)
            curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, _curl_write_header)
            curl_easy_setopt(curl, CURLOPT_HEADERDATA, data)
            curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, <void *><long>1L)
            # curl_easy_setopt(curl, CURLOPT_VERBOSE, <void *><long>1L)
            if data.headers != NULL:
                curl_easy_setopt(curl, CURLOPT_HTTPHEADER, data.headers)
            data.status_code = curl_easy_perform(curl)

            if data.cache_fn != NULL and data.size > 0:
                fp = fopen(data.cache_fn, "wb")
                fwrite(data.data, data.size, 1, fp)
                fclose(fp)

        # dynamically load the image too ?
        if data.preload_image:
            rw = NULL
            if data.size > 0:
                rw = SDL_RWFromMem(data.data, data.size)
            elif data.cache_fn != NULL:
                rw = SDL_RWFromFile(data.cache_fn, "rb")
            if rw:
                data.image = IMG_Load_RW(rw, 1)
                if data.image == NULL:
                    data.image_error = <char *>IMG_GetError()
                if data.data != NULL:
                    free(data.data)
                data.data = NULL

        queue_append_last(&ctx_result, data)

    curl_easy_cleanup(curl)
    return 0


cdef void dl_init(int num_threads) nogil:
    # prepare the queue and background threads
    cdef SDL_Thread *thread
    cdef int index
    global dl_sem, dl_running
    queue_init(&ctx_download)
    queue_init(&ctx_result)
    queue_init(&ctx_thread)
    SDL_AtomicSet(&dl_done, 0)
    dl_sem = SDL_CreateSemaphore(0)

    for index in range(num_threads):
        thread = SDL_CreateThread(dl_run_job, "curl", NULL)
        queue_append_last(&ctx_thread, thread)

    dl_running = 1


cdef void dl_ensure_init() nogil:
    # ensure the download threads are ready
    if dl_running:
        return
    dl_init(4)


cdef load_from_surface(SDL_Surface *image):
    # taken from _img_sdl2, just for test.
    cdef SDL_Surface *image2 = NULL
    cdef SDL_Surface *fimage = NULL
    cdef SDL_PixelFormat pf
    cdef bytes pixels

    try:
        if image == NULL:
            return None

        fmt = ''
        if image.format.BytesPerPixel == 3:
            fmt = 'rgb'
        elif image.format.BytesPerPixel == 4:
            fmt = 'rgba'

        # FIXME the format might be 3 or 4, but it doesn't mean it's rgb/rgba.
        # It could be argb, bgra etc. it needs to be detected correctly. I guess
        # we could even let the original pass, bgra / argb support exists in
        # some opengl card.

        if fmt not in ('rgb', 'rgba'):
            if fmt == 'rgb':
                pf.format = SDL_PIXELFORMAT_BGR888
                fmt = 'rgb'
            else:
                pf.format = SDL_PIXELFORMAT_ABGR8888
                fmt = 'rgba'

            image2 = SDL_ConvertSurfaceFormat(image, pf.format, 0)
            if image2 == NULL:
                return

            fimage = image2
        else:
            if (image.format.Rshift > image.format.Bshift):
                memset(&pf, 0, sizeof(pf))
                pf.BitsPerPixel = 32
                pf.Rmask = 0x000000FF
                pf.Gmask = 0x0000FF00
                pf.Bmask = 0x00FF0000
                pf.Amask = 0xFF000000
                image2 = SDL_ConvertSurface(image, &pf, 0)
                fimage = image2
            else:
                fimage = image

        pixels = (<char *>fimage.pixels)[:fimage.pitch * fimage.h]
        return (fimage.w, fimage.h, fmt, pixels, fimage.pitch)

    finally:
        if image2:
            SDL_FreeSurface(image2)


class ImageLoaderMemory(ImageLoaderBase):
    # Internal loader for data loaded from SDL2
    def __init__(self, filename, data, **kwargs):
        w, h, fmt, pixels, rowlength = data
        self._data = [ImageData(
            w, h, fmt, pixels, source=filename, rowlength=rowlength)]
        super(ImageLoaderMemory, self).__init__(filename, **kwargs)

    def load(self, kwargs):
        return self._data

#
# API
#

class HTTPError(Exception):
    """HTTP Error that can be sent when :method:`CurlResult.raise_for_status`
    is raising an exception
    """
    pass


cdef class CurlResult(object):
    """Object containing a result from a request.
    """
    cdef:
        dl_queue_data *_data
        dict _headers
        object _json
        object _image
        bytes _reason

    def __cinit__(self):
        self._data = NULL

    def __init__(self):
        self._headers = None
        self._json = None
        self._image = None
        self._reason = None

    def __dealloc__(self):
        if self._data != NULL:
            dl_queue_node_free(&self._data)

    @property
    def image(self):
        """Return the CoreImage associated to the url
        Only if preload_image was used
        """
        if self._image is not None:
            return self._image

        if not self._data.preload_image:
            raise Exception("Preload image not used")

        # send back an image
        # FIXME: optimization would be to prevent any conversion
        # here, but rather in the thread, if anything has to be done.
        # So using the load_from_surface will disapear somehow to have
        # a fully C version that doesn't require python.
        image = load_from_surface(self._data.image)
        loader = ImageLoaderMemory(self._data.url.decode("utf8"), image)
        self._image = CoreImage(loader)
        return self._image


    @property
    def url(self):
        """Return the url of the result
        """
        return self._data.url.decode("utf8")

    @property
    def error(self):
        """Error message if anything wrong happened
        """
        if self._data.image_error != NULL:
            return self._data.image_error.decode("utf8")

    @property
    def status_code(self):
        """HTTP Status Code
        """
        return self._data.status_code

    @property
    def headers(self):
        """HTTP Response headers
        """
        self._parse_headers()
        return self._headers

    @property
    def reason(self):
        """HTTP Reason
        """
        self._parse_headers()
        return self._reason.decode("utf8")

    @property
    def data(self):
        """HTTP Data from the request
        """
        cdef bytes b_data
        if self._data.size > 0:
            b_data = self._data.data[:self._data.size]
            return b_data

    def _parse_headers(self):
        cdef curl_slist *item
        cdef bytes b_data
        if self._headers is not None:
            return
        self._headers = {}
        item = self._data.resp_headers
        while item != NULL:
            b_data = item.data[:strlen(item.data)].strip()
            if b_data.startswith(b"HTTP/"):
                self._reason = b_data.split(b" ", 3)[-1]
            elif b_data:
                key, value = b_data.split(b":", 1)
                key = key.strip().lower()
                value = value.strip()
                # XXX is that can potentially break?
                self._headers[key.decode("utf8")] = value.decode("utf8")
            item = item.next

    def raise_for_status(self):
        """If the HTTP status code was wrong (within 400-599),
        it will raise an :class:`HTTPError` exception
        """
        reason = None
        http_error_msg = None
        if 400 <= self.status_code < 500:
            http_error_msg = u'{} Client Error: {} for url: {}'.format(
                self.status_code, reason, self.url)
        elif 500 <= self.status_code < 600:
            http_error_msg = u'{} Server Error: {} for url: {}'.format(
                self.status_code, reason, self.url)
        if http_error_msg:
            exc = HTTPError(http_error_msg)
            exc.response = self
            raise exc

    def json(self):
        """If the content-type is an application/json, then the data will be
        interpreted and returned
        """
        if not self.headers.get("content-type", "").startswith("application/json"):
            raise Exception("Not a application/json response")
        if self._json is None:
            self._json = json.loads(self.data)
        return self._json

    def __repr__(self):
        return "<CurlResult url={!r}>".format(self.url)


def request(url, callback, headers=None, cache_fn=None, preload_image=False):
    """Execute an HTTP Request asynchronously.
    The result will be dispatched only when :func:`process` is called

    :Parameters:
        `url`: str
            URL to fetch
        `callback`: callable with one argument
            The callback function will receive the :class:`CurlResult` when
            the request is done.
        `headers`: dict
            Dictionnary of all HTTP headers to pass in the request.
            Defaults to None.
        `preload_image`: bool
            If an image is passed in URL, it will be downloaded
            then preloaded via SDL2 to reduce the load on the main thread
            Defaults to False
        `cache_fn`: str
            A basic cache system can be used to save the result of the
            request to the disk. It must be a valid filename in an existing
            directory. If the request succedded, the data will be saved to
            the cache.
            If a later request indicate the same cache_fn, and the cache
            exists, it will be used instead of downloading the data
            from the url.
    """
    cdef:
        dl_queue_data *data = <dl_queue_data *>calloc(1, sizeof(dl_queue_data))
        bytes b_url = url.encode("utf8")
        bytes b_cache_fn
        char *c_url = b_url
        char *c_header
        char *c_cache_fn
    data.status_code = -1
    data.data = NULL
    data.callback = NULL
    data.preload_image = int(preload_image)
    data.url = strdup(c_url)

    if cache_fn is not None:
        b_cache_fn = cache_fn.encode("utf8")
        c_cache_fn = b_cache_fn
        data.cache_fn = strdup(c_cache_fn)
    if headers is not None:
        for key, value in headers.iteritems():
            header = "{}: {}".format(key, value)
            c_header = header
            data.headers = curl_slist_append(
                data.headers, c_header)

    if callback:
        data.callback = <void *>callback
        Py_XINCREF(<PyObject *>data.callback)

    dl_ensure_init()
    queue_append_last(&ctx_download, data)
    SDL_SemPost(dl_sem)


def download_image(*args, **kwargs):
    """A wrapper around :func:`request` that set `preload_image` to True
    """
    kwargs["preload_image"] = True
    request(*args, **kwargs)


def process(*args):
    """Process results. It must be called as must as possible in order
    to process the results from the download threads.

    You can also use :func:`install` to install the process into the Kivy
    Clock.
    """
    cdef:
        CurlResult result
        dl_queue_data *data
        bytes b_data = None
        object callback
        curl_slist *item

    while True:
        data = <dl_queue_data *>queue_pop_first(&ctx_result)
        if data == NULL:
            break

        callback = <object><void *>data.callback
        if not callback:
            continue

        result = CurlResult()
        result._data = data
        callback(result)


def install():
    """Install a scheduler in the Kivy clock to call :func:`process`
    """
    uninstall()
    Clock.schedule_interval(process, 0)


def uninstall():
    """Uninstall the scheduler that call :func:`process` from the Kivy clock
    """
    Clock.unschedule(process)


def stop():
    """Stop any threads working in the background.
    Any ongoing results or request will be stopped.
    """
    uninstall()
    SDL_AtomicSet(&dl_done, 1)
    SDL_SemPost(dl_sem)
    SDL_DestroySemaphore(dl_sem)
