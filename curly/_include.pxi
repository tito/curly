cdef extern from * nogil:
    bool __sync_bool_compare_and_swap(void **ptr, void *oldval, void *newval)
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

    enum CURLSHcode:
        CURLSHE_OK
    struct CURL:
        pass
    struct curl_slist:
        curl_slist *next
        char *data

    int CURLcode
    CURL *curl_easy_init()
    CURLSHcode curl_easy_setopt(CURL *, CURLoption, ...)
    CURLSHcode curl_easy_cleanup(CURL *)
    CURLSHcode curl_easy_perform(CURL *)
    curl_slist *curl_slist_append(curl_slist *, char *)
    void curl_slist_free_all(curl_slist *)

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

    int SDL_AtomicGet(SDL_atomic_t *)
    int SDL_AtomicSet(SDL_atomic_t *, int v)
    int SDL_SemWait(SDL_sem *)
    int SDL_SemPost(SDL_sem *)
    SDL_sem *SDL_CreateSemaphore(int)
    void SDL_DestroySemaphore(SDL_sem *)

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
