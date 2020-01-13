from cpython.ref cimport PyObject
from cython.operator cimport dereference as deref, preincrement as inc
from libcpp.string cimport string
from libcpp.vector cimport vector
from libcpp.pair cimport pair
from libcpp.optional cimport optional
from libcpp.memory cimport shared_ptr, make_shared
from simplehttp cimport Request as NativeRequest, \
                        Response as NativeResponse, \
                        SimpleHttpClient as NativeSimpleHttpClient, \
                        SimpleHttpServer as NativeSimpleHttpServer
from request_handler cimport RequestHandler
from chrono_helper cimport time_point_as_double
from python_reference cimport PythonReference
from opentracing cimport Scope as NativeScope, \
                         Span as NativeOpenTracingSpan
from w3copentracing cimport SpanContext as NativeSpanContext
from otinterop cimport SpanCollectedData as NativeSpanCollectedData, \
                       Span as NativeSpan, \
                       Tracer as NativeTracer, dynamic_cast_span_ptr

from typing import Callable
from .types import Request, Response
from opentracing import global_tracer
from w3copentracing import Span
from contextlib import contextmanager

include "util.pxi"

# Load Tracing
cdef shared_ptr[NativeTracer] tracer
tracer = make_shared[NativeTracer]()
deref(tracer).InitGlobal(tracer)

cdef observe_spans():
    """Consume tracing events and propagate them in Python"""
    cdef vector[shared_ptr[NativeSpanCollectedData]] spans_data
    native_span_datas = deref(tracer).consume_tracked_spans()
    cdef vector[shared_ptr[NativeSpanCollectedData]].iterator it = native_span_datas.begin()
    while it != native_span_datas.end():
        process_span_data(deref(deref(it)))
        inc(it)

cdef process_span_data(NativeSpanCollectedData& data):
    if not data.python_span.has_value():
        # First time we've seen the span. Need to create it:
        context = native_to_span_context(data.context)
        operation_name = data.operation_name.value() if data.operation_name.has_value() else None

        # No start_time should not happen and would be populated interop tracer
        start_time = time_point_as_double(data.start_time.value()) if data.start_time.has_value() else None
        assert(start_time)

        references = native_to_references(data.references)
        tags = native_to_tags(data.tags)

        span = global_tracer().start_span(operation_name=operation_name,
                                          child_of=None,
                                          references=references,
                                          tags=tags,
                                          start_time=start_time,
                                          ignore_active_span=True)
        span.context = context
        data.python_span = PythonReference(<PyObject*>span)

        # Reset consumed fields
        data.operation_name.reset()
        data.start_time.reset()
        data.references.clear()
        data.tags.clear()
    else:
        span = <object>data.python_span.value().get()

    tags = native_to_tags(data.tags)
    if tags is not None:
        for key, value in tags.items():
            span.set_tag(key, value)
        data.tags.clear()

    logs = native_to_logs(data.logs)
    if logs is not None:
        for key_values, timestamp in logs:
            span.log_kv(key_values, timestamp)
        data.logs.clear()

    if data.finish_time.has_value():
        finish_time = time_point_as_double(data.finish_time.value())
        span.finish(finish_time)

cdef class SimpleHttpClient:
    cdef optional[NativeSimpleHttpClient] client

    def __init__(self, host: str, port: int):
        self.client.emplace(<string>host.encode('ascii'), <unsigned short>port)

    def make_request(self, request: Request) -> Response:
        assert(self.client.has_value())

        cdef NativeSpanContext native_context
        cdef shared_ptr[NativeOpenTracingSpan] native_span_ptr
        cdef optional[NativeScope] native_scope
        scope = global_tracer().scope_manager.active

        # Reinstantiate the active scope in C++ if exists in python
        if scope is not None and isinstance(scope.span, Span):
            span_context_to_native(scope.span.context, native_context)
            native_span_ptr = shared_ptr[NativeOpenTracingSpan](deref(tracer).StartProxySpan(
                native_context, PythonReference(<PyObject*>scope.span)))
            native_scope.emplace(deref(tracer).ScopeManager().Activate(native_span_ptr))
            # Scope lives until and of call

        # Convert the request
        cdef NativeRequest nreq
        cdef NativeResponse nresp
        nreq.path = request.path.encode('ascii')
        if request.data is not None:
            nreq.data = string(bytes(request.data))

        # Make the request
        with nogil:
            nresp = self.client.value().make_request(nreq)
            native_scope.reset()
            native_span_ptr.reset()

        # Handle tracing data
        observe_spans()

        # Convert the response
        return Response(nresp.code, nresp.data.value() if nresp.data.has_value() else None)

    def __del__(self):
        self.client.reset()
