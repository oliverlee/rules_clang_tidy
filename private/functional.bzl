"""Module containing functional-style utilities."""

def _map(f, iterable):
    return [f(x) for x in iterable]

def _filter(p, iterable):
    r = []
    for value in iterable:
        if p(value):
            r.append(value)
    return r

def _left_fold(bop, head, *tail):
    # https://github.com/bazelbuild/starlark/issues/97
    # https://github.com/bazelbuild/bazel/issues/9163
    tail = tuple(tail)
    for i in range(len(tail)):
        head = bop(head, tail[i])
    return head

def _reduce(bop, *args):
    return _left_fold(bop, *args)

def _add(head, *tail):
    return _reduce(lambda x, y: x + y, head, *tail)

def _bind_front(f, *front):
    return lambda *back: f(*(tuple(front) + tuple(back)))

def _empty(x):
    return not len(x)

functional = struct(
    map = _map,
    filter = _filter,
    reduce = _reduce,
    left_fold = _left_fold,
    add = _add,
    bind_front = _bind_front,
    empty = _empty,
)
