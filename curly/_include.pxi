cdef extern from * nogil:
    ctypedef unsigned int size_t


cdef extern from "curl/curl.h" nogil:
    enum CURLoption:
        CURLOPT_URL
        CURLOPT_VERBOSE
        CURLOPT_WRITEFUNCTION
        CURLOPT_WRITEDATA
        CURLOPT_FOLLOWLOCATION
        CURLOPT_HTTPHEADER
        CURLOPT_HEADERFUNCTION
        CURLOPT_HEADERDATA
        CURLOPT_CUSTOMREQUEST
        CURLOPT_HTTPPOST
        CURLOPT_HTTPGET
        CURLOPT_POSTFIELDS
        CURLOPT_HTTPAUTH
        CURLOPT_USERPWD
        CURLOPT_POSTFIELDSIZE
        CURLOPT_SSL_VERIFYPEER
        CURLAUTH_ANY

    enum CURLversion:
        CURLVERSION_NOW

    enum CURLSHcode:
        CURLSHE_OK

    struct CURL:
        pass
    struct curl_slist:
        curl_slist *next
        char *data

    ctypedef struct curl_version_info_data:
        CURLversion age  # see description below

        # when 'age' is 0 or higher, the members below also exist:
        const char *version  # human readable string
        unsigned int version_num  # numeric representation
        const char *host  # human readable string
        int features  # bitmask, see below
        char *ssl_version  # human readable string
        long ssl_version_num  # not used, always zero
        const char *libz_version  # human readable string
        const char * const *protocols  # protocols

        # when 'age' is 1 or higher, the members below also exist:
        const char *ares  # human readable string
        int ares_num  # number

        # when 'age' is 2 or higher, the member below also exists:
        const char *libidn  # human readable string

        # when 'age' is 3 or higher (7.16.1 or later), the members below also exist
        int iconv_ver_num  # '_libiconv_version' if iconv support enabled

        const char *libssh_version  # human readable string

        # when 'age' is 4 or higher (7.57.0 or later), the members below also exist
        unsigned int brotli_ver_num  # Numeric Brotli vers (MAJOR << 24) | (MINOR << 12) | PATCH
        const char *brotli_version  # human readable string.


    ctypedef int CURLcode
    int CURL_GLOBAL_ALL
    CURLcode curl_global_init(long flags)
    CURL *curl_easy_init()
    CURLSHcode curl_easy_setopt(CURL *, CURLoption, ...)
    CURLSHcode curl_easy_cleanup(CURL *)
    CURLSHcode curl_easy_perform(CURL *)
    curl_slist *curl_slist_append(curl_slist *, char *)
    void curl_slist_free_all(curl_slist *)
    curl_version_info_data *curl_version_info(CURLversion age)
    const char *curl_easy_strerror(int)

cdef extern from "SDL.h" nogil:
    ctypedef unsigned char Uint8
    ctypedef unsigned long Uint32
    ctypedef signed long Sint32
    ctypedef unsigned long long Uint64
    ctypedef signed long long Sint64
    ctypedef signed short Sint16
    ctypedef unsigned short Uint16

    ctypedef enum:
        SDL_PIXELFORMAT_ARGB8888
        SDL_PIXELFORMAT_RGBA8888
        SDL_PIXELFORMAT_RGB888
        SDL_PIXELFORMAT_ABGR8888
        SDL_PIXELFORMAT_BGR888

    ctypedef struct SDL_Thread
    ctypedef struct SDL_mutex
    ctypedef int SDL_atomic_t
    ctypedef int SDL_bool
    ctypedef struct SDL_sem
    cdef struct SDL_BlitMap

    cdef struct SDL_Color:
        Uint8 r
        Uint8 g
        Uint8 b
        Uint8 a

    cdef struct SDL_Rect:
        int x, y
        int w, h

    cdef struct SDL_Palette:
        int ncolors
        SDL_Color *colors
        Uint32 version
        int refcount

    cdef struct SDL_PixelFormat:
        Uint32 format
        SDL_Palette *palette
        Uint8 BitsPerPixel
        Uint8 BytesPerPixel
        Uint8 padding[2]
        Uint32 Rmask
        Uint32 Gmask
        Uint32 Bmask
        Uint32 Amask
        Uint8 Rloss
        Uint8 Gloss
        Uint8 Bloss
        Uint8 Aloss
        Uint8 Rshift
        Uint8 Gshift
        Uint8 Bshift
        Uint8 Ashift
        int refcount
        SDL_PixelFormat *next

    cdef struct SDL_Surface:
        Uint32 flags
        SDL_PixelFormat *format
        int w, h
        int pitch
        void *pixels
        void *userdata
        int locked
        void *lock_data
        SDL_Rect clip_rect
        SDL_BlitMap *map
        int refcount

    cdef struct SDL_RWops:
        long (* seek) (SDL_RWops * context, long offset,int whence)
        size_t(* read) ( SDL_RWops * context, void *ptr, size_t size, size_t maxnum)
        size_t(* write) (SDL_RWops * context, void *ptr,size_t size, size_t num)
        int (* close) (SDL_RWops * context)

    ctypedef long SDL_threadID
    ctypedef int (*SDL_ThreadFunction)(void *data)
    SDL_Thread *SDL_CreateThread(SDL_ThreadFunction fn, char *name, void *data)
    void SDL_DetachThread(SDL_Thread *thread)
    SDL_threadID SDL_GetThreadID(SDL_Thread *thread)
    void SDL_WaitThread(SDL_Thread *thread, int *status)

    SDL_bool SDL_AtomicCASPtr(void** a,
                              void*  oldval,
                              void*  newval)
    int SDL_AtomicGet(SDL_atomic_t *)
    int SDL_AtomicSet(SDL_atomic_t *, int v)
    void SDL_AtomicIncRef(SDL_atomic_t* a)
    SDL_bool SDL_AtomicDecRef(SDL_atomic_t* a)
    int SDL_SemWait(SDL_sem *)
    int SDL_SemPost(SDL_sem *)
    SDL_sem *SDL_CreateSemaphore(int)
    void SDL_DestroySemaphore(SDL_sem *)

    SDL_mutex* SDL_CreateMutex()
    void SDL_DestroyMutex(SDL_mutex* mutex)
    int SDL_LockMutex(SDL_mutex* mutex)
    int SDL_TryLockMutex(SDL_mutex* mutex)
    int SDL_UnlockMutex(SDL_mutex* mutex)


    cdef SDL_RWops * SDL_RWFromFile(char *file, char *mode)
    cdef SDL_RWops * SDL_RWFromMem(void *mem, int size)
    cdef SDL_RWops * SDL_RWFromConstMem(void *mem, int size)

    cdef SDL_Surface* SDL_ConvertSurface(SDL_Surface* src, SDL_PixelFormat* fmt, Uint32 flags)
    cdef SDL_Surface* SDL_ConvertSurfaceFormat(SDL_Surface* src, Uint32
            pixel_format, Uint32 flags)
    cdef void SDL_FreeSurface(SDL_Surface * surface)

cdef extern from "SDL_image.h" nogil:
    ctypedef enum IMG_InitFlags:
        IMG_INIT_JPG
        IMG_INIT_PNG
        IMG_INIT_TIF
        IMG_INIT_WEBP
    cdef int IMG_Init(IMG_InitFlags flags)
    cdef char *IMG_GetError()
    cdef SDL_Surface *IMG_Load(char *file)
    cdef SDL_Surface *IMG_Load_RW(SDL_RWops *src, int freesrc)
    cdef SDL_Surface *IMG_LoadTyped_RW(SDL_RWops *src, int freesrc, char *type)
    cdef int *IMG_SavePNG(SDL_Surface *src, char *file)
