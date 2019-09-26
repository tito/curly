# -*- coding: utf-8 -*-

# Cython import
try:
    import _ssl
except ImportError:
    print("curly requires ssl linked, otherwise libcurl won't work")

from libc.stdio cimport printf, FILE, fopen, fwrite, fclose
from libc.stdlib cimport malloc, calloc, free, realloc
from libc.string cimport memset, strdup, memcpy, strlen, strncmp
from json import dumps, loads
from cpython.ref cimport PyObject, Py_XINCREF, Py_XDECREF
from posix.unistd cimport access, F_OK
from libcpp cimport bool
try:
    from urllib.parse import quote
except ImportError:
    from urllib import quote

# Python import
from kivy.core.image import Image as CoreImage
from kivy.core.image import ImageLoaderBase, ImageData
from kivy.clock import Clock
from os.path import dirname, exists
from os import makedirs

include "_include.pxi"
include "_queue.pxi"


cdef queue_ctx ctx_download
cdef queue_ctx ctx_result
cdef queue_ctx ctx_thread
cdef int dl_running = 0
cdef int dl_stop = 0
cdef SDL_sem *dl_sem
cdef SDL_atomic_t dl_done
cdef SDL_atomic_t dl_ready_to_process

cdef int config_num_threads = 4
# very bad, will activate by default once we can check cacert.pem on android
cdef int config_req_verify_peer = 0


cdef size_t _curl_write_data(void *ptr, size_t size, size_t nmemb, dl_queue_data *data) nogil:
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


cdef size_t _curl_write_header(void *ptr, size_t size, size_t nmemb, dl_queue_data *data) nogil:
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
            else:
                curl_easy_setopt(curl, CURLOPT_HTTPHEADER, NULL)
            if data.auth_userpwd != NULL:
                curl_easy_setopt(curl, CURLOPT_HTTPAUTH, CURLAUTH_ANY)
                curl_easy_setopt(curl, CURLOPT_USERPWD, data.auth_userpwd)
            if data.postdata != NULL:
                curl_easy_setopt(curl, CURLOPT_POSTFIELDS, data.postdata)
                curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, strlen(data.postdata))
            if strncmp(data.method, "GET", 3) == 0:
                curl_easy_setopt(curl, CURLOPT_HTTPGET, 1)
            elif strncmp(data.method, "POST", 4) == 0:
                curl_easy_setopt(curl, CURLOPT_HTTPPOST, 1)
            else:
                curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, data.method)
            curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, <void *><long>config_req_verify_peer)
            data.curl_ret = curl_easy_perform(curl)

            if data.curl_ret != 0:
                # if the request failed for any reason,
                # avoid any sort of image preloading
                data.preload_image = 0

            elif data.cache_fn != NULL and data.size > 0:
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
        SDL_AtomicIncRef(&dl_ready_to_process)

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

    curl_global_init(CURL_GLOBAL_ALL)

    for index in range(num_threads):
        thread = SDL_CreateThread(dl_run_job, "curl", NULL)
        queue_append_last(&ctx_thread, thread)

    dl_running = 1


cdef void dl_ensure_init() nogil:
    # ensure the download threads are ready
    if dl_running:
        return
    dl_init(config_num_threads)


def get_info():
    cdef curl_version_info_data *info
    dl_ensure_init()
    info = curl_version_info(CURLVERSION_NOW)
    ret = {}
    if info.version != NULL:
        ret["version"] = info.version.decode("utf8")
    if info.host != NULL:
        ret["host"] = (<char *>info.host).decode("utf8")
    if info.ssl_version != NULL:
        ret["ssl_version"] = (<char *>info.ssl_version).decode("utf8")
    if info.libz_version != NULL:
        ret["libz_version"] = (<char *>info.libz_version).decode("utf8")
    return ret


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

class CurlyError(Exception):
    """Exception raised when something was wrong during the request, when
    checking the result with `raise_for_status`.
    Check the `code` attribute to get the libcurl error code.
    """


class CurlyHTTPError(CurlyError):
    """If the request was ok, this exception is raised if the HTTP status
    code was indicating an issue with the HTTP requests.
    """


cdef class CurlyResult(object):
    """Object containing a result from a request.
    """
    cdef:
        dl_queue_data *_data
        dict _headers
        object _json
        object _image
        bytes _reason
        object _http_status_code

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
            self._data = NULL

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
        if self._data.image == NULL:
            return
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
        self._parse_headers()
        return self._http_status_code

    @property
    def curl_ret(self):
        """Libcurl status after performing the request.
        0 is OK, everything else is an error.

        Check https://curl.haxx.se/libcurl/c/libcurl-errors.html
        """
        return self._data.curl_ret

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
                items = b_data.split(b" ", 3)
                self._http_status_code = int(items[1])
                self._reason = items[-1]
            elif b_data:
                key, value = b_data.split(b":", 1)
                key = key.strip().lower()
                value = value.strip()
                # XXX is that can potentially break?
                self._headers[key.decode("utf8")] = value.decode("utf8")
            item = item.next

    def raise_for_status(self):
        """If the request failed for any reason, it will raise an
        :class:`CurlyError` with the libcurl error code.
        If the request was ok, then it will check if the HTTP status code was
        wrong (within 400-599), in that case it will raise an
        it will raise an :class:`CurlyHTTPError` exception.
        """

        cdef const char *c_msg
        if self.curl_ret != 0:
            c_msg = curl_easy_strerror(self.curl_ret)
            if c_msg == NULL:
                msg = "No error message for {}".format(self.curl_ret)
            else:
                msg = c_msg.decode("utf8")
            exc = CurlyError(msg)
            exc.code = self.curl_ret
            raise exc

        if self.status_code is None:
            # no status code, so it's a cached loading
            return

        reason = None
        http_error_msg = None
        if 400 <= self.status_code < 500:
            http_error_msg = u'{} Client Error: {} for url: {}'.format(
                self.status_code, reason, self.url)
        elif 500 <= self.status_code < 600:
            http_error_msg = u'{} Server Error: {} for url: {}'.format(
                self.status_code, reason, self.url)
        if http_error_msg:
            exc = CurlyHTTPError(http_error_msg)
            exc.response = self
            raise exc

    def json(self):
        """If the content-type is an application/json, then the data will be
        interpreted and returned
        """
        if not self.headers.get("content-type", "").startswith("application/json"):
            raise Exception("Not a application/json response")
        if self._json is None:
            self._json = loads(self.data)
        return self._json

    def __repr__(self):
        return "<CurlyResult url={!r}>".format(self.url)


def request(url, callback, headers=None,
            method="GET", params=None, data=None, json=None,
            auth=None, cache_fn=None, preload_image=False,
            priority=False):
    """Execute an HTTP Request asynchronously.
    The result will be dispatched only when :func:`process` is called

    :Parameters:
        `url`: str
            URL to fetch
        `callback`: callable with one argument
            The callback function will receive the :class:`CurlyResult` when
            the request is done.
        `headers`: dict
            Dictionnary of all HTTP headers to pass in the request.
            Defaults to None.
        `method`: str
            Method of the http request, defaults to "GET".
        `params`: dict
            Dictionnary of additionnal parameters to add in the URL.
            Defaults to None.
        `data`: dict, bytes or unicode
            Data to send in the body if the requests.
            If dict, it will be transformed to a bytes string.
            No multipart/form-data are supported yet.
        `json`: dict
            Data to send in the body of the requests.
            Automatically convert to a bytes string, and set the content type.
        `auth`: tuple
            Authentication support, only (user, password) supported right now.
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
        `priority`: bool
            If True, the URL will be fetch before the other, aka, it will be
            the next to be deque.
            Defaults to False.
    """
    cdef:
        dl_queue_data *qdata
        bytes b_string
        char *c_header

    if data and json:
        raise Exception("Cannot have data and json parameters at the same time")

    # allocate qdata
    qdata = <dl_queue_data *>calloc(1, sizeof(dl_queue_data))
    qdata.preload_image = int(preload_image)

    # url + params
    if params:
        url_suffix = []
        for key, value in params.items():
            value = "{}".format(value)
            url_suffix.append("{}={}".format(quote(key), quote(value)))
        if "?" in url:
            url += "&" + "&".join(url_suffix)
        else:
            url += "?" + "&".join(url_suffix)

    b_string = url.encode("utf8")
    qdata.url = strdup(b_string)

    # method
    b_string = method.encode("utf8")
    qdata.method = strdup(b_string)

    # postdata
    if json is not None:
        data = dumps(json)
        b_string = data.encode("utf8")
        qdata.postdata = strdup(b_string)
        headers["Content-Type"] = "application/json"
    elif isinstance(data, dict):
        # XXX support multipart form-data, using curl_mime
        postdata = []
        for key, value in data.items():
            value = "{}".format(value)
            postdata.append("{}={}".format(quote(key), quote(value)))
        postdata = "&".join(postdata)
        b_string = postdata.encode("utf8")
        qdata.postdata = strdup(b_string)

    if data is not None:
        if isinstance(data, bytes):
            b_string = data
        else:
            b_string = data.encode("utf8")
        qdata.postdata = strdup(b_string)

    # cache
    if cache_fn is not None:
        cache_dir = dirname(cache_fn)
        if not exists(cache_dir):
            makedirs(cache_dir)
        b_string = cache_fn.encode("utf8")
        qdata.cache_fn = strdup(b_string)

    # headers
    if headers is not None:
        for key, value in headers.iteritems():
            header = "{}: {}".format(key, value).encode("utf8")
            c_header = header
            qdata.headers = curl_slist_append(
                qdata.headers, c_header)

    # callback
    if callback is not None:
        qdata.callback = <void *>callback
        Py_XINCREF(<PyObject *>qdata.callback)

    # auth
    if isinstance(auth, (tuple, list)):
        # supports HTTP AUTH
        obj = "{}:{}".format(*auth)
        b_string = obj.encode("utf8")
        qdata.auth_userpwd = strdup(b_string)
    elif auth is None:
        pass
    else:
        dl_queue_node_free(&qdata)
        raise Exception("Unsupported auth for the moment")


    dl_ensure_init()
    if priority:
        queue_append_first(&ctx_download, qdata)
    else:
        queue_append_last(&ctx_download, qdata)
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
        CurlyResult result
        dl_queue_data *data
        bytes b_data = None
        object callback
        curl_slist *item

    while SDL_AtomicDecRef(&dl_ready_to_process) == 0:
        data = <dl_queue_data *>queue_pop_first(&ctx_result)
        if data == NULL:
            break

        callback = <object><void *>data.callback
        if not callback:
            continue

        result = CurlyResult()
        result._data = data
        callback(result)


def install():
    """Install a scheduler in the Kivy clock to call :func:`process`
    """
    uninstall()
    Clock.schedule_interval(process, 1 / 120.)


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


def configure(num_threads=4, req_verify_peer=0):
    """Configure the library before any invocation
    Any call after the using `request`, `download_image` or `get_info`
    won't use the information and raise an exception.

    :Parameters:
        `num_threads`: int
            Number of background threads to use for downloading
            Defaults to 4
        `req_verify_peer`: bool
            If True, it will verify SSL peers.
            But since we have an issue with cacert.pem on Android, it is
            disabled by default right now. (it's bad)
            Defaults to False
    """
    if dl_running:
        raise Exception("Library already running, cannot reconfigure.")
    global config_num_threads, config_req_verify_peer
    config_num_threads = num_threads
    config_req_verify_peer = 1 if req_verify_peer else 0
