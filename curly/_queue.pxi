ctypedef struct dl_queue_data:
    # curl perform
    int curl_ret

    # http request
    char *url
    char *data
    int size
    void *callback
    char *postdata
    char *method
    char *auth_userpwd
    curl_slist *headers
    curl_slist *resp_headers

    # image loading if wanted
    int preload_image
    SDL_Surface *image
    char *image_error

    # caching
    char *cache_fn


ctypedef struct queue_node:
    void *data
    queue_node *next


ctypedef struct queue_ctx:
    queue_node *head
    queue_node *tail
    SDL_mutex *mutex


cdef void queue_init(queue_ctx *ctx) nogil:
    memset(ctx, 0, sizeof(queue_ctx))
    ctx.mutex = SDL_CreateMutex()
    ctx.head = ctx.tail = NULL


# FIXME: not used right now, but we should clean the memory
# correctly at the end
# cdef void queue_clean(queue_ctx *ctx) nogil:
#     cdef queue_node *node
#     cdef queue_node *tmp
#     if ctx.tail != NULL or ctx.head != NULL:
#         node = ctx.head
#         while node != ctx.tail:
#             tmp = node.next
#             free(node)
#             node = tmp
#         free(ctx.head)
#     SDL_DestroyMutex(ctx.mutex)
#     memset(ctx, 0, sizeof(queue_ctx))


cdef int queue_append_last(queue_ctx *ctx, void *data) nogil:
    cdef queue_node *p
    cdef queue_node *node = <queue_node *>calloc(1, sizeof(queue_node))
    if node == NULL:
        return -1

    node.data = data
    if SDL_LockMutex(ctx.mutex) != 0:
        return -1

    if ctx.tail != NULL:
        ctx.tail.next = node
        ctx.tail = node
    else:
        ctx.head = ctx.tail = node

    SDL_UnlockMutex(ctx.mutex)
    return 0


cdef int queue_append_first(queue_ctx *ctx, void *data) nogil:
    cdef queue_node *p
    cdef queue_node *node = <queue_node *>calloc(1, sizeof(queue_node))
    if node == NULL:
        return -1

    node.data = data
    if SDL_LockMutex(ctx.mutex) != 0:
        return -1

    if ctx.head != NULL:
        node.next = ctx.head
        ctx.head = node
    else:
        ctx.head = ctx.tail = node

    SDL_UnlockMutex(ctx.mutex)
    return 0


cdef void *queue_pop_first(queue_ctx *ctx) nogil:
    cdef void *ret = NULL
    cdef queue_node *p = NULL

    if SDL_LockMutex(ctx.mutex) != 0:
        return NULL

    if ctx.head == NULL:
        SDL_UnlockMutex(ctx.mutex)
        return NULL

    if ctx.head != NULL:
        p = ctx.head
        ctx.head = ctx.head.next
    if ctx.head == NULL:
        ctx.tail = NULL
    SDL_UnlockMutex(ctx.mutex)

    if p == NULL:
        return NULL

    ret = p.data
    free(p)
    return ret


cdef void dl_queue_node_free(dl_queue_data **data):
    if data is NULL:
        return
    if data[0] is NULL:
        return
    if data[0].url != NULL:
        free(data[0].url)
    if data[0].method != NULL:
        free(data[0].method)
    if data[0].cache_fn != NULL:
        free(data[0].cache_fn)
    if data[0].data != NULL:
        free(data[0].data)
    if data[0].headers != NULL:
        curl_slist_free_all(data[0].headers)
    if data[0].resp_headers != NULL:
        curl_slist_free_all(data[0].resp_headers)
    if data[0].callback != NULL:
        Py_XDECREF(<PyObject *>data[0].callback)
    if data[0].auth_userpwd != NULL:
        free(data[0].auth_userpwd)
    if data[0].postdata != NULL:
        free(data[0].postdata)
    if data[0].image != NULL:
        SDL_FreeSurface(data[0].image)
    free(data[0])
