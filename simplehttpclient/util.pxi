from cpython.bytes cimport PyBytes_FromStringAndSize
from cython.operator cimport dereference as deref, preincrement as inc
from opentracing cimport Value as NativeValue, \
                         Dictionary as NativeDictionary, \
                         LogRecord as NativeLogRecord, \
                         Values as NativeValues, \
                         SpanReferenceType, \
                         ChildOfRef, \
                         FollowsFromRef, \
                         recursive_wrapper
from opentracing import child_of, follows_from
from w3copentracing cimport SpanContext as NativeSpanContext
from w3copentracing import SpanContext
from libcpp cimport bool
from libcpp.string cimport string
from libcpp.map cimport map
from libcpp.unordered_map cimport unordered_map
from libcpp.vector cimport vector
from libc.stdint cimport uint64_t, int64_t


cdef bytes_to_mem(bytes src, char* dst, int size):
    assert(len(src) >= size)
    for i in range(size):
        dst[i] = src[i]

cdef bytes mem_to_bytes(char* src, int size):
    return PyBytes_FromStringAndSize(src,size)

cdef baggage_to_native(dict baggage, map[string,string]& native):
    if baggage is not None:
        for k,v in baggage.items():
            native[k.encode("ascii")] = v.encode("ascii")

cdef object native_to_baggage(const map[string,string]& native):
    """Convert baggage to a Python Dict[str,str]."""
    out = dict()
    cdef map[string,string].const_iterator it = native.const_begin()
    while it != native.const_end():
        out[bytes(deref(it).first).decode("ascii")] = bytes(deref(it).second).decode("ascii")
        inc(it)
    return out

ctypedef const char * const_char_ptr

cdef object native_value_to_object(const NativeValue& native):
    """Recursively convert a value to a Python object."""
    cdef const unordered_map[string, NativeValue]* ndict
    cdef unordered_map[string, NativeValue].const_iterator ndict_it
    cdef const vector[NativeValue]* nlist
    cdef vector[NativeValue].const_iterator nlist_it
    if native.is_type[bool]():
        return native.get[bool]()
    elif native.is_type[double]():
        return native.get[double]()
    elif native.is_type[int64_t]():
        return native.get[int64_t]()
    elif native.is_type[uint64_t]():
        return native.get[uint64_t]()
    elif native.is_type[string]():
        return bytes(native.get[string]()).decode("ascii")
    elif native.is_type[const_char_ptr]():
        return bytes(native.get[const_char_ptr]()).decode("ascii")
    elif native.is_type[recursive_wrapper[NativeDictionary]]():
        out_dict = {}
        ndict = &native.get[recursive_wrapper[NativeDictionary]]().get()
        ndict_it = deref(ndict).const_begin()
        while ndict_it != deref(ndict).const_end():
            out_dict[bytes(deref(ndict_it).first).decode("ascii")] = native_value_to_object(deref(ndict_it).second)
            inc(ndict_it)
        return out_dict
    elif native.is_type[recursive_wrapper[NativeValues]]():
        out_list = []
        nlist = &native.get[recursive_wrapper[NativeValues]]().get()
        nlist_it = deref(nlist).const_begin()
        while nlist_it != deref(nlist).const_end():
            out_list.append(native_value_to_object(deref(nlist_it)))
            inc(nlist_it)
        return out_list
    return None # unknown or nullptr_t

cdef object native_to_tags(const map[string,NativeValue]& native):
    """Convert tags to a Python Dict[str, object]."""
    out = dict()
    cdef map[string,NativeValue].const_iterator it = native.const_begin()
    while it != native.const_end():
        out[bytes(deref(it).first).decode("ascii")] = native_value_to_object(deref(it).second)
        inc(it)
    if len(out):
        return out
    return None

cdef object native_to_references(const vector[pair[SpanReferenceType,NativeSpanContext]]& native):
    cdef vector[pair[SpanReferenceType,NativeSpanContext]].const_iterator it
    out = list()
    it = native.const_begin()
    while it != native.const_end():
        if <int>deref(it).first == <int>ChildOfRef:
            out.append(child_of(native_to_span_context(deref(it).second)))
        elif <int>deref(it).first == <int>FollowsFromRef:
            out.append(follows_from(native_to_span_context(deref(it).second)))
        inc(it)
    if len(out):
        return out
    return None

cdef object native_to_logs(const vector[NativeLogRecord]& native):
    cdef vector[NativeLogRecord].const_iterator it
    out = list()
    # TODO: handle logs
    # it = native.const_begin()
    # while it != native.const_end():
    #     if <int>deref(it).first == <int>ChildOfRef:
    #         out.append(child_of(native_to_span_context(deref(it).second)))
    #     elif <int>deref(it).first == <int>FollowsFromRef:
    #         out.append(follows_from(native_to_span_context(deref(it).second)))
    #     inc(it)
    # if len(out):
    #     return out
    return None

cdef span_context_to_native(context: SpanContext, NativeSpanContext& native):
    assert(len(context.trace_id) == native.trace_id.size())
    assert(len(context.span_id) == native.span_id.size())
    bytes_to_mem(context.trace_id, <char*>native.trace_id.data(), native.trace_id.size())
    bytes_to_mem(context.span_id, <char*>native.span_id.data(), native.span_id.size())
    native.sampled = context.sampled
    baggage_to_native(context.baggage, native.baggage)

cdef object native_to_span_context(const NativeSpanContext& native):
    return SpanContext(
        trace_id=mem_to_bytes(<char*>native.trace_id.data(), native.trace_id.size()),
        span_id=mem_to_bytes(<char*>native.span_id.data(), native.span_id.size()),
        sampled=native.sampled,
        baggage=native_to_baggage(native.baggage)
    )

