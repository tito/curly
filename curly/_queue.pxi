ctypedef struct dl_queue_data:
    # http request
    int status_code
    char *url
    char *data
    int size
    void *callback
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


cdef void queue_init(queue_ctx *ctx) nogil:
    cdef queue_node *node = <queue_node *>calloc(1, sizeof(queue_node))
    memset(ctx, 0, sizeof(queue_ctx))
    ctx.head = ctx.tail = node


cdef void queue_clean(queue_ctx *ctx) nogil:
    cdef queue_node *node
    cdef queue_node *tmp
    if ctx.tail != NULL or ctx.head != NULL:
        node = ctx.head
        while node != ctx.tail:
            tmp = node.next
            free(node)
            node = tmp
        free(ctx.head)
        memset(ctx, 0, sizeof(queue_ctx))


cdef int queue_append_last(queue_ctx *ctx, void *data) nogil:
    cdef queue_node *p
    cdef queue_node *node = <queue_node *>calloc(1, sizeof(queue_node))
    if node == NULL:
        return -1

    node.data = data
    while True:
        p = ctx.tail
        if __sync_bool_compare_and_swap(<void **>&ctx.tail, p, node):
            p.next = node
            break

    return 0


cdef void *queue_pop_first(queue_ctx *ctx) nogil:
    cdef void *ret = NULL
    cdef queue_node *p
    while True:
        p = ctx.head
        if p == NULL:
            continue
        if not __sync_bool_compare_and_swap(<void **>&ctx.head, p, NULL):
            continue
        break
    if p.next == NULL:
        ctx.head = p
        return NULL
    ret = p.next.data
    ctx.head = p.next
    free(p)
    return ret


cdef void dl_queue_node_free(dl_queue_data **data):
    if data is NULL:
        return
    free(data[0].url)
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
    free(data[0])
