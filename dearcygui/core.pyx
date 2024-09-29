#!python
#cython: language_level=3
#cython: boundscheck=False
#cython: wraparound=False
#cython: nonecheck=False
#cython: embedsignature=False
#cython: cdivision=True
#cython: cdivision_warnings=False
#cython: always_allow_keywords=False
#cython: profile=False
#cython: infer_types=False
#cython: initializedcheck=False
#cython: c_line_in_traceback=False
#distutils: language = c++

from libcpp cimport bool
import traceback

cimport cython
cimport cython.view
from cython.operator cimport dereference
from cpython.ref cimport PyObject

# This file is the only one that is linked to the C++ code
# Thus it is the only one allowed to make calls to it

from dearcygui.wrapper cimport *
from dearcygui.backends.backend cimport *
# We use unique_lock rather than lock_guard as
# the latter doesn't support nullary constructor
# which causes trouble to cython
from dearcygui.wrapper.mutex cimport recursive_mutex, unique_lock, defer_lock_t

from concurrent.futures import ThreadPoolExecutor
from libcpp.algorithm cimport swap
from libcpp.cmath cimport atan, sin, cos, trunc
from libcpp.vector cimport vector
from libc.math cimport M_PI, INFINITY
cimport dearcygui.backends.time as ctime

import numpy as np
cimport numpy as cnp
cnp.import_array()

import scipy
import scipy.spatial
import threading


cdef void internal_resize_callback(void *object, int a, int b) noexcept nogil:
    with gil:
        try:
            (<Viewport>object).__on_resize(a, b)
        except Exception as e:
            print("An error occured in the viewport resize callback", traceback.format_exc())

cdef void internal_close_callback(void *object) noexcept nogil:
    with gil:
        try:
            (<Viewport>object).__on_close()
        except Exception as e:
            print("An error occured in the viewport close callback", traceback.format_exc())

cdef void internal_render_callback(void *object) noexcept nogil:
    (<Viewport>object).__render()

# The no gc clear flag enforces that in case
# of no-reference cycle detected, the Context is freed last.
# The cycle is due to Context referencing Viewport
# and vice-versa

cdef class Context:
    """
    Main class managing the DearCyGui items and imgui context.
    There is exactly one viewport per context.

    Items are assigned an uuid and eventually a user tag.
    indexing the context with the uuid or the tag returns
    the object associated.
    """
    def __init__(self):
        self.on_close_callback = None
        self.on_frame_callbacks = None
        self.queue = ThreadPoolExecutor(max_workers=1)

    def __cinit__(self):
        self.next_uuid.store(21)
        self.waitOneFrame = False
        self.started = False
        self.uuid_to_tag = dict()
        self.tag_to_uuid = dict()
        self.threadlocal_data = threading.local()
        self.viewport = Viewport(self)
        self.resetTheme = False
        imgui.IMGUI_CHECKVERSION()
        self.imgui_context = imgui.CreateContext()
        self.implot_context = implot.CreateContext()
        self.imnodes_context = imnodes.CreateContext()
        #mvToolManager::GetFontManager()._dirty = true;

    def __dealloc__(self):
        self.started = True
        if self.imnodes_context != NULL:
            imnodes.DestroyContext(self.imnodes_context)
        if self.implot_context != NULL:
            implot.DestroyContext(self.implot_context)
        if self.imgui_context != NULL:
            imgui.DestroyContext(self.imgui_context)

    def __del__(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if self.on_close_callback is not None:
            self.started = True
            self.queue_callback_noarg(self.on_close_callback, self)
            self.started = False

        #mvToolManager::Reset()
        #ClearItemRegistry(*GContext->itemRegistry)
        if self.queue is not None:
            self.queue.shutdown(wait=True)

    cdef void queue_callback_noarg(self, Callback callback, baseItem parent_item) noexcept nogil:
        if callback is None:
            return
        with gil:
            try:
                self.queue.submit(callback, parent_item, None, parent_item._user_data)
            except Exception as e:
                print(traceback.format_exc())

    cdef void queue_callback_arg1obj(self, Callback callback, baseItem parent_item, baseItem arg1) noexcept nogil:
        if callback is None:
            return
        with gil:
            try:
                self.queue.submit(callback, parent_item, arg1, parent_item._user_data)
            except Exception as e:
                print(traceback.format_exc())

    cdef void queue_callback_arg1int(self, Callback callback, baseItem parent_item, int arg1) noexcept nogil:
        if callback is None:
            return
        with gil:
            try:
                self.queue.submit(callback, parent_item, arg1, parent_item._user_data)
            except Exception as e:
                print(traceback.format_exc())

    cdef void queue_callback_arg1float(self, Callback callback, baseItem parent_item, float arg1) noexcept nogil:
        if callback is None:
            return
        with gil:
            try:
                self.queue.submit(callback, parent_item, arg1, parent_item._user_data)
            except Exception as e:
                print(traceback.format_exc())

    cdef void queue_callback_arg1value(self, Callback callback, baseItem parent_item, SharedValue arg1) noexcept nogil:
        if callback is None:
            return
        with gil:
            try:
                self.queue.submit(callback, parent_item, arg1.value, parent_item._user_data)
            except Exception as e:
                print(traceback.format_exc())


    cdef void queue_callback_arg1int1float(self, Callback callback, baseItem parent_item, int arg1, float arg2) noexcept nogil:
        if callback is None:
            return
        with gil:
            try:
                self.queue.submit(callback, parent_item, (arg1, arg2), parent_item._user_data)
            except Exception as e:
                print(traceback.format_exc())

    cdef void queue_callback_arg2float(self, Callback callback, baseItem parent_item, float arg1, float arg2) noexcept nogil:
        if callback is None:
            return
        with gil:
            try:
                self.queue.submit(callback, parent_item, (arg1, arg2), parent_item._user_data)
            except Exception as e:
                print(traceback.format_exc())

    cdef void queue_callback_arg1int2float(self, Callback callback, baseItem parent_item, int arg1, float arg2, float arg3) noexcept nogil:
        if callback is None:
            return
        with gil:
            try:
                self.queue.submit(callback, parent_item, (arg1, arg2, arg3), parent_item._user_data)
            except Exception as e:
                print(traceback.format_exc())

    cdef void queue_callback_arg4int(self, Callback callback, baseItem parent_item, int arg1, int arg2, int arg3, int arg4) noexcept nogil:
        if callback is None:
            return
        with gil:
            try:
                self.queue.submit(callback, parent_item, (arg1, arg2, arg3, arg4), parent_item._user_data)
            except Exception as e:
                print(traceback.format_exc())

    cdef void queue_callback_arg3long1int(self, Callback callback, baseItem parent_item, long long arg1, long long arg2, long long arg3, int arg4) noexcept nogil:
        if callback is None:
            return
        with gil:
            try:
                self.queue.submit(callback, parent_item, (arg1, arg2, arg3, arg4), parent_item._user_data)
            except Exception as e:
                print(traceback.format_exc())

    cdef void register_item(self, baseItem o, long long uuid):
        """ Stores weak references to objects.
        
        Each object holds a reference on the context, and thus will be
        freed after calling unregister_item. If gc makes it so the context
        is collected first, that's ok as we don't use the content of the
        map anymore.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.items[uuid] = <PyObject*>o
        self.threadlocal_data.last_item_uuid = uuid
        if o.can_have_drawing_child or \
           o.can_have_handler_child or \
           o.can_have_menubar_child or \
           o.can_have_payload_child or \
           o.can_have_tab_child or \
           o.can_have_theme_child or \
           o.can_have_widget_child or \
           o.can_have_window_child:
            self.threadlocal_data.last_container_uuid = uuid

    cdef void register_item_with_tag(self, baseItem o, long long uuid, str tag):
        """ Stores weak references to objects.
        
        Each object holds a reference on the context, and thus will be
        freed after calling unregister_item. If gc makes it so the context
        is collected first, that's ok as we don't use the content of the
        map anymore.

        Using a tag enables the user to name his objects and reference them by
        names.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if tag in self.tag_to_uuid:
            raise KeyError(f"Tag {tag} already in use")
        self.items[uuid] = <PyObject*>o
        self.uuid_to_tag[uuid] = tag
        self.tag_to_uuid[tag] = uuid
        self.threadlocal_data.last_item_uuid = uuid
        if o.can_have_drawing_child or \
           o.can_have_handler_child or \
           o.can_have_menubar_child or \
           o.can_have_payload_child or \
           o.can_have_tab_child or \
           o.can_have_theme_child or \
           o.can_have_widget_child or \
           o.can_have_window_child:
            self.threadlocal_data.last_container_uuid = uuid

    cdef void unregister_item(self, long long uuid):
        """ Free weak reference """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.items.erase(uuid)
        if self.uuid_to_tag is None:
            # Can occur during gc collect at
            # the end of the program
            return
        if uuid in self.uuid_to_tag:
            tag = self.uuid_to_tag[uuid]
            del self.uuid_to_tag[uuid]
            del self.tag_to_uuid[tag]

    cdef baseItem get_registered_item_from_uuid(self, long long uuid):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef map[long long, PyObject *].iterator item = self.items.find(uuid)
        if item == self.items.end():
            return None
        cdef PyObject *o = dereference(item).second
        # Cython inserts a strong object reference when we convert
        # the pointer to an object
        return <baseItem>o

    cdef baseItem get_registered_item_from_tag(self, str tag):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef long long uuid = self.tag_to_uuid.get(tag, -1)
        if uuid == -1:
            # not found
            return None
        return self.get_registered_item_from_uuid(uuid)

    cdef void update_registered_item_tag(self, baseItem o, long long uuid, str tag):
        old_tag = self.uuid_to_tag.get(uuid, None)
        if old_tag == tag:
            return
        if tag in self.tag_to_uuid:
            raise KeyError(f"Tag {tag} already in use")
        if old_tag is not None:
            del self.tag_to_uuid[old_tag]
            del self.uuid_to_tag[uuid]
        if tag is not None:
            self.uuid_to_tag[uuid] = tag
            self.tag_to_uuid[tag] = uuid

    def __getitem__(self, key):
        """
        Retrieves the object associated to
        a tag or an uuid
        """
        if isinstance(key, baseItem) or isinstance(key, SharedValue):
            # TODO: register shared values
            # Useful for legacy call wrappers
            return key
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef long long uuid
        if isinstance(key, str):
            if key not in self.tag_to_uuid:
                raise KeyError(f"Item not found with index {key}.")
            uuid = self.tag_to_uuid[key]
        elif isinstance(key, int):
            uuid = key
        else:
            raise TypeError(f"{type(key)} is an invalid index type")
        item = self.get_registered_item_from_uuid(uuid)
        if item is None:
            raise KeyError(f"Item not found with index {key}.")
        return item

    cpdef void push_next_parent(self, baseItem next_parent):
        """
        Each time 'with' is used on an item, it is pushed
        to the list of potentialy parents to use if
        no parent (or before) is set when an item is created.
        If the list is empty, items are left unattached and
        can be attached later.

        In order to enable multiple threads from using
        the 'with' syntax, thread local storage is used,
        such that each thread has its own list.
        """
        # Use thread local storage such that multiple threads
        # can build items trees without conflicts.
        # Mutexes are not needed due to the thread locality
        cdef list parent_queue = getattr(self.threadlocal_data, 'parent_queue', [])
        parent_queue.append(next_parent)
        self.threadlocal_data.parent_queue = parent_queue

    cpdef void pop_next_parent(self):
        """
        Remove an item from the potential parent list.
        """
        cdef list parent_queue = getattr(self.threadlocal_data, 'parent_queue', [])
        if len(parent_queue) > 0:
            parent_queue.pop()

    cpdef object fetch_parent_queue_back(self):
        """
        Retrieve the last item from the potential parent list
        """
        cdef list parent_queue = getattr(self.threadlocal_data, 'parent_queue', [])
        if len(parent_queue) == 0:
            return None
        return parent_queue[len(parent_queue)-1]

    cpdef object fetch_parent_queue_front(self):
        """
        Retrieve the top item from the potential parent list
        """
        cdef list parent_queue = getattr(self.threadlocal_data, 'parent_queue', [])
        if len(parent_queue) == 0:
            return None
        return parent_queue[0]

    cpdef object fetch_last_created_item(self):
        """
        Return the last item created in this thread.
        Returns None if the last item created has been
        deleted.
        """
        cdef long long last_uuid = getattr(self.threadlocal_data, 'last_item_uuid', -1)
        return self.get_registered_item_from_uuid(last_uuid)

    cpdef object fetch_last_created_container(self):
        """
        Return the last item which can have children
        created in this thread.
        Returns None if the last such item has been
        deleted.
        """
        cdef long long last_uuid = getattr(self.threadlocal_data, 'last_container_uuid', -1)
        return self.get_registered_item_from_uuid(last_uuid)

    def initialize_viewport(self, **kwargs):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.viewport.initialize(width=kwargs["width"],
                                 height=kwargs["height"])
        self.viewport.configure(**kwargs)
        self.started = True

    def is_key_down(self, int key, int keymod=-1):
        """
        Is key being held.

        key is a key constant (see constants)
        keymod is a mask if keymod constants (ctrl, shift, alt, super)
        if keymod is negative, ignores any key modifiers.
        If non-negative, returns True only if the modifiers
        correspond as well as the key.
        """
        cdef unique_lock[recursive_mutex] m
        if key < 0 or <imgui.ImGuiKey>key >= imgui.ImGuiKey_NamedKey_END:
            raise ValueError("Invalid key")
        ensure_correct_imgui_context(self)
        lock_gil_friendly(m, self.imgui_mutex)
        if keymod >= 0 and (keymod & imgui.ImGuiMod_Mask_) != imgui.GetIO().KeyMods:
            return False
        return imgui.IsKeyDown(<imgui.ImGuiKey>key)

    def is_key_pressed(self, int key, int keymod=-1, bint repeat=True):
        """
        Was key pressed (went from !Down to Down)?
        
        if repeat=true, the pressed state is repeated
        if the user continue pressing the key.
        If keymod is non-negative, returns True only if the modifiers
        correspond as well as the key.

        """
        cdef unique_lock[recursive_mutex] m
        if key < 0 or <imgui.ImGuiKey>key >= imgui.ImGuiKey_NamedKey_END:
            raise ValueError("Invalid key")
        ensure_correct_imgui_context(self)
        lock_gil_friendly(m, self.imgui_mutex)
        if keymod >= 0 and (keymod & imgui.ImGuiMod_Mask_) != imgui.GetIO().KeyMods:
            return False
        return imgui.IsKeyPressed(<imgui.ImGuiKey>key, repeat)

    def is_key_released(self, int key, int keymod=-1):
        """
        Was key released (went from Down to !Down)?
        
        If keymod is non-negative, returns True also if the
        required modifiers are not pressed.
        """
        cdef unique_lock[recursive_mutex] m
        if key < 0 or <imgui.ImGuiKey>key >= imgui.ImGuiKey_NamedKey_END:
            raise ValueError("Invalid key")
        ensure_correct_imgui_context(self)
        lock_gil_friendly(m, self.imgui_mutex)
        if keymod >= 0 and (keymod & imgui.GetIO().KeyMods) != keymod:
            return True
        return imgui.IsKeyReleased(<imgui.ImGuiKey>key)

    def is_mouse_down(self, int button):
        """is mouse button held?"""
        cdef unique_lock[recursive_mutex] m
        if button < 0 or button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        ensure_correct_imgui_context(self)
        lock_gil_friendly(m, self.imgui_mutex)
        return imgui.IsMouseDown(button)

    def is_mouse_clicked(self, int button, bint repeat=False):
        """did mouse button clicked? (went from !Down to Down). Same as get_mouse_clicked_count() >= 1."""
        cdef unique_lock[recursive_mutex] m
        if button < 0 or button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        ensure_correct_imgui_context(self)
        lock_gil_friendly(m, self.imgui_mutex)
        return imgui.IsMouseClicked(button, repeat)

    def is_mouse_double_clicked(self, int button, bint repeat=False):
        """did mouse button double-clicked?. Same as get_mouse_clicked_count() == 2."""
        cdef unique_lock[recursive_mutex] m
        if button < 0 or button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        ensure_correct_imgui_context(self)
        lock_gil_friendly(m, self.imgui_mutex)
        return imgui.IsMouseDoubleClicked(button)

    def get_mouse_clicked_count(self, int button):
        """how many times a mouse button is clicked in a row"""
        cdef unique_lock[recursive_mutex] m
        if button < 0 or button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        ensure_correct_imgui_context(self)
        lock_gil_friendly(m, self.imgui_mutex)
        return imgui.GetMouseClickedCount(button)

    def is_mouse_released(self, int button):
        """did mouse button released? (went from Down to !Down)"""
        cdef unique_lock[recursive_mutex] m
        if button < 0 or button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        ensure_correct_imgui_context(self)
        lock_gil_friendly(m, self.imgui_mutex)
        return imgui.IsMouseReleased(button)

    def get_mouse_position(self):
        """Retrieves the mouse position (x, y). Raises KeyError if there is no mouse"""
        cdef unique_lock[recursive_mutex] m
        ensure_correct_imgui_context(self)
        lock_gil_friendly(m, self.imgui_mutex)
        cdef imgui.ImVec2 pos = imgui.GetMousePos()
        if not(imgui.IsMousePosValid(&pos)):
            raise KeyError("Cannot get mouse position: no mouse found")
        return (pos.x, pos.y)

    def is_mouse_dragging(self, int button, float lock_threshold=-1.):
        """is mouse dragging? (uses default distance threshold if lock_threshold < 0.0f"""
        cdef unique_lock[recursive_mutex] m
        if button < 0 or button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        ensure_correct_imgui_context(self)
        lock_gil_friendly(m, self.imgui_mutex)
        return imgui.IsMouseDragging(button, lock_threshold)

    def get_mouse_drag_delta(self, int button, float lock_threshold=-1.):
        """
        Return the delta (dx, dy) from the initial clicking position while the mouse button is pressed or was just released.
        
        This is locked and return 0.0f until the mouse moves past a distance threshold at least once
        (uses default distance if lock_threshold < 0.0f)"""
        cdef unique_lock[recursive_mutex] m
        if button < 0 or button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        ensure_correct_imgui_context(self)
        lock_gil_friendly(m, self.imgui_mutex)
        cdef imgui.ImVec2 delta =  imgui.GetMouseDragDelta(button, lock_threshold)
        return (delta.x, delta.y)

    def reset_mouse_drag_delta(self, int button, float lock_threshold=-1.):
        """Reset to 0 the drag delta for the target button"""
        cdef unique_lock[recursive_mutex] m
        if button < 0 or button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        ensure_correct_imgui_context(self)
        lock_gil_friendly(m, self.imgui_mutex)
        return imgui.ResetMouseDragDelta(button)

    @property
    def running(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.started

    @running.setter
    def running(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.started = value

    @property
    def clipboard(self):
        """Writable attribute: content of the clipboard"""
        cdef unique_lock[recursive_mutex] m
        if not(self.viewport.initialized):
            return ""
        ensure_correct_imgui_context(self)
        lock_gil_friendly(m, self.imgui_mutex)
        return str(imgui.GetClipboardText())

    @clipboard.setter
    def clipboard(self, str value):
        cdef string value_str = bytes(value, 'utf-8')
        cdef unique_lock[recursive_mutex] m
        if not(self.viewport.initialized):
            return
        ensure_correct_imgui_context(self)
        lock_gil_friendly(m, self.imgui_mutex)
        imgui.SetClipboardText(value_str.c_str())



cdef class baseItem:
    """
    Base class for all items (except shared values)

    To be rendered, an item must be in the child tree
    of the viewport (context.viewport).

    The parent of an item can be set with various ways:
    1) Using the parent attribute. item.parent = target_item
    2) Passing (parent=target_item) during item creation
    3) If the context manager is not empty ('with' on an item),
       and no parent is set (parent = None passed or nothing),
       the last item in 'with' is taken as parent. The context
       manager can be managed directly with context.push_next_parent()
       and context.pop_next_parent()
    4) if you set the previous_sibling or next_sibling attribute,
       the item will be inserted respectively after and before the
       respective items in the parent item children list. For legacy
       support, the 'before=target_item' attribute can be used during item creation,
       and is equivalent to item.next_sibling = target_item

    parent, previous_sibling and next_sibling are baseItem attributes
    and can be read at any time.
    It is possible to get the list of children of an item as well
    with the 'children' attribute: item.children.

    For ease of use, the items can be named for easy retrieval.
    The tag attribute is a user string that can be set at any
    moment and can be passed for parent/previous_sibling/next_sibling.
    The item associated with a tag can be retrieved with context[tag].
    Note that having a tag doesn't mean the item is referenced by the context.
    If an item is not in the subtree of the viewport, and is not referenced,
    it might get deleted.

    During rendering the children of each item are rendered in
    order from the first one to the last one.
    When an item is attached to a parent, it is by default inserted
    last, unless previous_sibling or next_sibling is used.

    previous_sibling and next_sibling enable to insert an item
    between elements.

    When parent, previous_sibling or next_sibling are set, the item
    is detached from any parent or sibling it had previously.

    An item can be manually detached from a parent
    by setting parent = None.

    Most items have restrictions for the parents and children it can
    have. In addition some items can have several children lists
    of incompatible types. These children list will be concatenated
    when reading item.children. In a given list are items of a similar
    type.

    Finally some items cannot be children of any item in the rendering
    tree. One such item is PlaceHolderParent, which can be parent
    of any item which can have a parent. PlaceHolderParent cannot
    be inserted in the rendering tree, but can be used to store items
    before their insertion in the rendering tree.
    Other such items are textures, themes, colormaps and fonts. Those
    items cannot be made children of items of the rendering tree, but
    can be bound to them. For example item.theme = theme_item will
    bind theme_item to item. It is possible to bind such an item to
    several items, and as long as one item reference them, they will
    not be deleted by the garbage collector.
    """
    def __init__(self, context, *args, **kwargs):
        self.configure(*args, **kwargs)

    def __cinit__(self, context, *args, **kwargs):
        if not(isinstance(context, Context)):
            raise ValueError("Provided context is not a valid Context instance")
        self.context = context
        self.external_lock = False
        self.uuid = self.context.next_uuid.fetch_add(1)
        self.context.register_item(self, self.uuid)
        self.can_have_widget_child = False
        self.can_have_drawing_child = False
        self.can_have_payload_child = False
        self.can_have_sibling = False
        self.element_child_category = -1

    def __dealloc__(self):
        if self.context is not None:
            self.context.unregister_item(self.uuid)

    def configure(self, **kwargs):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        # Legacy DPG support: automatic attachement
        should_attach = kwargs.pop("attach", None)
        cdef bint ignore_if_fail = False
        if should_attach is None:
            # None: default to False for items which
            # cannot be attached, True else
            if self.element_child_category == -1:
                should_attach = False
            else:
                should_attach = True
                # To avoid failing on items which cannot
                # be attached to the rendering tree but
                # can be attached to other items
                ignore_if_fail = True
        if self._parent is None and should_attach:
            before = kwargs.pop("before", None)
            parent = kwargs.pop("parent", None)
            if before is not None:
                # parent manually set. Do not ignore failure
                ignore_if_fail = False
                self.attach_before(before)
            else:
                if parent is None:
                    parent = self.context.fetch_parent_queue_back()
                else:
                    # parent manually set. Do not ignore failure
                    ignore_if_fail = False
                try:
                    if parent is not None:
                        self.attach_to_parent(parent)
                except Exception as e:
                    if not(ignore_if_fail):
                        raise(e)
        else:
            if "before" in kwargs:
                del kwargs["before"]
            if "parent" in kwargs:
                del kwargs["parent"]
        remaining = {}
        for (key, value) in kwargs.items():
            try:
                setattr(self, key, value)
            except AttributeError:
                remaining[key] = value
        if len(remaining) > 0:
            print("Unused configure parameters: ", remaining)
        return

    @property
    def user_data(self):
        """
        User data of any type.
        When a callback is called, the item user_data
        is passed as third argument.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._user_data

    @user_data.setter
    def user_data(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._user_data = value

    @property
    def uuid(self):
        """
        Readonly attribute: uuid is an unique identifier created
        by the context for the item.
        uuid can be used to access the object by name for parent=,
        previous_sibling=, next_sibling= arguments, but it is
        preferred to pass the objects directly. 
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return int(self.uuid)

    @property
    def tag(self):
        """
        Writable attribute: tag is an optional string that uniquely
        defines the object.

        If set (else it is set to None), tag can be used to access
        the object by name for parent=,
        previous_sibling=, next_sibling= arguments.

        The tag can be set at any time, but it must be unique.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.context.get_registered_item_from_uuid(self.uuid)

    @tag.setter
    def tag(self, str tag):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.context.update_registered_item_tag(self, self.uuid, tag)

    @property
    def parent(self):
        """
        Writable attribute: parent of the item in the rendering tree.

        Rendering starts from the viewport. Then recursively each child
        is rendered from the first to the last, and each child renders
        their subtree.

        Only an item inserted in the rendering tree is rendered.
        An item that is not in the rendering tree can have children.
        Thus it is possible to build and configure various items, and
        attach them to the tree in a second phase.

        The children hold a reference to their parent, and the parent
        holds a reference to its children. Thus to be release memory
        held by an item, two options are possible:
        . Remove the item from the tree, remove all your references.
          If the item has children or siblings, the item will not be
          released until Python's garbage collection detects a
          circular reference.
        . Use delete_item to remove the item from the tree, and remove
          all the internal references inside the item structure and
          the item's children, thus allowing them to be removed from
          memory as soon as the user doesn't hold a reference on them.

        Note the viewport is referenced by the context.

        If you set this attribute, the item will be inserted at the last
        position of the children of the parent (regardless whether this
        item is already a child of the parent).
        If you set None, the item will be removed from its parent's children
        list.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._parent

    @parent.setter
    def parent(self, value):
        # It is important to not lock the mutex before the call
        if value is None:
            self.detach_item()
            return
        self.attach_to_parent(value)

    @property
    def previous_sibling(self):
        """
        Writable attribute: child of the parent of the item that
        is rendered just before this item.

        It is not possible to have siblings if you have no parent,
        thus if you intend to attach together items outside the
        rendering tree, there must be a toplevel parent item.

        If you write to this attribute, the item will be moved
        to be inserted just after the target item.
        In case of failure, the item remains in a detached state.

        Note that a parent can have several child queues, and thus
        child elements are not guaranteed to be siblings of each other.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._prev_sibling

    @previous_sibling.setter
    def previous_sibling(self, baseItem target not None):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, target.mutex)
        # Convert into an attach_before or attach_to_parent
        next_sibling = target._next_sibling
        target_parent = target._parent
        m.unlock()
        # It is important to not lock the mutex before the call
        if next_sibling is None:
            if target_parent is not None:
                self.attach_to_parent(target_parent)
            else:
                raise ValueError("Cannot bind sibling if no parent")
        self.attach_before(next_sibling)

    @property
    def next_sibling(self):
        """
        Writable attribute: child of the parent of the item that
        is rendered just after this item.

        It is not possible to have siblings if you have no parent,
        thus if you intend to attach together items outside the
        rendering tree, there must be a toplevel parent item.

        If you write to this attribute, the item will be moved
        to be inserted just before the target item.
        In case of failure, the item remains in a detached state.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._next_sibling

    @next_sibling.setter
    def next_sibling(self, baseItem target not None):
        # It is important to not lock the mutex before the call
        self.attach_before(target)

    @property
    def children(self):
        """
        Readable attribute: List of all the children of the item,
        from first rendered, to last rendered.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        result = []
        # Note: the children structure is not allowed
        # to change when the parent mutex is held
        cdef baseItem item = self.last_theme_child
        while item is not None:
            result.append(item)
            item = item._prev_sibling
        item = self.last_handler_child
        while item is not None:
            result.append(item)
            item = item._prev_sibling
        item = self.last_plot_element_child
        while item is not None:
            result.append(item)
            item = item._prev_sibling
        item = self.last_payloads_child
        while item is not None:
            result.append(item)
            item = item._prev_sibling
        item = self.last_drawings_child
        while item is not None:
            result.append(item)
            item = item._prev_sibling
        item = self.last_widgets_child
        while item is not None:
            result.append(item)
            item = item._prev_sibling
        item = self.last_window_child
        while item is not None:
            result.append(item)
            item = item._prev_sibling
        item = self.last_menubar_child
        while item is not None:
            result.append(item)
            item = item._prev_sibling
        result.reverse()
        return result

    def __enter__(self):
        # Mutexes not needed
        self.context.push_next_parent(self)
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.context.pop_next_parent()
        return False # Do not catch exceptions

    cdef void lock_parent_and_item_mutex(self,
                                         unique_lock[recursive_mutex] &parent_m,
                                         unique_lock[recursive_mutex] &item_m):
        # We must make sure we lock the correct parent mutex, and for that
        # we must access self._parent and thus hold the item mutex
        cdef bint locked = False
        while not(locked):
            lock_gil_friendly(item_m, self.mutex)
            if self._parent is not None:
                # Manipulate the lock directly
                # as we don't want unique lock to point
                # to a mutex which might be freed (if the
                # parent of the item is changed by another
                # thread and the parent freed)
                locked = self._parent.mutex.try_lock()
            else:
                locked = True
            if locked:
                if self._parent is not None:
                    # Transfert the lock
                    parent_m = unique_lock[recursive_mutex](self._parent.mutex)
                    self._parent.mutex.unlock()
                return
            item_m.unlock()
            if not(locked) and self.external_lock:
                raise RuntimeError(
                    "Trying to lock parent mutex while holding a lock. "
                    "If you get this error, this means you are attempting "
                    "to edit the children list of a parent of nodes you "
                    "hold a mutex to, but you are not holding a mutex of the "
                    "parent. As a result deadlock occured."
                    "To fix this issue:\n "
                    "If the item you are inserting in the parent's children "
                    "list is outside the rendering tree, (you didn't really "
                    " need a mutex) -> release your mutexes.\n "
                    "If the item is in the rendering tree you should lock first "
                    "the parent.")


    cdef void lock_and_previous_siblings(self) noexcept nogil:
        """
        Used when the parent needs to prevent any change to its
        children.
        Note when the parent mutex is held, it can rely that
        its list of children is fixed. However this is used
        when the parent needs to read the individual state
        of its children and needs these state to not change
        for some operations.
        """
        self.mutex.lock()
        if self._prev_sibling is not None:
            self._prev_sibling.lock_and_previous_siblings()

    cdef void unlock_and_previous_siblings(self) noexcept nogil:
        if self._prev_sibling is not None:
            self._prev_sibling.unlock_and_previous_siblings()
        self.mutex.unlock()

    cpdef void attach_to_parent(self, target):
        """
        Same as item.parent = target, but
        target must not be None
        """
        cdef baseItem target_parent
        if not(isinstance(target, baseItem)):
            target_parent = self.context[target]
        else:
            target_parent = <baseItem>target
        # We must ensure a single thread attaches at a given time.
        # __detach_item_and_lock will lock both the item lock
        # and the parent lock.
        cdef unique_lock[recursive_mutex] m0
        # In the case of manipulating the theme tree,
        # block all rendering. This is because with the
        # push/pop system, removing/adding items during
        # rendering cannot work
        if self.element_child_category == child_type.cat_theme:
            lock_gil_friendly(m0, self.context.viewport.mutex)

        cdef unique_lock[recursive_mutex] m
        cdef unique_lock[recursive_mutex] m2
        cdef unique_lock[recursive_mutex] m3
        self.__detach_item_and_lock(m)
        # retaining the lock enables to ensure the item is
        # still detached

        if self.context is None:
            raise ValueError("Trying to attach a deleted item")
        if target_parent is None:
            # Shouldn't occur as should be caught by self.context[target]
            raise RuntimeError("Trying to attach to None")

        # Lock target parent mutex
        lock_gil_friendly(m2, target_parent.mutex)

        cdef bint attached = False

        # Attach to parent in the correct category
        # Note that Cython converts this into a switch().
        if self.element_child_category == child_type.cat_drawing:
            if target_parent.can_have_drawing_child:
                if target_parent.last_drawings_child is not None:
                    lock_gil_friendly(m3, target_parent.last_drawings_child.mutex)
                    target_parent.last_drawings_child._next_sibling = self
                self._prev_sibling = target_parent.last_drawings_child
                self._parent = target_parent
                target_parent.last_drawings_child = <drawingItem>self
                attached = True
        elif self.element_child_category == child_type.cat_handler:
            if target_parent.can_have_handler_child:
                if target_parent.last_handler_child is not None:
                    lock_gil_friendly(m3, target_parent.last_handler_child.mutex)
                    target_parent.last_handler_child._next_sibling = self
                self._prev_sibling = target_parent.last_handler_child
                self._parent = target_parent
                target_parent.last_handler_child = <baseHandler>self
                attached = True
        elif self.element_child_category == child_type.cat_menubar:
            if target_parent.can_have_menubar_child:
                if target_parent.last_menubar_child is not None:
                    lock_gil_friendly(m3, target_parent.last_menubar_child.mutex)
                    target_parent.last_menubar_child._next_sibling = self
                self._prev_sibling = target_parent.last_menubar_child
                self._parent = target_parent
                target_parent.last_menubar_child = <uiItem>self
                attached = True
        elif self.element_child_category == child_type.cat_plot_element:
            if target_parent.can_have_plot_element_child:
                if target_parent.last_plot_element_child is not None:
                    lock_gil_friendly(m3, target_parent.last_plot_element_child.mutex)
                    target_parent.last_plot_element_child._next_sibling = self
                self._prev_sibling = target_parent.last_plot_element_child
                self._parent = target_parent
                target_parent.last_plot_element_child = <plotElement>self
                attached = True
        elif self.element_child_category == child_type.cat_tab:
            if target_parent.can_have_tab_child:
                if target_parent.last_tab_child is not None:
                    lock_gil_friendly(m3, target_parent.last_tab_child.mutex)
                    target_parent.last_tab_child._next_sibling = self
                self._prev_sibling = target_parent.last_tab_child
                self._parent = target_parent
                target_parent.last_tab_child = <uiItem>self
                attached = True
        elif self.element_child_category == child_type.cat_theme:
            if target_parent.can_have_theme_child:
                if target_parent.last_theme_child is not None:
                    lock_gil_friendly(m3, target_parent.last_theme_child.mutex)
                    target_parent.last_theme_child._next_sibling = self
                self._prev_sibling = target_parent.last_theme_child
                self._parent = target_parent
                target_parent.last_theme_child = <baseTheme>self
                attached = True
        elif self.element_child_category == child_type.cat_widget:
            if target_parent.can_have_widget_child:
                if target_parent.last_widgets_child is not None:
                    lock_gil_friendly(m3, target_parent.last_widgets_child.mutex)
                    target_parent.last_widgets_child._next_sibling = self
                self._prev_sibling = target_parent.last_widgets_child
                self._parent = target_parent
                target_parent.last_widgets_child = <uiItem>self
                attached = True
        elif self.element_child_category == child_type.cat_window:
            if target_parent.can_have_window_child:
                if target_parent.last_window_child is not None:
                    lock_gil_friendly(m3, target_parent.last_window_child.mutex)
                    target_parent.last_window_child._next_sibling = self
                self._prev_sibling = target_parent.last_window_child
                self._parent = target_parent
                target_parent.last_window_child = <Window>self
                attached = True
        if not(attached):
            raise ValueError("Instance of type {} cannot be attached to {}".format(type(self), type(target_parent)))

    cpdef void attach_before(self, target):
        """
        Same as item.next_sibling = target,
        but target must not be None
        """
        cdef baseItem target_before
        if not(isinstance(target, baseItem)):
            target_before = self.context[target]
        else:
            target_before = <baseItem>target
        # We must ensure a single thread attaches at a given time.
        # __detach_item_and_lock will lock both the item lock
        # and the parent lock.
        cdef unique_lock[recursive_mutex] m0
        # In the case of manipulating the theme tree,
        # block all rendering. This is because with the
        # push/pop system, removing/adding items during
        # rendering cannot work
        if self.element_child_category == child_type.cat_theme:
            lock_gil_friendly(m0, self.context.viewport.mutex)

        cdef unique_lock[recursive_mutex] m
        cdef unique_lock[recursive_mutex] target_before_m
        cdef unique_lock[recursive_mutex] target_parent_m
        self.__detach_item_and_lock(m)
        # retaining the lock enables to ensure the item is
        # still detached

        if self.context is None:
            raise ValueError("Trying to attach a deleted item")

        if target_before is None:
            raise ValueError("target before cannot be None")

        # Lock target mutex and its parent mutex
        target_before.lock_parent_and_item_mutex(target_parent_m,
                                                 target_before_m)

        if target_before._parent is None:
            # We can bind to an unattached parent, but not
            # to unattached siblings. Could be implemented, but not trivial
            raise ValueError("Trying to attach to an un-attached sibling. Not yet supported")

        # Check the elements can indeed be siblings
        if not(self.can_have_sibling):
            raise ValueError("Instance of type {} cannot have a sibling".format(type(self)))
        if not(target_before.can_have_sibling):
            raise ValueError("Instance of type {} cannot have a sibling".format(type(target_before)))
        if self.element_child_category != target_before.element_child_category:
            raise ValueError("Instance of type {} cannot be sibling to {}".format(type(self), type(target_before)))

        # Attach to sibling
        cdef baseItem _prev_sibling = target_before._prev_sibling
        self._parent = target_before._parent
        # Potential deadlocks are avoided by the fact that we hold the parent
        # mutex and any lock of a next sibling must hold the parent
        # mutex.
        cdef unique_lock[recursive_mutex] prev_m
        if _prev_sibling is not None:
            lock_gil_friendly(prev_m, _prev_sibling.mutex)
            _prev_sibling._next_sibling = self
        self._prev_sibling = _prev_sibling
        self._next_sibling = target_before
        target_before._prev_sibling = self

    cdef void __detach_item_and_lock(self, unique_lock[recursive_mutex]& m):
        # NOTE: the mutex is not locked if we raise an exception.
        # Detach the item from its parent and siblings
        # We are going to change the tree structure, we must lock
        # the parent mutex first and foremost
        cdef unique_lock[recursive_mutex] parent_m
        self.lock_parent_and_item_mutex(parent_m, m)
        # Use unique lock for the mutexes to
        # simplify handling (parent will change)

        if self.parent is None:
            return # nothing to do

        # Remove this item from the list of siblings
        if self._prev_sibling is not None:
            with nogil:
                self._prev_sibling.mutex.lock()
            self._prev_sibling._next_sibling = self._next_sibling
            self._prev_sibling.mutex.unlock()
        if self._next_sibling is not None:
            with nogil:
                self._next_sibling.mutex.lock()
            self._next_sibling._prev_sibling = self._prev_sibling
            self._next_sibling.mutex.unlock()
        else:
            # No next sibling. We might be referenced in the
            # parent
            if self._parent is not None:
                if self._parent.last_window_child is self:
                    self._parent.last_window_child = self._prev_sibling
                elif self._parent.last_widgets_child is self:
                    self._parent.last_widgets_child = self._prev_sibling
                elif self._parent.last_drawings_child is self:
                    self._parent.last_drawings_child = self._prev_sibling
                elif self._parent.last_payloads_child is self:
                    self._parent.last_payloads_child = self._prev_sibling
                elif self._parent.last_plot_element_child is self:
                    self._parent.last_plot_element_child = self._prev_sibling
                elif self._parent.last_handler_child is self:
                    self._parent.last_handler_child = self._prev_sibling
                elif self._parent.last_theme_child is self:
                    self._parent.last_theme_child = self._prev_sibling
        # Free references
        self._parent = None
        self._prev_sibling = None
        self._next_sibling = None

    cpdef void detach_item(self):
        """
        Same as item.parent = None
        """
        cdef unique_lock[recursive_mutex] m0
        cdef unique_lock[recursive_mutex] m
        # In the case of manipulating the theme tree,
        # block all rendering. This is because with the
        # push/pop system, removing/adding items during
        # rendering cannot work
        if self.element_child_category == child_type.cat_theme:
            lock_gil_friendly(m0, self.context.viewport.mutex)
        self.__detach_item_and_lock(m)

    cpdef void delete_item(self):
        """
        When an item is not referenced anywhere, it might
        not get deleted immediately, due to circular references.
        The Python garbage collector will eventually catch
        the circular references, but to speedup the process,
        delete_item will recursively detach the item
        and all elements in its subtree, as well as bound
        items. As a result, items with no more references
        will be freed immediately.
        """
        cdef unique_lock[recursive_mutex] m0
        # In the case of manipulating the theme tree,
        # block all rendering. This is because with the
        # push/pop system, removing/adding items during
        # rendering cannot work
        if self.element_child_category == child_type.cat_theme:
            lock_gil_friendly(m0, self.context.viewport.mutex)

        cdef unique_lock[recursive_mutex] m
        self.__detach_item_and_lock(m)
        # retaining the lock enables to ensure the item is
        # still detached

        if self.context is None:
            raise ValueError("Trying to delete a deleted item")

        # Remove this item from the list of elements
        if self._prev_sibling is not None:
            with nogil:
                self._prev_sibling.mutex.lock()
            self._prev_sibling._next_sibling = self._next_sibling
            self._prev_sibling.mutex.unlock()
        if self._next_sibling is not None:
            with nogil:
                self._next_sibling.mutex.lock()
            self._next_sibling._prev_sibling = self._prev_sibling
            self._next_sibling.mutex.unlock()
        else:
            # No next sibling. We might be referenced in the
            # parent
            if self._parent is not None:
                if self._parent.last_window_child is self:
                    self._parent.last_window_child = self._prev_sibling
                elif self._parent.last_widgets_child is self:
                    self._parent.last_widgets_child = self._prev_sibling
                elif self._parent.last_drawings_child is self:
                    self._parent.last_drawings_child = self._prev_sibling
                elif self._parent.last_payloads_child is self:
                    self._parent.last_payloads_child = self._prev_sibling
                elif self._parent.last_plot_element_child is self:
                    self._parent.last_plot_element_child = self._prev_sibling
                elif self._parent.last_handler_child is self:
                    self._parent.last_handler_child = self._prev_sibling
                elif self._parent.last_theme_child is self:
                    self._parent.last_theme_child = self._prev_sibling

        # delete all children recursively
        if self.last_window_child is not None:
            (<baseItem>self.last_window_child).__delete_and_siblings()
        if self.last_widgets_child is not None:
            (<baseItem>self.last_widgets_child).__delete_and_siblings()
        if self.last_drawings_child is not None:
            (<baseItem>self.last_drawings_child).__delete_and_siblings()
        if self.last_payloads_child is not None:
            (<baseItem>self.last_payloads_child).__delete_and_siblings()
        if self.last_plot_element_child is not None:
            (<baseItem>self.last_plot_element_child).__delete_and_siblings()
        if self.last_handler_child is not None:
            (<baseItem>self.last_handler_child).__delete_and_siblings()
        if self.last_theme_child is not None:
            (<baseItem>self.last_theme_child).__delete_and_siblings()
        # Free references
        self.context = None # TODO: bound items might have issues with this
        # TODO: free item specific references (themes, font, etc)
        self.last_window_child = None
        self.last_widgets_child = None
        self.last_drawings_child = None
        self.last_payloads_child = None
        self.last_plot_element_child = None
        self.last_handler_child = None
        self.last_theme_child = None

    cdef void __delete_and_siblings(self):
        # Must only be called from delete_item or itself.
        # Assumes the parent mutex is already held
        # and that we don't need to edit the parent last_*_child fields
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        # delete all its children recursively
        if self.last_window_child is not None:
            (<baseItem>self.last_window_child).__delete_and_siblings()
        if self.last_widgets_child is not None:
            (<baseItem>self.last_widgets_child).__delete_and_siblings()
        if self.last_drawings_child is not None:
            (<baseItem>self.last_drawings_child).__delete_and_siblings()
        if self.last_payloads_child is not None:
            (<baseItem>self.last_payloads_child).__delete_and_siblings()
        if self.last_plot_element_child is not None:
            (<baseItem>self.last_plot_element_child).__delete_and_siblings()
        if self.last_handler_child is not None:
            (<baseItem>self.last_handler_child).__delete_and_siblings()
        if self.last_theme_child is not None:
            (<baseItem>self.last_theme_child).__delete_and_siblings()
        # delete previous sibling
        if self._prev_sibling is not None:
            (<baseItem>self._prev_sibling).__delete_and_siblings()
        # Free references
        self.context = None
        self._parent = None
        self._prev_sibling = None
        self._next_sibling = None
        self.last_window_child = None
        self.last_widgets_child = None
        self.last_drawings_child = None
        self.last_payloads_child = None
        self.last_plot_element_child = None
        self.last_handler_child = None
        self.last_theme_child = None

    def lock_mutex(self, wait=False):
        """
        Lock the internal item mutex.
        **Know what you are doing**
        Locking the mutex will prevent:
        . Other threads from reading/writing
          attributes or calling methods with this item,
          editing the children/parent of the item
        . Any rendering of this item and its children.
          If the viewport attemps to render this item,
          it will be blocked until the mutex is released.
          (if the rendering thread is holding the mutex,
           no blocking occurs)
        This is useful if you want to edit several attributes
        in several commands of an item or its subtree,
        and prevent rendering or other threads from accessing
        the item until you have finished.
        If you plan on moving the item position in the rendering
        tree, to avoid deadlock you must hold the mutex of a
        parent of all the items involved in the motion (a common
        parent of the source and target parent). This mutex has to
        be locked before you lock any mutex of your child item
        if this item is already in the rendering tree (to avoid
        deadlock with the rendering thread).
        If you are unsure and plans to move an item already
        in the rendering tree, it is thus best to lock the viewport
        mutex first.

        Input argument:
        . wait (default = False): if locking the mutex fails (mutex
          held by another thread), wait it is released

        Returns: True if the mutex is held, False else.

        The mutex is a recursive mutex, thus you can lock it several
        times in the same thread. Each lock has to be matched to an unlock.
        """
        cdef bint locked = False
        locked = self.mutex.try_lock()
        if not(locked) and not(wait):
            return False
        if not(locked) and wait:
            with nogil:
                self.mutex.lock()
        self.external_lock += 1
        return True

    def unlock_mutex(self):
        """
        Unlock a previously held mutex on this object by this thread.
        Returns True on success, False if no lock was held by this thread.
        """
        cdef bint locked = False
        locked = self.mutex.try_lock()
        if locked and self.external_lock > 0:
            # We managed to lock and an external lock is held
            # thus we are indeed the owning thread
            self.mutex.unlock()
            self.external_lock -= 1
            self.mutex.unlock()
            return True
        return False




@cython.final
@cython.no_gc_clear
cdef class Viewport(baseItem):
    """
    The viewport corresponds to the main item containing
    all the visuals. It is decorated by the operating system,
    and can be minimized/maximized/made fullscreen.

    Rendering starts from the viewports and recursively
    every item renders itself and its children.
    """
    def __cinit__(self, context):
        self.resize_callback = None
        self.initialized = False
        self.viewport = NULL
        self.graphics_initialized = False
        self.can_have_window_child = True
        self.can_have_menubar_child = True
        self.can_have_sibling = False
        self.last_t_before_event_handling = ctime.monotonic_ns()
        self.last_t_before_rendering = self.last_t_before_event_handling
        self.last_t_after_rendering = self.last_t_before_event_handling
        self.last_t_after_swapping = self.last_t_before_event_handling
        self.frame_count = 0

    def __dealloc__(self):
        # NOTE: Called BEFORE the context is released.
        cdef unique_lock[recursive_mutex] m
        cdef unique_lock[recursive_mutex] m2
        lock_gil_friendly(m, self.context.imgui_mutex)
        lock_gil_friendly(m2, self.mutex_backend) # To not release while we render a frame
        ensure_correct_im_context(self.context)
        if self.graphics_initialized:
            cleanup_graphics(self.graphics)
        if self.viewport != NULL:
            mvCleanupViewport(dereference(self.viewport))
            #self.viewport is freed by mvCleanupViewport
            self.viewport = NULL

    cdef initialize(self, unsigned width, unsigned height):
        cdef unique_lock[recursive_mutex] m
        cdef unique_lock[recursive_mutex] m2
        cdef unique_lock[recursive_mutex] m3
        lock_gil_friendly(m, self.context.imgui_mutex)
        lock_gil_friendly(m2, self.mutex)
        lock_gil_friendly(m3, self.mutex_backend)
        ensure_correct_im_context(self.context)
        if self.initialized:
            raise RuntimeError("Viewport already initialized")
            return
        self.viewport = mvCreateViewport(width,
                                         height,
                                         internal_render_callback,
                                         internal_resize_callback,
                                         internal_close_callback,
                                         <void*>self)
        self.initialized = True

    cdef void __check_initialized(self):
        if not(self.initialized):
            raise RuntimeError("The viewport must be initialized before being used")

    @property
    def clear_color(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return (self.viewport.clearColor.r,
                self.viewport.clearColor.g,
                self.viewport.clearColor.b,
                self.viewport.clearColor.a)

    @clear_color.setter
    def clear_color(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef int r, g, b, a
        self.__check_initialized()
        (r, g, b, a) = value
        self.viewport.clearColor = colorFromInts(r, g, b, a)

    @property
    def small_icon(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return str(self.viewport.small_icon)

    @small_icon.setter
    def small_icon(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.small_icon = value.encode("utf-8")

    @property
    def large_icon(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return str(self.viewport.large_icon)

    @large_icon.setter
    def large_icon(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.large_icon = value.encode("utf-8")

    @property
    def x_pos(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return self.viewport.xpos

    @x_pos.setter
    def x_pos(self, int value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.xpos = value
        self.viewport.posDirty = 1

    @property
    def y_pos(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return self.viewport.ypos

    @y_pos.setter
    def y_pos(self, int value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.ypos = value
        self.viewport.posDirty = 1

    @property
    def width(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return self.viewport.actualWidth

    @width.setter
    def width(self, int value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.actualWidth = value
        self.viewport.sizeDirty = 1

    @property
    def height(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return self.viewport.actualHeight

    @height.setter
    def height(self, int value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.actualHeight = value
        self.viewport.sizeDirty = 1

    @property
    def resizable(self) -> bint:
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return self.viewport.resizable

    @resizable.setter
    def resizable(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.resizable = value
        self.viewport.modesDirty = 1

    @property
    def vsync(self) -> bint:
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return self.viewport.vsync

    @vsync.setter
    def vsync(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.vsync = value

    @property
    def min_width(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return self.viewport.minwidth

    @min_width.setter
    def min_width(self, unsigned value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.minwidth = value

    @property
    def max_width(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return self.viewport.maxwidth

    @max_width.setter
    def max_width(self, unsigned value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.maxwidth = value

    @property
    def min_height(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return self.viewport.minheight

    @min_height.setter
    def min_height(self, unsigned value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.minheight = value

    @property
    def max_height(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return self.viewport.maxheight

    @max_height.setter
    def max_height(self, unsigned value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.maxheight = value

    @property
    def always_on_top(self) -> bint:
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return self.viewport.alwaysOnTop

    @always_on_top.setter
    def always_on_top(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.alwaysOnTop = value
        self.viewport.modesDirty = 1

    @property
    def decorated(self) -> bint:
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return self.viewport.decorated

    @decorated.setter
    def decorated(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.decorated = value
        self.viewport.modesDirty = 1

    @property
    def handler(self):
        """
        Writable attribute: bound handler (or handlerList)
        for the viewport.
        Only Key and Mouse handlers are compatible.
        Handlers that check item states won't work.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._handler

    @handler.setter
    def handler(self, baseHandler value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        # Check the list of handlers can use our states. Else raise error
        value.check_bind(self, self.state)
        # yes: bind
        self._handler = value

    @property
    def theme(self):
        """
        Writable attribute: global theme
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._theme

    @theme.setter
    def theme(self, baseTheme value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._theme = value

    @property
    def title(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return str(self.viewport.title)

    @title.setter
    def title(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.title = value.encode("utf-8")
        self.viewport.titleDirty = 1

    @property
    def disable_close(self) -> bint:
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return self.viewport.disableClose

    @disable_close.setter
    def disable_close(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.disableClose = value
        self.viewport.modesDirty = 1

    @property
    def fullscreen(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.viewport.fullScreen

    @fullscreen.setter
    def fullscreen(self, bint value):
        cdef unique_lock[recursive_mutex] m
        cdef unique_lock[recursive_mutex] m2
        cdef unique_lock[recursive_mutex] m3
        lock_gil_friendly(m, self.context.imgui_mutex)
        lock_gil_friendly(m2, self.mutex)
        lock_gil_friendly(m3, self.mutex_backend)
        ensure_correct_im_context(self.context)
        if value and not(self.viewport.fullScreen):
            mvToggleFullScreen(dereference(self.viewport))
        elif not(value) and (self.viewport.fullScreen):
            print("TODO: fullscreen(false)")

    @property
    def minimized(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return None #TODO

    @minimized.setter
    def minimized(self, bint value):
        cdef unique_lock[recursive_mutex] m
        cdef unique_lock[recursive_mutex] m2
        cdef unique_lock[recursive_mutex] m3
        lock_gil_friendly(m, self.context.imgui_mutex)
        lock_gil_friendly(m2, self.mutex)
        lock_gil_friendly(m3, self.mutex_backend)
        ensure_correct_im_context(self.context)
        if value:
            mvMinimizeViewport(dereference(self.viewport))
        else:
            mvRestoreViewport(dereference(self.viewport))

    @property
    def maximized(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return None #TODO

    @maximized.setter
    def maximized(self, bint value):
        cdef unique_lock[recursive_mutex] m
        cdef unique_lock[recursive_mutex] m2
        cdef unique_lock[recursive_mutex] m3
        lock_gil_friendly(m, self.context.imgui_mutex)
        lock_gil_friendly(m2, self.mutex)
        lock_gil_friendly(m3, self.mutex_backend)
        ensure_correct_im_context(self.context)
        if value:
            mvMaximizeViewport(dereference(self.viewport))
        else:
            mvRestoreViewport(dereference(self.viewport))

    @property
    def wait_for_input(self):
        """
        Writable attribute: When the app doesn't need to be
        refreshed, one can save power comsumption by not
        rendering. wait_for_input will pause rendering until
        a mouse or keyboard event is received.
        wake() can also be used to restart rendering
        for one frame.
        """
        return self.viewport.waitForEvents

    @wait_for_input.setter
    def wait_for_input(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.viewport.waitForEvents = value

    @property
    def shown(self) -> bint:
        """
        Whether the viewport window has been created by the
        operating system.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        return self.viewport.shown

    @property
    def resize_callback(self):
        """
        Callback to be issued when the viewport is resized.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._resize_callback

    @resize_callback.setter
    def resize_callback(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._resize_callback = value if isinstance(value, Callback) or value is None else Callback(value)

    @property
    def close_callback(self):
        """
        Callback to be issued when the viewport is closed.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._close_callback

    @close_callback.setter
    def close_callback(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._close_callback = value if isinstance(value, Callback) or value is None else Callback(value)

    @property
    def metrics(self):
        cdef unique_lock[recursive_mutex] m
        cdef unique_lock[recursive_mutex] m2
        lock_gil_friendly(m, self.context.imgui_mutex)
        lock_gil_friendly(m2, self.mutex)

        """
        Return rendering related metrics relative to the last
        frame.
        times are returned in ns and use the monotonic clock
        delta of times are return in float as seconds.

        Render frames does in the folowing order:
        event handling (wait_for_input has effect there)
        rendering (going through all objects and calling imgui)
        presenting to the os (send to the OS the rendered frame)

        No average is performed. To get FPS, one can
        average delta_whole_frame and invert it.
        """
        return {
            "last_time_before_event_handling" : self.last_t_before_event_handling,
            "last_time_before_rendering" : self.last_t_before_rendering,
            "last_time_after_rendering" : self.last_t_after_rendering,
            "last_time_after_swapping": self.last_t_after_swapping,
            "delta_event_handling": self.delta_event_handling,
            "delta_rendering": self.delta_rendering,
            "delta_presenting": self.delta_swapping,
            "delta_whole_frame": self.delta_frame,
            "rendered_vertices": imgui.GetIO().MetricsRenderVertices,
            "rendered_indices": imgui.GetIO().MetricsRenderIndices,
            "rendered_windows": imgui.GetIO().MetricsRenderWindows,
            "active_windows": imgui.GetIO().MetricsActiveWindows,
            "frame_count" : self.frame_count
        }

    def configure(self, **kwargs):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        for (key, value) in kwargs.items():
            setattr(self, key, value)

    cdef void __on_resize(self, int width, int height):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        self.viewport.actualHeight = height
        self.viewport.clientHeight = height
        self.viewport.actualWidth = width
        self.viewport.clientWidth = width
        self.viewport.resized = True
        self.context.queue_callback_arg4int(self._resize_callback,
                                            self,
                                            self.viewport.actualWidth,
                                            self.viewport.actualHeight,
                                            self.viewport.clientWidth,
                                            self.viewport.clientHeight)

    cdef void __on_close(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.__check_initialized()
        if not(<bint>self.viewport.disableClose):
            self.context.started = False
        self.context.queue_callback_noarg(self._close_callback, self)

    cdef void __render(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.last_t_before_rendering = ctime.monotonic_ns()
        # Initialize drawing state
        if self._theme is not None: # maybe apply in render_frame instead ?
            self._theme.push()
        #self.cullMode = 0
        self.perspectiveDivide = False
        self.depthClipping = False
        self.has_matrix_transform = False
        self.in_plot = False
        self.start_pending_theme_actions = 0
        #if self.filedialogRoots is not None:
        #    self.filedialogRoots.draw(<imgui.ImDrawList*>NULL, 0., 0.)
        #if self.colormapRoots is not None:
        #    self.colormapRoots.draw(<imgui.ImDrawList*>NULL, 0., 0.)
        if self.last_window_child is not None:
            self.last_window_child.draw()
        #if self.viewportMenubarRoots is not None:
        #    self.viewportMenubarRoots.draw(<imgui.ImDrawList*>NULL, 0., 0.)
        #if self.last_viewport_drawlist_child is not None:
        #    self.last_viewport_drawlist_child.draw(<imgui.ImDrawList*>NULL, 0., 0.)
        if self.last_menubar_child is not None:
            self.last_menubar_child.draw()
        if self._theme is not None:
            self._theme.pop()
        if self._handler is not None:
            self._handler.run_handler(self, self.state)
        self.last_t_after_rendering = ctime.monotonic_ns()
        return

    cdef void apply_current_transform(self, float *dst_p, float[4] src_p) noexcept nogil:
        """
        Used during rendering as helper to convert drawing coordinates to pixel coordinates
        """
        # assumes imgui + viewport mutex are held
        cdef float[4] transformed_p
        if self.has_matrix_transform:
            transformed_p[0] = self.transform[0][0] * src_p[0] + \
                               self.transform[0][1] * src_p[1] + \
                               self.transform[0][2] * src_p[2] + \
                               self.transform[0][3] * src_p[3]
            transformed_p[1] = self.transform[1][0] * src_p[0] + \
                               self.transform[1][1] * src_p[1] + \
                               self.transform[1][2] * src_p[2] + \
                               self.transform[1][3] * src_p[3]
            transformed_p[2] = self.transform[2][0] * src_p[0] + \
                               self.transform[2][1] * src_p[1] + \
                               self.transform[2][2] * src_p[2] + \
                               self.transform[2][3] * src_p[3]
            transformed_p[3] = self.transform[3][0] * src_p[0] + \
                               self.transform[3][1] * src_p[1] + \
                               self.transform[3][2] * src_p[2] + \
                               self.transform[3][3] * src_p[3]
        else:
            transformed_p = src_p

        if self.perspectiveDivide:
            if transformed_p[3] != 0.:
                transformed_p[0] /= transformed_p[3]
                transformed_p[1] /= transformed_p[3]
                transformed_p[2] /= transformed_p[3]
            transformed_p[3] = 1.

        # TODO clipViewport

        cdef imgui.ImVec2 plot_transformed
        if self.in_plot:
            plot_transformed = \
                implot.PlotToPixels(<double>transformed_p[0],
                                    <double>transformed_p[1],
                                    -1,
                                    -1)
            transformed_p[0] = plot_transformed.x
            transformed_p[1] = plot_transformed.y
        else:
            # Unsure why the original code doesn't do it in the in_plot path
            transformed_p[0] += self.shift_x
            transformed_p[1] += self.shift_y
        dst_p[0] = transformed_p[0]
        dst_p[1] = transformed_p[1]
        dst_p[2] = transformed_p[2]
        dst_p[3] = transformed_p[3]

    cdef void push_pending_theme_actions(self,
                                         theme_enablers theme_activation_condition_enabled,
                                         theme_categories theme_activation_condition_category) noexcept nogil:
        """
        Used during rendering to apply themes defined by items
        parents and that should activate based on specific conditions
        Returns the number of theme actions applied. This number
        should be returned to pop_applied_pending_theme_actions
        """
        self.current_theme_activation_condition_enabled = theme_activation_condition_enabled
        self.current_theme_activation_condition_category = theme_activation_condition_category
        self.push_pending_theme_actions_on_subset(self.start_pending_theme_actions,
                                                  <int>self.pending_theme_actions.size())

    cdef void push_pending_theme_actions_on_subset(self,
                                                   int start,
                                                   int end) noexcept nogil:
        cdef int i
        cdef int size_init = self.applied_theme_actions.size()
        cdef theme_action action
        cdef imgui.ImVec2 value_float2
        cdef theme_enablers theme_activation_condition_enabled = self.current_theme_activation_condition_enabled
        cdef theme_categories theme_activation_condition_category = self.current_theme_activation_condition_category

        cdef bool apply
        for i in range(start, end):
            apply = True
            if self.pending_theme_actions[i].activation_condition_enabled != theme_enablers.t_enabled_any and \
               theme_activation_condition_enabled != theme_enablers.t_enabled_any and \
               self.pending_theme_actions[i].activation_condition_enabled != theme_activation_condition_enabled:
                apply = False
            if self.pending_theme_actions[i].activation_condition_category != theme_activation_condition_category and \
               self.pending_theme_actions[i].activation_condition_category != theme_categories.t_any:
                apply = False
            if apply:
                action = self.pending_theme_actions[i]
                self.applied_theme_actions.push_back(action)
                if action.backend == theme_backends.t_imgui:
                    if action.type == theme_types.t_color:
                        # can only be theme_value_types.t_u32
                        imgui.PushStyleColor(<imgui.ImGuiCol>action.theme_index,
                                             action.value.value_u32)
                    elif action.type == theme_types.t_style:
                        if action.value_type == theme_value_types.t_float:
                            imgui.PushStyleVar(<imgui.ImGuiStyleVar>action.theme_index,
                                               action.value.value_float)
                        elif action.value_type == theme_value_types.t_float2:
                            value_float2 = imgui.ImVec2(action.value.value_float2[0],
                                                        action.value.value_float2[1])
                            imgui.PushStyleVar(<imgui.ImGuiStyleVar>action.theme_index,
                                               value_float2)
                elif action.backend == theme_backends.t_implot:
                    if action.type == theme_types.t_color:
                        # can only be theme_value_types.t_u32
                        implot.PushStyleColor(<implot.ImPlotCol>action.theme_index,
                                             action.value.value_u32)
                    elif action.type == theme_types.t_style:
                        if action.value_type == theme_value_types.t_float:
                            implot.PushStyleVar(<implot.ImPlotStyleVar>action.theme_index,
                                               action.value.value_float)
                        elif action.value_type == theme_value_types.t_int:
                            implot.PushStyleVar(<implot.ImPlotStyleVar>action.theme_index,
                                               action.value.value_int)
                        elif action.value_type == theme_value_types.t_float2:
                            value_float2 = imgui.ImVec2(action.value.value_float2[0],
                                                        action.value.value_float2[1])
                            implot.PushStyleVar(<implot.ImPlotStyleVar>action.theme_index,
                                               value_float2)
                elif action.backend == theme_backends.t_imnodes:
                    if action.type == theme_types.t_color:
                        # can only be theme_value_types.t_u32
                        imnodes.PushColorStyle(<imnodes.ImNodesCol>action.theme_index,
                                             action.value.value_u32)
                    elif action.type == theme_types.t_style:
                        if action.value_type == theme_value_types.t_float:
                            imnodes.PushStyleVar(<imnodes.ImNodesStyleVar>action.theme_index,
                                               action.value.value_float)
                        elif action.value_type == theme_value_types.t_float2:
                            value_float2 = imnodes.ImVec2(action.value.value_float2[0],
                                                        action.value.value_float2[1])
                            imnodes.PushStyleVar(<imnodes.ImNodesStyleVar>action.theme_index,
                                               value_float2)
        self.applied_theme_actions_count.push_back(self.applied_theme_actions.size() - size_init)

    cdef void pop_applied_pending_theme_actions(self) noexcept nogil:
        """
        Used during rendering to pop what push_pending_theme_actions did
        """
        cdef int count = self.applied_theme_actions_count.back()
        self.applied_theme_actions_count.pop_back()
        if count == 0:
            return
        cdef int i
        cdef int size = self.applied_theme_actions.size()
        cdef theme_action action
        for i in range(count):
            action = self.applied_theme_actions[size-i-1]
            if action.backend == theme_backends.t_imgui:
                if action.type == theme_types.t_color:
                    imgui.PopStyleColor(1)
                elif action.type == theme_types.t_style:
                    imgui.PopStyleVar(1)
            elif action.backend == theme_backends.t_implot:
                if action.type == theme_types.t_color:
                    implot.PopStyleColor(1)
                elif action.type == theme_types.t_style:
                    implot.PopStyleVar(1)
            elif action.backend == theme_backends.t_imnodes:
                if action.type == theme_types.t_color:
                    imnodes.PopColorStyle()
                elif action.type == theme_types.t_style:
                    imnodes.PopStyleVar(1)
        for i in range(count):
            self.applied_theme_actions.pop_back()


    def render_frame(self):
        """
        Render one frame.

        Rendering occurs in several separated steps:
        . Mouse/Keyboard events are processed. it's there
          that wait_for_input has an effect.
        . The viewport item, and then all the rendering tree are
          walked through to query their state and prepare the rendering
          commands using ImGui, ImPlot and ImNodes
        . The rendering commands are submitted to the GPU.
        . The submission is passed to the operating system to handle the
          window update. It's usually at this step that the system will
          apply vsync by making the application wait if it rendered faster
          than the screen refresh rate.
        """
        # to lock in this order
        cdef unique_lock[recursive_mutex] imgui_m = unique_lock[recursive_mutex](self.context.imgui_mutex, defer_lock_t())
        cdef unique_lock[recursive_mutex] self_m
        cdef unique_lock[recursive_mutex] backend_m = unique_lock[recursive_mutex](self.mutex_backend, defer_lock_t())
        lock_gil_friendly(self_m, self.mutex)
        self.__check_initialized()
        assert(self.graphics_initialized)
        self.last_t_before_event_handling = ctime.monotonic_ns()
        with nogil:
            backend_m.lock()
            self_m.unlock()
            # Process input events.
            # Doesn't need imgui mutex.
            # if wait_for_input is set, can take a long time
            mvProcessEvents(self.viewport)
            backend_m.unlock() # important to respect lock order
            # Core rendering - uses imgui and viewport
            imgui_m.lock()
            self_m.lock()
            backend_m.lock()
            #self.last_t_before_rendering = ctime.monotonic_ns()
            ensure_correct_im_context(self.context)
            mvRenderFrame(dereference(self.viewport),
			    		  self.graphics)
            #self.last_t_after_rendering = ctime.monotonic_ns()
            backend_m.unlock()
            self_m.unlock()
            imgui_m.unlock()
            # Present doesn't use imgui but can take time (vsync)
            backend_m.lock()
            mvPresent(self.viewport)
            backend_m.unlock()
            self_m.lock()
        cdef long long current_time = ctime.monotonic_ns()
        self.delta_frame = 1e-9 * <float>(current_time - self.last_t_after_swapping)
        self.last_t_after_swapping = current_time
        self.delta_swapping = 1e-9 * <float>(current_time - self.last_t_after_rendering)
        self.delta_rendering = 1e-9 * <float>(self.last_t_after_rendering - self.last_t_before_rendering)
        self.delta_event_handling = 1e-9 * <float>(self.last_t_before_rendering - self.last_t_before_event_handling)
        if self.viewport.resized:
            self.context.queue_callback_arg4int(self._resize_callback,
                                                self,
                                                self.viewport.actualWidth,
                                                self.viewport.actualHeight,
                                                self.viewport.clientWidth,
                                                self.viewport.clientHeight)
            self.viewport.resized = False
        self.frame_count += 1
        assert(self.pending_theme_actions.empty())
        assert(self.applied_theme_actions.empty())
        assert(self.start_pending_theme_actions == 0)

    def show(self, minimized=False, maximized=False):
        cdef unique_lock[recursive_mutex] m
        cdef unique_lock[recursive_mutex] m2
        lock_gil_friendly(m, self.context.imgui_mutex)
        lock_gil_friendly(m2, self.mutex)
        cdef imgui.ImGuiStyle* style
        cdef mvColor* colors
        self.__check_initialized()
        ensure_correct_im_context(self.context)
        mvShowViewport(dereference(self.viewport),
                       minimized,
                       maximized)
        if not(self.graphics_initialized):
            self.graphics = setup_graphics(dereference(self.viewport))
            imgui.StyleColorsDark()
            """
            imgui.GetIO().ConfigWindowsMoveFromTitleBarOnly = True
            # TODO if (GContext->IO.autoSaveIniFile). if (!GContext->IO.iniFile.empty())
			# io.IniFilename = GContext->IO.iniFile.c_str();

            # TODO if(GContext->IO.kbdNavigation)
		    # io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;  // Enable Keyboard Controls
            #if(GContext->IO.docking)
            # io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;
            # io.ConfigDockingWithShift = GContext->IO.dockingShiftOnly;
            """
            self.graphics_initialized = True
        self.viewport.shown = 1

    def wake(self):
        """
        In case rendering is waiting for an input (waitForInputs),
        generate a fake input to force rendering.

        This is useful if you have updated the content asynchronously
        and want to show the update
        """
        cdef unique_lock[recursive_mutex] m
        cdef unique_lock[recursive_mutex] m2
        lock_gil_friendly(m, self.context.imgui_mutex)
        lock_gil_friendly(m2, self.mutex)
        mvWakeRendering(dereference(self.viewport))


cdef class Callback:
    def __cinit__(self, callback):
        if not(callable(callback)):
            raise TypeError("Callback requires a callable object")
        self.callback = callback
        self.num_args = callback.__code__.co_argcount
        if self.num_args > 3:
            self.num_args = 3
            #raise ValueError("Callback function takes too many arguments")

    def __call__(self, item, call_info, user_data):
        try:
            if self.num_args == 3:
                self.callback(item, call_info, user_data)
            elif self.num_args == 2:
                self.callback(item, call_info)
            elif self.num_args == 1:
                self.callback(item)
            else:
                self.callback()
        except Exception as e:
            print(f"Callback {self.callback} raised exception {e}")
            if self.num_args == 3:
                print(f"Callback arguments were: {item}, {call_info}, {user_data}")
            if self.num_args == 2:
                print(f"Callback arguments were: {item}, {call_info}")
            if self.num_args == 1:
                print(f"Callback argument was: {item}")
            else:
                print("Callback called without arguments")
            print(traceback.format_exc())

"""
PlaceHolder parent
To store items outside the rendering tree
Can be parent to anything.
Cannot have any parent. Thus cannot render.
"""
cdef class PlaceHolderParent(baseItem):
    def __cinit__(self):
        self.can_have_drawing_child = True
        self.can_have_handler_child = True
        self.can_have_menubar_child = True
        self.can_have_payload_child = True
        self.can_have_tab_child = True
        self.can_have_theme_child = True
        self.can_have_widget_child = True
        self.can_have_window_child = True

"""
Drawing items
"""


cdef class drawingItem(baseItem):
    """
    A simple item with no UI state,
    that inherit from the drawing area of its
    parent
    """
    def __cinit__(self):
        self._show = True
        self.element_child_category = child_type.cat_drawing
        self.can_have_sibling = True

    def configure(self, **kwargs):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._show = kwargs.pop("show", self._show)
        super().configure(**kwargs)

    @property
    def show(self):
        """
        Writable attribute: Should the object be drawn/shown ?
        In case show is set to False, this disables any
        callback (for example the close callback won't be called
        if a window is hidden with show = False).
        In the case of items that can be closed,
        show is set to False automatically on close.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._show
    @show.setter
    def show(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._show = value

    cdef void draw_prev_siblings(self, imgui.ImDrawList* l) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        if self._prev_sibling is not None:
            (<drawingItem>self._prev_sibling).draw(l)

    cdef void draw(self, imgui.ImDrawList* l) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(l)

cdef class DrawingList(drawingItem):
    """
    A simple drawing item that renders its children.
    Useful to arrange your items and quickly
    hide/show/delete them by manipulating the list.
    """
    def __cinit__(self):
        self.can_have_drawing_child = True

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show):
            return
        if self.last_drawings_child is None:
            return

        # draw children
        self.last_drawings_child.draw(drawlist)

cdef class DrawLayer_(drawingItem):
    """
    Similar to a DrawingList, but
    can apply scene clipping, enable
    perspective divide and/or a 4x4 matrix
    transform.
    """
    def __cinit__(self):
        self._cull_mode = 0 # mvCullMode_None == 0
        self._perspective_divide = False
        self._depth_clipping = False
        self.clip_viewport = [0.0, 0.0, 1.0, 1.0, -1.0, 1.0]
        self.has_matrix_transform = False
        self.can_have_drawing_child = True

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show):
            return
        if self.last_drawings_child is None:
            return

        # Reset current drawInfo - except in_plot as we keep drawlist
        #self.context.viewport.cullMode = self._cull_mode
        self.context.viewport.perspectiveDivide = self._perspective_divide
        self.context.viewport.depthClipping = self._depth_clipping
        if self._depth_clipping:
            self.context.viewport.clipViewport = self.clip_viewport
        #if self.has_matrix_transform and self.context.viewport.has_matrix_transform:
        #    TODO
        #    matrix_fourfour_mul(self.context.viewport.transform, self.transform)
        #elif
        if self.has_matrix_transform:
            self.context.viewport.has_matrix_transform = True
            self.context.viewport.transform = self._transform
        # As we inherit from drawlist
        # We don't change self.in_plot

        # draw children
        self.last_drawings_child.draw(drawlist)

cdef class DrawArrow_(drawingItem):
    def __cinit__(self):
        # p1, p2, etc are zero init by cython
        self.color = 4294967295 # 0xffffffff
        self.thickness = 1.
        self.size = 4.

    cdef void __compute_tip(self):
        # Copy paste from original code

        cdef float xsi = self.end[0]
        cdef float xfi = self.start[0]
        cdef float ysi = self.end[1]
        cdef float yfi = self.start[1]

        # length of arrow head
        cdef double xoffset = self.size
        cdef double yoffset = self.size

        # get pointer angle w.r.t +X (in radians)
        cdef double angle = 0.0
        if xsi >= xfi and ysi >= yfi:
            angle = atan((ysi - yfi) / (xsi - xfi))
        elif xsi < xfi and ysi >= yfi:
            angle = M_PI + atan((ysi - yfi) / (xsi - xfi))
        elif xsi < xfi and ysi < yfi:
            angle = -M_PI + atan((ysi - yfi) / (xsi - xfi))
        elif xsi >= xfi and ysi < yfi:
            angle = atan((ysi - yfi) / (xsi - xfi))

        cdef float x1 = <float>(xsi - xoffset * cos(angle))
        cdef float y1 = <float>(ysi - yoffset * sin(angle))
        self.corner1 = [x1 - 0.5 * self.size * sin(angle),
                        y1 + 0.5 * self.size * cos(angle),
                        0.,
                        1.]
        self.corner2 = [x1 + 0.5 * self.size * cos((M_PI / 2.0) - angle),
                        y1 - 0.5 * self.size * sin((M_PI / 2.0) - angle),
                        0.,
                        1.]

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show):
            return

        cdef float thickness = self.thickness
        if self.context.viewport.in_plot:
            thickness *= self.context.viewport.thickness_multiplier

        cdef float[4] tstart
        cdef float[4] tend
        cdef float[4] tcorner1
        cdef float[4] tcorner2
        self.context.viewport.apply_current_transform(tstart, self.start)
        self.context.viewport.apply_current_transform(tend, self.end)
        self.context.viewport.apply_current_transform(tcorner1, self.corner1)
        self.context.viewport.apply_current_transform(tcorner2, self.corner2)
        cdef imgui.ImVec2 itstart = imgui.ImVec2(tstart[0], tstart[1])
        cdef imgui.ImVec2 itend  = imgui.ImVec2(tend[0], tend[1])
        cdef imgui.ImVec2 itcorner1 = imgui.ImVec2(tcorner1[0], tcorner1[1])
        cdef imgui.ImVec2 itcorner2 = imgui.ImVec2(tcorner2[0], tcorner2[1])
        drawlist.AddTriangleFilled(itend, itcorner1, itcorner2, self.color)
        drawlist.AddLine(itend, itstart, self.color, thickness)
        drawlist.AddTriangle(itend, itcorner1, itcorner2, self.color, thickness)


cdef class DrawBezierCubic_(drawingItem):
    def __cinit__(self):
        # p1, etc are zero init by cython
        self.color = 4294967295 # 0xffffffff
        self.thickness = 0.
        self.segments = 0

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show):
            return

        cdef float thickness = self.thickness
        if self.context.viewport.in_plot:
            thickness *= self.context.viewport.thickness_multiplier

        cdef float[4] p1
        cdef float[4] p2
        cdef float[4] p3
        cdef float[4] p4
        self.context.viewport.apply_current_transform(p1, self.p1)
        self.context.viewport.apply_current_transform(p2, self.p2)
        self.context.viewport.apply_current_transform(p3, self.p3)
        self.context.viewport.apply_current_transform(p4, self.p4)
        cdef imgui.ImVec2 ip1 = imgui.ImVec2(p1[0], p1[1])
        cdef imgui.ImVec2 ip2 = imgui.ImVec2(p2[0], p2[1])
        cdef imgui.ImVec2 ip3 = imgui.ImVec2(p3[0], p3[1])
        cdef imgui.ImVec2 ip4 = imgui.ImVec2(p4[0], p4[1])
        drawlist.AddBezierCubic(ip1, ip2, ip3, ip4, self.color, self.thickness, self.segments)

cdef class DrawBezierQuadratic_(drawingItem):
    def __cinit__(self):
        # p1, etc are zero init by cython
        self.color = 4294967295 # 0xffffffff
        self.thickness = 0.
        self.segments = 0

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show):
            return

        cdef float thickness = self.thickness
        if self.context.viewport.in_plot:
            thickness *= self.context.viewport.thickness_multiplier

        cdef float[4] p1
        cdef float[4] p2
        cdef float[4] p3
        self.context.viewport.apply_current_transform(p1, self.p1)
        self.context.viewport.apply_current_transform(p2, self.p2)
        self.context.viewport.apply_current_transform(p3, self.p3)
        cdef imgui.ImVec2 ip1 = imgui.ImVec2(p1[0], p1[1])
        cdef imgui.ImVec2 ip2 = imgui.ImVec2(p2[0], p2[1])
        cdef imgui.ImVec2 ip3 = imgui.ImVec2(p3[0], p3[1])
        drawlist.AddBezierQuadratic(ip1, ip2, ip3, self.color, self.thickness, self.segments)


cdef class DrawCircle_(drawingItem):
    def __cinit__(self):
        # center is zero init by cython
        self.color = 4294967295 # 0xffffffff
        self.fill = 0
        self.radius = 1.
        self.thickness = 1.
        self.segments = 0

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show):
            return

        cdef float thickness = self.thickness
        cdef float radius = self.radius
        if self.context.viewport.in_plot:
            thickness *= self.context.viewport.thickness_multiplier
            radius *= self.context.viewport.thickness_multiplier

        cdef float[4] center
        self.context.viewport.apply_current_transform(center, self.center)
        cdef imgui.ImVec2 icenter = imgui.ImVec2(center[0], center[1])
        if self.fill & imgui.IM_COL32_A_MASK != 0:
            drawlist.AddCircleFilled(icenter, radius, self.fill, self.segments)
        drawlist.AddCircle(icenter, radius, self.color, self.segments, thickness)


cdef class DrawEllipse_(drawingItem):
    # TODO: I adapted the original code,
    # But these deserves rewrite: call the imgui Ellipse functions instead
    # and add rotation parameter
    def __cinit__(self):
        # pmin/pmax is zero init by cython
        self.color = 4294967295 # 0xffffffff
        self.fill = 0
        self.thickness = 1.
        self.segments = 0

    cdef void __fill_points(self):
        cdef int segments = max(self.segments, 3)
        cdef float width = self.pmax[0] - self.pmin[0]
        cdef float height = self.pmax[1] - self.pmin[1]
        cdef float cx = width / 2. + self.pmin[0]
        cdef float cy = height / 2. + self.pmin[1]
        cdef float radian_inc = (M_PI * 2.) / <float>segments
        self.points.clear()
        self.points.reserve(segments+1)
        cdef int i
        # vector needs float4 rather than float[4]
        cdef float4 p
        p.p[2] = self.pmax[2]
        p.p[3] = self.pmax[3]
        width = abs(width)
        height = abs(height)
        for i in range(segments):
            p.p[0] = cx + cos(<float>i * radian_inc) * width / 2.
            p.p[1] = cy - sin(<float>i * radian_inc) * height / 2.
            self.points.push_back(p)
        self.points.push_back(self.points[0])

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show) or self.points.size() < 3:
            return

        cdef float thickness = self.thickness
        if self.context.viewport.in_plot:
            thickness *= self.context.viewport.thickness_multiplier

        cdef vector[imgui.ImVec2] transformed_points
        transformed_points.reserve(self.points.size())
        cdef int i
        cdef float[4] p
        for i in range(<int>self.points.size()):
            self.context.viewport.apply_current_transform(p, self.points[i].p)
            transformed_points.push_back(imgui.ImVec2(p[0], p[1]))
        # TODO imgui requires clockwise order for correct AA
        # Reverse order if needed
        if self.fill & imgui.IM_COL32_A_MASK != 0:
            drawlist.AddConvexPolyFilled(transformed_points.data(),
                                                <int>transformed_points.size(),
                                                self.fill)
        drawlist.AddPolyline(transformed_points.data(),
                                    <int>transformed_points.size(),
                                    self.color,
                                    0,
                                    thickness)


cdef class DrawImage_(drawingItem):
    def __cinit__(self):
        self.uv = [0., 0., 1., 1.]
        self.color_multiplier = 4294967295 # 0xffffffff

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show) or self.texture is None:
            return

        cdef unique_lock[recursive_mutex] m4 = unique_lock[recursive_mutex](self.texture.mutex)

        cdef float[4] pmin
        cdef float[4] pmax
        self.context.viewport.apply_current_transform(pmin, self.pmin)
        self.context.viewport.apply_current_transform(pmax, self.pmax)
        cdef imgui.ImVec2 ipmin = imgui.ImVec2(pmin[0], pmin[1])
        cdef imgui.ImVec2 ipmax = imgui.ImVec2(pmax[0], pmax[1])
        cdef imgui.ImVec2 uvmin = imgui.ImVec2(self.uv[0], self.uv[1])
        cdef imgui.ImVec2 uvmax = imgui.ImVec2(self.uv[2], self.uv[3])
        drawlist.AddImage(self.texture.allocated_texture, ipmin, ipmax, uvmin, uvmax, self.color_multiplier)


cdef class DrawImageQuad_(drawingItem):
    def __cinit__(self):
        # last two fields are unused
        self.uv1 = [0., 0., 0., 0.]
        self.uv2 = [0., 0., 0., 0.]
        self.uv3 = [0., 0., 0., 0.]
        self.uv4 = [0., 0., 0., 0.]
        self.color_multiplier = 4294967295 # 0xffffffff

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show) or self.texture is None:
            return

        cdef unique_lock[recursive_mutex] m4 = unique_lock[recursive_mutex](self.texture.mutex)

        cdef float[4] p1
        cdef float[4] p2
        cdef float[4] p3
        cdef float[4] p4
        cdef imgui.ImVec2 ip1
        cdef imgui.ImVec2 ip2
        cdef imgui.ImVec2 ip3
        cdef imgui.ImVec2 ip4

        self.context.viewport.apply_current_transform(p1, self.p1)
        self.context.viewport.apply_current_transform(p2, self.p2)
        self.context.viewport.apply_current_transform(p3, self.p3)
        self.context.viewport.apply_current_transform(p4, self.p4)
        ip1 = imgui.ImVec2(p1[0], p1[1])
        ip2 = imgui.ImVec2(p2[0], p2[1])
        ip3 = imgui.ImVec2(p3[0], p3[1])
        ip4 = imgui.ImVec2(p4[0], p4[1])
        cdef imgui.ImVec2 iuv1 = imgui.ImVec2(self.uv1[0], self.uv1[1])
        cdef imgui.ImVec2 iuv2 = imgui.ImVec2(self.uv2[0], self.uv2[1])
        cdef imgui.ImVec2 iuv3 = imgui.ImVec2(self.uv3[0], self.uv3[1])
        cdef imgui.ImVec2 iuv4 = imgui.ImVec2(self.uv4[0], self.uv4[1])
        drawlist.AddImageQuad(self.texture.allocated_texture, \
            ip1, ip2, ip3, ip4, iuv1, iuv2, iuv3, iuv4, self.color_multiplier)



cdef class DrawLine_(drawingItem):
    def __cinit__(self):
        # p1, p2 are zero init by cython
        self.color = 4294967295 # 0xffffffff
        self.thickness = 1.

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show):
            return

        cdef float thickness = self.thickness
        if self.context.viewport.in_plot:
            thickness *= self.context.viewport.thickness_multiplier

        cdef float[4] p1
        cdef float[4] p2
        self.context.viewport.apply_current_transform(p1, self.p1)
        self.context.viewport.apply_current_transform(p2, self.p2)
        cdef imgui.ImVec2 ip1 = imgui.ImVec2(p1[0], p1[1])
        cdef imgui.ImVec2 ip2 = imgui.ImVec2(p2[0], p2[1])
        drawlist.AddLine(ip1, ip2, self.color, thickness)

cdef class DrawPolyline_(drawingItem):
    def __cinit__(self):
        # points is empty init by cython
        self.color = 4294967295 # 0xffffffff
        self.thickness = 1.
        self.closed = False

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show) or self.points.size() < 2:
            return

        cdef float thickness = self.thickness
        if self.context.viewport.in_plot:
            thickness *= self.context.viewport.thickness_multiplier

        cdef float[4] p
        cdef imgui.ImVec2 ip1
        cdef imgui.ImVec2 ip1_
        cdef imgui.ImVec2 ip2
        self.context.viewport.apply_current_transform(p, self.points[0].p)
        ip1 = imgui.ImVec2(p[0], p[1])
        ip1_ = ip1
        # imgui requires clockwise order + convexity for correct AA of AddPolyline
        # Thus we only call AddLine
        cdef int i
        for i in range(1, <int>self.points.size()):
            self.context.viewport.apply_current_transform(p, self.points[i].p)
            ip2 = imgui.ImVec2(p[0], p[1])
            drawlist.AddLine(ip1, ip2, self.color, thickness)
        if self.closed and self.points.size() > 2:
            drawlist.AddLine(ip1_, ip2, self.color, thickness)

cdef inline bint is_counter_clockwise(imgui.ImVec2 p1,
                                      imgui.ImVec2 p2,
                                      imgui.ImVec2 p3) noexcept nogil:
    cdef float det = (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x)
    return det > 0.

cdef class DrawPolygon_(drawingItem):
    def __cinit__(self):
        # points is empty init by cython
        self.color = 4294967295 # 0xffffffff
        self.fill = 0
        self.thickness = 1.

    # ImGui Polygon fill requires clockwise order and convex polygon.
    # We want to be more lenient -> triangulate
    cdef void __triangulate(self):
        if self.fill & imgui.IM_COL32_A_MASK != 0:
            return
        # TODO: optimize with arrays
        points = []
        cdef int i
        for i in range(<int>self.points.size()):
            # For now perform only in 2D
            points.append([self.points[i].p[0], self.points[i].p[1]])
        # order is counter clock-wise
        self.triangulation_indices = scipy.spatial.Delaunay(points).simplices

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show) or self.points.size() < 2:
            return

        cdef float thickness = self.thickness
        if self.context.viewport.in_plot:
            thickness *= self.context.viewport.thickness_multiplier

        cdef float[4] p
        cdef imgui.ImVec2 ip
        cdef vector[imgui.ImVec2] ipoints
        cdef int i
        cdef bint ccw
        ipoints.reserve(self.points.size())
        for i in range(<int>self.points.size()):
            self.context.viewport.apply_current_transform(p, self.points[i].p)
            ip = imgui.ImVec2(p[0], p[1])
            ipoints.push_back(ip)

        # Draw interior
        if self.fill & imgui.IM_COL32_A_MASK != 0 and self.triangulation_indices.shape[0] > 0:
            # imgui requires clockwise order + convexity for correct AA
            # The triangulation always returns counter-clockwise
            # but the matrix can change the order.
            # The order should be the same for all triangles, except in plot with log
            # scale.
            for i in range(self.triangulation_indices.shape[0]):
                ccw = is_counter_clockwise(ipoints[self.triangulation_indices[i, 0]],
                                           ipoints[self.triangulation_indices[i, 1]],
                                           ipoints[self.triangulation_indices[i, 2]])
                if ccw:
                    drawlist.AddTriangleFilled(ipoints[self.triangulation_indices[i, 0]],
                                                      ipoints[self.triangulation_indices[i, 2]],
                                                      ipoints[self.triangulation_indices[i, 1]],
                                                      self.fill)
                else:
                    drawlist.AddTriangleFilled(ipoints[self.triangulation_indices[i, 0]],
                                                      ipoints[self.triangulation_indices[i, 1]],
                                                      ipoints[self.triangulation_indices[i, 2]],
                                                      self.fill)

        # Draw closed boundary
        # imgui requires clockwise order + convexity for correct AA of AddPolyline
        # Thus we only call AddLine
        for i in range(1, <int>self.points.size()):
            drawlist.AddLine(ipoints[i-1], ipoints[i], self.color, thickness)
        if self.points.size() > 2:
            drawlist.AddLine(ipoints[0], ipoints[<int>self.points.size()-1], self.color, thickness)


cdef class DrawQuad_(drawingItem):
    def __cinit__(self):
        # p1, p2, p3, p4 are zero init by cython
        self.color = 4294967295 # 0xffffffff
        self.fill = 0
        self.thickness = 1.

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show):
            return

        cdef float thickness = self.thickness
        if self.context.viewport.in_plot:
            thickness *= self.context.viewport.thickness_multiplier

        cdef float[4] p1
        cdef float[4] p2
        cdef float[4] p3
        cdef float[4] p4
        cdef imgui.ImVec2 ip1
        cdef imgui.ImVec2 ip2
        cdef imgui.ImVec2 ip3
        cdef imgui.ImVec2 ip4
        cdef bint ccw

        self.context.viewport.apply_current_transform(p1, self.p1)
        self.context.viewport.apply_current_transform(p2, self.p2)
        self.context.viewport.apply_current_transform(p3, self.p3)
        self.context.viewport.apply_current_transform(p4, self.p4)
        ip1 = imgui.ImVec2(p1[0], p1[1])
        ip2 = imgui.ImVec2(p2[0], p2[1])
        ip3 = imgui.ImVec2(p3[0], p3[1])
        ip4 = imgui.ImVec2(p4[0], p4[1])

        # imgui requires clockwise order + convex for correct AA
        if self.fill & imgui.IM_COL32_A_MASK != 0:
            ccw = is_counter_clockwise(ip1,
                                       ip2,
                                       ip3)
            if ccw:
                drawlist.AddTriangleFilled(ip1, ip3, ip2, self.fill)
            else:
                drawlist.AddTriangleFilled(ip1, ip2, ip3, self.fill)
            ccw = is_counter_clockwise(ip1,
                                       ip4,
                                       ip3)
            if ccw:
                drawlist.AddTriangleFilled(ip1, ip3, ip4, self.fill)
            else:
                drawlist.AddTriangleFilled(ip1, ip4, ip3, self.fill)

        drawlist.AddLine(ip1, ip2, self.color, thickness)
        drawlist.AddLine(ip2, ip3, self.color, thickness)
        drawlist.AddLine(ip3, ip4, self.color, thickness)
        drawlist.AddLine(ip4, ip1, self.color, thickness)


cdef class DrawRect_(drawingItem):
    def __cinit__(self):
        self.pmin = [0., 0., 0., 0.]
        self.pmax = [1., 1., 0., 0.]
        self.color = 4294967295 # 0xffffffff
        self.fill = 0
        self.color_upper_left = 0
        self.color_upper_right = 0
        self.color_bottom_left = 0
        self.color_bottom_right = 0
        self.rounding = 0.
        self.thickness = 1.
        self.multicolor = False

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show):
            return

        cdef float thickness = self.thickness
        if self.context.viewport.in_plot:
            thickness *= self.context.viewport.thickness_multiplier

        cdef float[4] pmin
        cdef float[4] pmax
        cdef imgui.ImVec2 ipmin
        cdef imgui.ImVec2 ipmax
        cdef imgui.ImU32 col_up_left = self.color_upper_left
        cdef imgui.ImU32 col_up_right = self.color_upper_right
        cdef imgui.ImU32 col_bot_left = self.color_bottom_left
        cdef imgui.ImU32 col_bot_right = self.color_bottom_right

        self.context.viewport.apply_current_transform(pmin, self.pmin)
        self.context.viewport.apply_current_transform(pmax, self.pmax)
        ipmin = imgui.ImVec2(pmin[0], pmin[1])
        ipmax = imgui.ImVec2(pmax[0], pmax[1])

        # The transform might invert the order
        if ipmin.x > ipmax.x:
            swap(ipmin.x, ipmax.x)
            swap(col_up_left, col_up_right)
            swap(col_bot_left, col_bot_right)
        if ipmin.y > ipmax.y:
            swap(ipmin.y, ipmax.y)
            swap(col_up_left, col_bot_left)
            swap(col_up_right, col_bot_right)

        # imgui requires clockwise order + convex for correct AA
        if self.multicolor:
            if (col_up_left|col_up_right|col_bot_left|col_up_right) & imgui.IM_COL32_A_MASK != 0:
                drawlist.AddRectFilledMultiColor(ipmin,
                                                        ipmax,
                                                        col_up_left,
                                                        col_up_right,
                                                        col_bot_left,
                                                        col_bot_right)
        else:
            if self.fill & imgui.IM_COL32_A_MASK != 0:
                drawlist.AddRectFilled(ipmin,
                                              ipmax,
                                              self.fill,
                                              self.rounding,
                                              imgui.ImDrawFlags_RoundCornersAll)

        drawlist.AddRect(ipmin,
                                ipmax,
                                self.color,
                                self.rounding,
                                imgui.ImDrawFlags_RoundCornersAll,
                                thickness)

cdef class DrawText_(drawingItem):
    def __cinit__(self):
        self.color = 4294967295 # 0xffffffff
        self.size = 1.

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show):
            return

        cdef float[4] p

        self.context.viewport.apply_current_transform(p, self.pos)
        cdef imgui.ImVec2 ip = imgui.ImVec2(p[0], p[1])

        # TODO fontptr

        #drawlist.AddText(fontptr, self.size, ip, self.color, self.text.c_str())
        drawlist.AddText(NULL, 0., ip, self.color, self.text.c_str())


cdef class DrawTriangle_(drawingItem):
    def __cinit__(self):
        # p1, p2, p3 are zero init by cython
        self.color = 4294967295 # 0xffffffff
        self.fill = 0
        self.thickness = 1.
        self.cull_mode = 0

    cdef void draw(self,
                   imgui.ImDrawList* drawlist) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.draw_prev_siblings(drawlist)
        if not(self._show):
            return

        cdef float thickness = self.thickness
        if self.context.viewport.in_plot:
            thickness *= self.context.viewport.thickness_multiplier

        cdef float[4] p1
        cdef float[4] p2
        cdef float[4] p3
        cdef imgui.ImVec2 ip1
        cdef imgui.ImVec2 ip2
        cdef imgui.ImVec2 ip3
        cdef bint ccw

        self.context.viewport.apply_current_transform(p1, self.p1)
        self.context.viewport.apply_current_transform(p2, self.p2)
        self.context.viewport.apply_current_transform(p3, self.p3)
        ip1 = imgui.ImVec2(p1[0], p1[1])
        ip2 = imgui.ImVec2(p2[0], p2[1])
        ip3 = imgui.ImVec2(p3[0], p3[1])
        ccw = is_counter_clockwise(ip1,
                                   ip2,
                                   ip3)

        if self.cull_mode == 1 and ccw:
            return
        if self.cull_mode == 2 and not(ccw):
            return

        # imgui requires clockwise order + convex for correct AA
        if ccw:
            if self.fill & imgui.IM_COL32_A_MASK != 0:
                drawlist.AddTriangleFilled(ip1, ip3, ip2, self.fill)
            drawlist.AddTriangle(ip1, ip3, ip2, self.color, thickness)
        else:
            if self.fill & imgui.IM_COL32_A_MASK != 0:
                drawlist.AddTriangleFilled(ip1, ip2, ip3, self.fill)
            drawlist.AddTriangle(ip1, ip2, ip3, self.color, thickness)

"""
Items that enable to insert drawings in other elements
"""

cdef class DrawInWindow(uiItem):
    def __cinit__(self):
        self.can_have_drawing_child = True
        self.state.can_be_clicked = True
        self.state.can_be_hovered = True
        self.state.can_be_activated = True
        self.state.can_be_active = True
        self.state.has_rect_size = True

    cdef bint draw_item(self) noexcept nogil:
        # negative width is used to indicate UI alignment
        cdef float clip_width = abs(self.requested_size.x)
        if clip_width == 0:
            clip_width = imgui.CalcItemWidth()
        cdef float clip_height = self.requested_size.y
        if clip_height <= 0 or clip_width == 0:
            self.set_hidden_and_propagate() # won't propagate though
            return False
        cdef imgui.ImDrawList* drawlist = imgui.GetWindowDrawList()

        cdef float startx = <float>imgui.GetCursorScreenPos().x
        cdef float starty = <float>imgui.GetCursorScreenPos().y

        # Reset current drawInfo
        #self.context.viewport.cullMode = 0 # mvCullMode_None
        self.context.viewport.perspectiveDivide = False
        self.context.viewport.depthClipping = False
        self.context.viewport.has_matrix_transform = False
        self.context.viewport.in_plot = False
        self.context.viewport.shift_x = startx
        self.context.viewport.shift_y = starty

        imgui.PushClipRect(imgui.ImVec2(startx, starty),
                           imgui.ImVec2(startx + clip_width,
                                        starty + clip_height),
                           True)

        if self.last_drawings_child is not None:
            self.last_drawings_child.draw(drawlist)

        imgui.PopClipRect()

        cdef bint active = imgui.InvisibleButton(self.imgui_label.c_str(),
                                 imgui.ImVec2(clip_width,
                                              clip_height),
                                 imgui.ImGuiButtonFlags_MouseButtonLeft | \
                                 imgui.ImGuiButtonFlags_MouseButtonRight | \
                                 imgui.ImGuiButtonFlags_MouseButtonMiddle)
        self.update_current_state()
        return active
        # UpdateAppItemState(state); ?

        # TODO:
        """
        if (handlerRegistry)
		handlerRegistry->checkEvents(&state);

	    if (ImGui::IsItemHovered())
	    {
		    ImVec2 mousepos = ImGui::GetMousePos();
	    	GContext->input.mouseDrawingPos.x = (int)(mousepos.x - _startx);
    		GContext->input.mouseDrawingPos.y = (int)(mousepos.y - _starty);
	    }
        -> This is very weird. Seems to be used by get_drawing_mouse_pos and
        set only here. But it is not set for the other drawlist
        elements when they are hovered...
        """
        

cdef class ViewportDrawList_(baseItem):
    def __cinit__(self):
        self.element_child_category = child_type.cat_viewport_drawlist
        self.can_have_drawing_child = True
        self._show = True
        self._front = True

    cdef void draw(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        if not(self._show):
            return
        if self.last_drawings_child is None:
            return

        # Reset current drawInfo
        #self.context.viewport.cullMode = 0 # mvCullMode_None
        self.context.viewport.perspectiveDivide = False
        self.context.viewport.depthClipping = False
        self.context.viewport.has_matrix_transform = False
        self.context.viewport.in_plot = False
        self.context.viewport.shift_x = 0
        self.context.viewport.shift_y = 0

        cdef imgui.ImDrawList* internal_drawlist = \
            imgui.GetForegroundDrawList() if self._front else \
            imgui.GetBackgroundDrawList()
        self.last_drawings_child.draw(internal_drawlist)

"""
Global handlers

A global handler doesn't look at the item states,
but at global states. It is usually attached to the
viewport, but can be attached to items. If attached
to items, the items needs to be visible for the callback
to be executed.
"""

cdef class KeyDownHandler_(baseHandler):
    def __cinit__(self):
        self.key = imgui.ImGuiKey_None

    cdef bint check_state(self, baseItem item, itemState& state) noexcept nogil:
        cdef int i
        cdef imgui.ImGuiKeyData *key_info
        if self.key == 0:
            for i in range(imgui.ImGuiKey_NamedKey_BEGIN, imgui.ImGuiKey_AppForward):
                key_info = imgui.GetKeyData(<imgui.ImGuiKey>i)
                if key_info.Down:
                    return True
        else:
            key_info = imgui.GetKeyData(<imgui.ImGuiKey>self.key)
            if key_info.Down:
                return True
        return False

    cdef void run_handler(self, baseItem item, itemState& state) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef imgui.ImGuiKeyData *key_info
        cdef int i
        if self._prev_sibling is not None:
            (<baseHandler>self._prev_sibling).run_handler(item, state)
        if not(self.enabled):
            return
        if self.key == 0:
            for i in range(imgui.ImGuiKey_NamedKey_BEGIN, imgui.ImGuiKey_AppForward):
                key_info = imgui.GetKeyData(<imgui.ImGuiKey>i)
                if key_info.Down:
                    self.context.queue_callback_arg1int1float(self.callback, self, i, key_info.DownDuration)
        else:
            key_info = imgui.GetKeyData(<imgui.ImGuiKey>self.key)
            if key_info.Down:
                self.context.queue_callback_arg1int1float(self.callback, self, self.key, key_info.DownDuration)

cdef class KeyPressHandler_(baseHandler):
    def __cinit__(self):
        self.key = imgui.ImGuiKey_None
        self.repeat = True

    cdef bint check_state(self, baseItem item, itemState& state) noexcept nogil:
        cdef int i
        if self.key == 0:
            for i in range(imgui.ImGuiKey_NamedKey_BEGIN, imgui.ImGuiKey_AppForward):
                if imgui.IsKeyPressed(<imgui.ImGuiKey>i, self.repeat):
                    return True
        else:
            if imgui.IsKeyPressed(<imgui.ImGuiKey>self.key, self.repeat):
                return True
        return False

    cdef void run_handler(self, baseItem item, itemState& state) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef int i
        if self._prev_sibling is not None:
            (<baseHandler>self._prev_sibling).run_handler(item, state)
        if not(self.enabled):
            return
        if self.key == 0:
            for i in range(imgui.ImGuiKey_NamedKey_BEGIN, imgui.ImGuiKey_AppForward):
                if imgui.IsKeyPressed(<imgui.ImGuiKey>i, self.repeat):
                    self.context.queue_callback_arg1int(self.callback, self, i)
        else:
            if imgui.IsKeyPressed(<imgui.ImGuiKey>self.key, self.repeat):
                self.context.queue_callback_arg1int(self.callback, self, self.key)

cdef class KeyReleaseHandler_(baseHandler):
    def __cinit__(self):
        self.key = imgui.ImGuiKey_None

    cdef bint check_state(self, baseItem item, itemState& state) noexcept nogil:
        cdef int i
        if self.key == 0:
            for i in range(imgui.ImGuiKey_NamedKey_BEGIN, imgui.ImGuiKey_AppForward):
                if imgui.IsKeyReleased(<imgui.ImGuiKey>i):
                    return True
        else:
            if imgui.IsKeyReleased(<imgui.ImGuiKey>self.key):
                return True
        return False

    cdef void run_handler(self, baseItem item, itemState& state) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef int i
        if self._prev_sibling is not None:
            (<baseHandler>self._prev_sibling).run_handler(item, state)
        if not(self.enabled):
            return
        if self.key == 0:
            for i in range(imgui.ImGuiKey_NamedKey_BEGIN, imgui.ImGuiKey_AppForward):
                if imgui.IsKeyReleased(<imgui.ImGuiKey>i):
                    self.context.queue_callback_arg1int(self.callback, self, i)
        else:
            if imgui.IsKeyReleased(<imgui.ImGuiKey>self.key):
                self.context.queue_callback_arg1int(self.callback, self, self.key)


cdef class MouseClickHandler_(baseHandler):
    def __cinit__(self):
        self.button = -1
        self.repeat = False

    cdef bint check_state(self, baseItem item, itemState& state) noexcept nogil:
        cdef int i
        for i in range(imgui.ImGuiMouseButton_COUNT):
            if self.button >= 0 and self.button != i:
                continue
            if imgui.IsMouseClicked(i, self.repeat):
                return True
        return False

    cdef void run_handler(self, baseItem item, itemState& state) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef int i
        if self._prev_sibling is not None:
            (<baseHandler>self._prev_sibling).run_handler(item, state)
        if not(self.enabled):
            return
        for i in range(imgui.ImGuiMouseButton_COUNT):
            if self.button >= 0 and self.button != i:
                continue
            if imgui.IsMouseClicked(i, self.repeat):
                self.context.queue_callback_arg1int(self.callback, self, i)

cdef class MouseDoubleClickHandler_(baseHandler):
    def __cinit__(self):
        self.button = -1

    cdef bint check_state(self, baseItem item, itemState& state) noexcept nogil:
        cdef int i
        for i in range(imgui.ImGuiMouseButton_COUNT):
            if self.button >= 0 and self.button != i:
                continue
            if imgui.IsMouseDoubleClicked(i):
                return True
        return False

    cdef void run_handler(self, baseItem item, itemState& state) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef int i
        if self._prev_sibling is not None:
            (<baseHandler>self._prev_sibling).run_handler(item, state)
        if not(self.enabled):
            return
        for i in range(imgui.ImGuiMouseButton_COUNT):
            if self.button >= 0 and self.button != i:
                continue
            if imgui.IsMouseDoubleClicked(i):
                self.context.queue_callback_arg1int(self.callback, self, i)


cdef class MouseDownHandler_(baseHandler):
    def __cinit__(self):
        self.button = -1

    cdef bint check_state(self, baseItem item, itemState& state) noexcept nogil:
        cdef int i
        for i in range(imgui.ImGuiMouseButton_COUNT):
            if self.button >= 0 and self.button != i:
                continue
            if imgui.IsMouseDown(i):
                return True
        return False

    cdef void run_handler(self, baseItem item, itemState& state) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef int i
        if self._prev_sibling is not None:
            (<baseHandler>self._prev_sibling).run_handler(item, state)
        if not(self.enabled):
            return
        for i in range(imgui.ImGuiMouseButton_COUNT):
            if self.button >= 0 and self.button != i:
                continue
            if imgui.IsMouseDown(i):
                self.context.queue_callback_arg1int1float(self.callback, self, i, imgui.GetIO().MouseDownDuration[i])

cdef class MouseDragHandler_(baseHandler):
    def __cinit__(self):
        self.button = -1
        self.threshold = -1 # < 0. means use default

    cdef bint check_state(self, baseItem item, itemState& state) noexcept nogil:
        cdef int i
        for i in range(imgui.ImGuiMouseButton_COUNT):
            if self.button >= 0 and self.button != i:
                continue
            if imgui.IsMouseDragging(i, self.threshold):
                return True
        return False

    cdef void run_handler(self, baseItem item, itemState& state) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef int i
        cdef imgui.ImVec2 delta
        if self._prev_sibling is not None:
            (<baseHandler>self._prev_sibling).run_handler(item, state)
        if not(self.enabled):
            return
        for i in range(imgui.ImGuiMouseButton_COUNT):
            if self.button >= 0 and self.button != i:
                continue
            if imgui.IsMouseDragging(i, self.threshold):
                delta = imgui.GetMouseDragDelta(i, self.threshold)
                self.context.queue_callback_arg1int2float(self.callback, self, i, delta.x, delta.y)


cdef class MouseMoveHandler(baseHandler):
    cdef bint check_state(self, baseItem item, itemState& state) noexcept nogil:
        cdef imgui.ImGuiIO io = imgui.GetIO()
        if io.MousePos.x != io.MousePosPrev.x or \
           io.MousePos.y != io.MousePosPrev.y:
            return True
        return False

    cdef void run_handler(self, baseItem item, itemState& state) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        if self._prev_sibling is not None:
            (<baseHandler>self._prev_sibling).run_handler(item, state)
        if not(self.enabled):
            return
        cdef imgui.ImGuiIO io = imgui.GetIO()
        if io.MousePos.x != io.MousePosPrev.x or \
           io.MousePos.y != io.MousePosPrev.y:
            self.context.queue_callback_arg2float(self.callback, self, io.MousePos.x, io.MousePos.y)
            

cdef class MouseReleaseHandler_(baseHandler):
    def __cinit__(self):
        self.button = -1

    cdef bint check_state(self, baseItem item, itemState& state) noexcept nogil:
        cdef int i
        for i in range(imgui.ImGuiMouseButton_COUNT):
            if self.button >= 0 and self.button != i:
                continue
            if imgui.IsMouseReleased(i):
                return True
        return False

    cdef void run_handler(self, baseItem item, itemState& state) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef int i
        if self._prev_sibling is not None:
            (<baseHandler>self._prev_sibling).run_handler(item, state)
        if not(self.enabled):
            return
        for i in range(imgui.ImGuiMouseButton_COUNT):
            if self.button >= 0 and self.button != i:
                continue
            if imgui.IsMouseReleased(i):
                self.context.queue_callback_arg1int(self.callback, self, i)

cdef class MouseWheelHandler(baseHandler):
    def __cinit__(self, *args, **kwargs):
        self._horizontal = False

    @property
    def horizontal(self):
        """
        Whether to look at the horizontal wheel
        instead of the vertical wheel.

        NOTE: Shift+ vertical wheel => horizontal wheel
        """
        return self._horizontal

    @horizontal.setter
    def horizontal(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._horizontal = value

    cdef bint check_state(self, baseItem item, itemState& state) noexcept nogil:
        cdef imgui.ImGuiIO io = imgui.GetIO()
        if self._horizontal:
            if abs(io.MouseWheelH) > 0.:
                return True
        else:
            if abs(io.MouseWheel) > 0.:
                return True
        return False

    cdef void run_handler(self, baseItem item, itemState& state) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        if self._prev_sibling is not None:
            (<baseHandler>self._prev_sibling).run_handler(item, state)
        if not(self.enabled):
            return
        cdef imgui.ImGuiIO io = imgui.GetIO()
        if self._horizontal:
            if abs(io.MouseWheelH) > 0.:
                self.context.queue_callback_arg1float(self.callback, self, io.MouseWheelH)
        else:
            if abs(io.MouseWheel) > 0.:
                self.context.queue_callback_arg1float(self.callback, self, io.MouseWheel)


"""
Sources
"""

cdef class SharedValue:
    def __init__(self, *args, **kwargs):
        # We create all shared objects using __new__, thus
        # bypassing __init__. If __init__ is called, it's
        # from the user.
        # __init__ is called after __cinit__
        self._num_attached = 0
    def __cinit__(self, Context context, *args, **kwargs):
        self.context = context
        self._last_frame_change = context.viewport.frame_count
        self._last_frame_update = context.viewport.frame_count
        self._num_attached = 1
    @property
    def value(self):
        return None
    @value.setter
    def value(self, value):
        if value is None:
            # In case of automated backup of
            # the value of all items
            return
        raise ValueError("Shared value is empty. Cannot set.")

    @property
    def last_frame_update(self):
        """
        Readable attribute: last frame index when the value
        was updated (can be identical value).
        """
        return self._last_frame_update

    @property
    def last_frame_change(self):
        """
        Readable attribute: last frame index when the value
        was changed (different value).
        For non-scalar data (color, point, vector), equals to
        last_frame_update to avoid heavy comparisons.
        """
        return self._last_frame_change

    @property
    def num_attached(self):
        """
        Readable attribute: Number of items sharing this value
        """
        return self._num_attached

    cdef void on_update(self, bint changed) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        # TODO: figure out if not using mutex is ok
        self._last_frame_update = self.context.viewport.frame_count
        if changed:
            self._last_frame_change = self.context.viewport.frame_count

    cdef void inc_num_attached(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self._num_attached += 1

    cdef void dec_num_attached(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self._num_attached -= 1


cdef class SharedBool(SharedValue):
    def __init__(self, Context context, bint value):
        self._value = value
        self._num_attached = 0
    @property
    def value(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._value
    @value.setter
    def value(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef bint changed = value != self._value
        self._value = value
        self.on_update(changed)
    cdef bint get(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        return self._value
    cdef void set(self, bint value) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef bint changed = value != self._value
        self._value = value
        self.on_update(changed)

cdef class SharedFloat(SharedValue):
    def __init__(self, Context context, float value):
        self._value = value
        self._num_attached = 0
    @property
    def value(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._value
    @value.setter
    def value(self, float value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef bint changed = value != self._value
        self._value = value
        self.on_update(changed)
    cdef float get(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        return self._value
    cdef void set(self, float value) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef bint changed = value != self._value
        self._value = value
        self.on_update(changed)

cdef class SharedInt(SharedValue):
    def __init__(self, Context context, int value):
        self._value = value
        self._num_attached = 0
    @property
    def value(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._value
    @value.setter
    def value(self, int value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef bint changed = value != self._value
        self._value = value
        self.on_update(changed)
    cdef int get(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        return self._value
    cdef void set(self, int value) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef bint changed = value != self._value
        self._value = value
        self.on_update(changed)

cdef class SharedColor(SharedValue):
    def __init__(self, Context context, value):
        self._value = parse_color(value)
        self._value_asfloat4 = imgui.ColorConvertU32ToFloat4(self._value)
        self._num_attached = 0
    @property
    def value(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        "Color data is an int32 (rgba, little endian),\n" \
        "If you pass an array of int (r, g, b, a), or float\n" \
        "(r, g, b, a) normalized it will get converted automatically"
        return <int>self._value
    @value.setter
    def value(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._value = parse_color(value)
        self._value_asfloat4 = imgui.ColorConvertU32ToFloat4(self._value)
        self.on_update(True)
    cdef imgui.ImU32 getU32(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        return self._value
    cdef imgui.ImVec4 getF4(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        return self._value_asfloat4
    cdef void setU32(self, imgui.ImU32 value) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self._value = value
        self._value_asfloat4 = imgui.ColorConvertU32ToFloat4(self._value)
        self.on_update(True)
    cdef void setF4(self, imgui.ImVec4 value) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self._value_asfloat4 = value
        self._value = imgui.ColorConvertFloat4ToU32(self._value_asfloat4)
        self.on_update(True)

cdef class SharedDouble(SharedValue):
    def __init__(self, Context context, double value):
        self._value = value
        self._num_attached = 0
    @property
    def value(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._value
    @value.setter
    def value(self, double value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef bint changed = value != self._value
        self._value = value
        self.on_update(changed)
    cdef double get(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        return self._value
    cdef void set(self, double value) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef bint changed = value != self._value
        self._value = value
        self.on_update(changed)

cdef class SharedStr(SharedValue):
    def __init__(self, Context context, str value):
        self._value = bytes(str(value), 'utf-8')
        self._num_attached = 0
    @property
    def value(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return str(self._value, encoding='utf-8')
    @value.setter
    def value(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._value = bytes(str(value), 'utf-8')
        self.on_update(True)
    cdef void get(self, string& out) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        out = self._value
    cdef void set(self, string value) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self._value = value
        self.on_update(True)

cdef class SharedFloat4(SharedValue):
    def __init__(self, Context context, value):
        read_point[float](self._value, value)
        self._num_attached = 0
    @property
    def value(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return list(self._value)
    @value.setter
    def value(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        read_point[float](self._value, value)
        self.on_update(True)
    cdef void get(self, float *dst) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        dst[0] = self._value[0]
        dst[1] = self._value[1]
        dst[2] = self._value[2]
        dst[3] = self._value[3]
    cdef void set(self, float[4] value) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self._value[0] = value[0]
        self._value[1] = value[1]
        self._value[2] = value[2]
        self._value[3] = value[3]
        self.on_update(True)

cdef class SharedInt4(SharedValue):
    def __init__(self, Context context, value):
        read_point[int](self._value, value)
        self._num_attached = 0
    @property
    def value(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return list(self._value)
    @value.setter
    def value(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        read_point[int](self._value, value)
        self.on_update(True)
    cdef void get(self, int *dst) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        dst[0] = self._value[0]
        dst[1] = self._value[1]
        dst[2] = self._value[2]
        dst[3] = self._value[3]
    cdef void set(self, int[4] value) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self._value[0] = value[0]
        self._value[1] = value[1]
        self._value[2] = value[2]
        self._value[3] = value[3]
        self.on_update(True)

cdef class SharedDouble4(SharedValue):
    def __init__(self, Context context, value):
        read_point[double](self._value, value)
    @property
    def value(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return list(self._value)
    @value.setter
    def value(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        read_point[double](self._value, value)
        self.on_update(True)
    cdef void get(self, double *dst) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        dst[0] = self._value[0]
        dst[1] = self._value[1]
        dst[2] = self._value[2]
        dst[3] = self._value[3]
    cdef void set(self, double[4] value) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self._value[0] = value[0]
        self._value[1] = value[1]
        self._value[2] = value[2]
        self._value[3] = value[3]
        self.on_update(True)

cdef class SharedFloatVect(SharedValue):
    def __init__(self, Context context, value):
        self._value = value
    @property
    def value(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if self._value_np is None:
            return None
        return np.copy(self._value)
    @value.setter
    def value(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._value_np = np.array(value, dtype=np.float32)
        self._value = self._value_np
        self.on_update(True)
    cdef float[:] get(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        return self._value
    cdef void set(self, float[:] value) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self._value = value
        self.on_update(True)

"""
cdef class SharedDoubleVect:
    cdef double[:] value
    cdef double[:] get(self) noexcept nogil
    cdef void set(self, double[:]) noexcept nogil

cdef class SharedTime:
    cdef tm value
    cdef tm get(self) noexcept nogil
    cdef void set(self, tm) noexcept nogil
"""

"""
UI elements
"""

"""
UI styles
"""


"""
UI input event handlers
"""

cdef class baseHandler(baseItem):
    def __cinit__(self):
        self.enabled = True
        self.can_have_sibling = True
        self.element_child_category = child_type.cat_handler
    @property
    def enabled(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.enabled
    @enabled.setter
    def enabled(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.enabled = value
    # for backward compatibility
    @property
    def show(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.enabled
    @show.setter
    def show(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.enabled = value

    @property
    def callback(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.callback
    @callback.setter
    def callback(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.callback = value if isinstance(value, Callback) or value is None else Callback(value)

    cdef void check_bind(self, baseItem item, itemState &state):
        """
        Must raise en error if the handler cannot be bound for the
        target item. We pass both item and state because
        state might not be positioned at the same space for all
        items, thus it is better to rely on state for the checks.
        However to allow subclassing handlers, having item enables
        to check for specific target classes and read fields that
        are not in itemState.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if self._prev_sibling is not None:
            (<baseHandler>self._prev_sibling).check_bind(item, state)

    cdef bint check_state(self, baseItem item, itemState &state) noexcept nogil:
        """
        Returns whether the target state it True.
        Is called by the default implementation of run_handler,
        which will call the default callback in this case.
        Classes that might issue non-standard callbacks should
        override run_handler in addition to check_state.
        """
        return False

    cdef void run_handler(self, baseItem item, itemState &state) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        if self._prev_sibling is not None:
            (<baseHandler>self._prev_sibling).run_handler(item, state)
        if not(self.enabled):
            return
        if self.check_state(item, state):
            self.run_callback(item)

    cdef void run_callback(self, baseItem item) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        self.context.queue_callback_arg1obj(self.callback, self, item)

cdef class HandlerList(baseHandler):
    """
    A list of handlers in order to attach several
    handlers to an item.
    In addition if you attach a callback to this handler,
    it will be issued if ALL or ANY of the children handler
    states are met. NONE is also possible.
    Note however that the handlers are not checked if an item
    is not rendered. This corresponds to the visible state.
    """
    def __cinit__(self):
        self.can_have_handler_child = True
        self._op = handlerListOP.ANY

    @property
    def op(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._op

    def op(self, handlerListOP value):
        if value not in [handlerListOP.ALL, handlerListOP.ANY, handlerListOP.NONE]:
            raise ValueError("Unknown op")
        self._op = value

    cdef void check_bind(self, baseItem item, itemState &state):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if self._prev_sibling is not None:
            (<baseHandler>self._prev_sibling).check_bind(item, state)
        if self.last_handler_child is not None:
            (<baseHandler>self.last_handler_child).check_bind(item, state)

    cdef bint check_state(self, baseItem item, itemState &state) noexcept nogil:
        """
        Returns whether the target state it True.
        Is called by the default implementation of run_handler,
        which will call the default callback in this case.
        Classes that might issue non-standard callbacks should
        override run_handler in addition to check_state.
        """
        if self.last_handler_child is None:
            return False
        self.last_handler_child.lock_and_previous_siblings()
        # We use PyObject to avoid refcounting and thus the gil
        cdef PyObject* child = <PyObject*>self.last_handler_child
        cdef bint current_state = False
        cdef bint child_state
        if self._op == handlerListOP.ALL:
            current_state = True
        while child is not <PyObject*>None:
            child_state = (<baseHandler>child).check_state(item, state)
            child = <PyObject*>((<baseHandler>child).last_handler_child)
            if not((<baseHandler>child).enabled):
                continue
            if self._op == handlerListOP.ALL:
                current_state = current_state and child_state
            else:
                current_state = current_state or child_state
        if self._op == handlerListOP.NONE:
            # NONE = not(ANY)
            current_state = not(current_state)
        self.last_handler_child.unlock_and_previous_siblings()
        return False

    cdef void run_handler(self, baseItem item, itemState &state) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        if self._prev_sibling is not None:
            (<baseHandler>self._prev_sibling).run_handler(item, state)
        if not(self.enabled):
            return
        if self.last_handler_child is not None:
            (<baseHandler>self.last_handler_child).run_handler(item, state)
        if self.callback is not None:
            if self.check_state(item, state):
                self.run_callback(item)

cdef inline object IntPairFromVec2(imgui.ImVec2 v):
    return (<int>v.x, <int>v.y)

cdef class uiItem(baseItem):
    def __cinit__(self):
        # mvAppItemInfo
        self.imgui_label = b'###%ld'% self.uuid
        self.user_label = ""
        self._show = True
        self._enabled = True
        self.can_be_disabled = False
        #self.location = -1
        # next frame triggers
        self.focus_update_requested = False
        self.show_update_requested = False
        self.size_update_requested = True
        self.pos_update_requested = False
        self.enabled_update_requested = False
        self.last_frame_update = 0 # last frame update occured
        # mvAppItemConfig
        #self.filter = b""
        #self.alias = b""
        self.payloadType = b"$$DPG_PAYLOAD"
        self.requested_size = imgui.ImVec2(0., 0.)
        self._indent = 0.
        self.theme_condition_enabled = theme_enablers.t_enabled_any
        self.theme_condition_category = theme_categories.t_any
        self.can_have_sibling = True
        self.element_child_category = child_type.cat_widget
        #self.trackOffset = 0.5 # 0.0f:top, 0.5f:center, 1.0f:bottom
        #self.tracked = False
        self.dragCallback = None
        self.dropCallback = None
        self._value = SharedValue(self.context) # To be changed by class

    def configure(self, **kwargs):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        # Convert old names to new attributes
        if "min_size" in kwargs:
            self.rect_min = kwargs.pop("min_size")
        if "max_size" in kwargs:
            self.rect_max = kwargs.pop("max_size")
        super().configure(**kwargs)

    cdef void update_current_state(self) noexcept nogil:
        """
        Updates the state of the last imgui object.
        """
        if self.state.can_be_hovered:
            self.state.hovered = imgui.IsItemHovered(imgui.ImGuiHoveredFlags_None)
        if self.state.can_be_active:
            self.state.active = imgui.IsItemActive()
        if self.state.can_be_activated:
            self.state.activated = imgui.IsItemActivated()
        cdef int i
        if self.state.can_be_clicked:
            for i in range(<int>imgui.ImGuiMouseButton_COUNT):
                self.state.clicked[i] = self.state.hovered and imgui.IsItemClicked(i)
                self.state.double_clicked[i] = self.state.hovered and imgui.IsMouseDoubleClicked(i)
        if self.state.can_be_deactivated:
            self.state.deactivated = imgui.IsItemDeactivated()
        if self.state.can_be_deactivated_after_edited:
            self.state.deactivated_after_edited = imgui.IsItemDeactivatedAfterEdit()
        if self.state.can_be_edited:
            self.state.edited = imgui.IsItemEdited()
        if self.state.can_be_focused:
            self.state.focused = imgui.IsItemFocused()
        if self.state.can_be_toggled:
            self.state.toggled = imgui.IsItemToggledOpen()
        if self.state.has_rect_min:
            self.state.rect_min = imgui.GetItemRectMin()
        if self.state.has_rect_max:
            self.state.rect_max = imgui.GetItemRectMax()
        cdef imgui.ImVec2 rect_size
        if self.state.has_rect_size:
            rect_size = imgui.GetItemRectSize()
            self.state.resized = rect_size.x != self.state.rect_size.x or \
                                 rect_size.y != self.state.rect_size.y
            self.state.rect_size = rect_size
        if self.state.has_content_region:
            self.state.content_region = imgui.GetContentRegionAvail()
        self.state.visible = imgui.IsItemVisible()

    cdef void update_current_state_as_hidden(self) noexcept nogil:
        """
        Indicates the object is hidden
        """
        self.state.hovered = False
        self.state.active = False
        self.state.activated = False
        cdef int i
        if self.state.can_be_clicked:
            for i in range(<int>imgui.ImGuiMouseButton_COUNT):
                self.state.clicked[i] = False
                self.state.double_clicked[i] = False
        self.state.deactivated = False
        self.state.deactivated_after_edited = False
        self.state.edited = False
        self.state.focused = False
        self.state.toggled = False
        self.state.resized = False
        self.state.visible = False

    cpdef object output_current_item_state(self):
        """
        Helper function to return the current dict of item state
        """
        output = {}
        if self.state.can_be_hovered:
            output["hovered"] = self.state.hovered
        if self.state.can_be_active:
            output["active"] = self.state.active
        if self.state.can_be_activated:
            output["activated"] = self.state.activated
        if self.state.can_be_clicked:
            output["clicked"] = max(self.state.clicked)
            output["left_clicked"] = self.state.clicked[0]
            output["middle_clicked"] = self.state.clicked[2]
            output["right_clicked"] = self.state.clicked[1]
        if self.state.can_be_deactivated:
            output["deactivated"] = self.state.deactivated
        if self.state.can_be_deactivated_after_edited:
            output["deactivated_after_edit"] = self.state.deactivated_after_edited
        if self.state.can_be_edited:
            output["edited"] = self.state.edited
        if self.state.can_be_focused:
            output["focused"] = self.state.focused
        if self.state.can_be_toggled:
            output["toggle_open"] = self.state.toggled
        if self.state.has_rect_min:
            output["rect_min"] = IntPairFromVec2(self.state.rect_min)
        if self.state.has_rect_max:
            output["rect_max"] = IntPairFromVec2(self.state.rect_max)
        if self.state.has_rect_size:
            output["rect_size"] = IntPairFromVec2(self.state.rect_size)
            output["resized"] = self.state.resized
        if self.state.has_content_region:
            output["content_region_avail"] = IntPairFromVec2(self.state.content_region)
        output["ok"] = True # Original code only set this to False on missing texture or invalid style
        output["visible"] = self.state.visible
        output["pos"] = (self._relative_position.x, self._relative_position.y)
        return output

    cdef void propagate_hidden_state_to_children(self) noexcept nogil:
        """
        The item is hidden (closed window, etc).
        Propagate the hidden state to children
        """
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        if self.last_widgets_child is not None:
            self.last_widgets_child.set_hidden_and_propagate()

    cdef void set_hidden_and_propagate(self) noexcept nogil:
        """
        A parent item is hidden. Propagate to children and siblings
        """
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        if self.last_widgets_child is not None:
            self.last_widgets_child.set_hidden_and_propagate()
        if self._prev_sibling is not None:
            (<uiItem>self._prev_sibling).set_hidden_and_propagate()
        self.update_current_state_as_hidden()

    # TODO: Find a better way to share all these attributes while avoiding AttributeError

    @property
    def active(self):
        """
        Readonly attribute: is the item active
        """
        if not(self.state.can_be_active):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.active

    @property
    def activated(self):
        """
        Readonly attribute: has the item just turned active
        If True, the attribute is reset the next frame. It's better to rely
        on handlers to catch this event.
        """
        if not(self.state.can_be_activated):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.activated

    @property
    def clicked(self):
        """
        Readonly attribute: has the item just been clicked.
        The returned value is a tuple of len 5 containing the individual test
        mouse buttons (up to 5 buttons)
        If True, the attribute is reset the next frame. It's better to rely
        on handlers to catch this event.
        """
        if not(self.state.can_be_clicked):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return tuple(self.state.clicked)

    @property
    def double_clicked(self):
        """
        Readonly attribute: has the item just been double-clicked.
        The returned value is a tuple of len 5 containing the individual test
        mouse buttons (up to 5 buttons)
        If True, the attribute is reset the next frame. It's better to rely
        on handlers to catch this event.
        """
        if not(self.state.can_be_clicked):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.double_clicked

    @property
    def deactivated(self):
        """
        Readonly attribute: has the item just turned un-active
        If True, the attribute is reset the next frame. It's better to rely
        on handlers to catch this event.
        """
        if not(self.state.can_be_deactivated):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.deactivated

    @property
    def deactivated_after_edited(self):
        """
        Readonly attribute: has the item just turned un-active after having
        been edited.
        If True, the attribute is reset the next frame. It's better to rely
        on handlers to catch this event.
        """
        if not(self.state.can_be_deactivated_after_edited):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.deactivated_after_edited

    @property
    def edited(self):
        """
        Readonly attribute: has the item just been edited
        If True, the attribute is reset the next frame. It's better to rely
        on handlers to catch this event.
        """
        if not(self.state.can_be_edited):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.edited

    @property
    def focused(self):
        """
        Writable attribute: Is the item focused ?
        For windows it means the window is at the top,
        while for items it could mean the keyboard inputs are redirected to it.
        """
        if not(self.state.can_be_focused):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.focused

    @focused.setter
    def focused(self, bint value):
        """
        Writable attribute: Is the item focused ?
        For windows it means the window is at the top,
        while for items it could mean the keyboard inputs are redirected to it.
        """
        if not(self.state.can_be_focused):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.state.focused = value
        self.focus_update_requested = True

    @property
    def hovered(self):
        """
        Readonly attribute: Is the mouse inside the region of the item.
        Only one element is hovered at a time, thus
        subitems/subwindows take priority over their parent.
        """
        if not(self.state.can_be_hovered):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.hovered

    @property
    def resized(self):
        """
        Readonly attribute: has the item size just changed
        If True, the attribute is reset the next frame. It's better to rely
        on handlers to catch this event.
        """
        if not(self.state.has_rect_size):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.resized

    @property
    def toggled(self):
        """
        Has a menu/bar trigger been hit for the item
        If True, the attribute is reset the next frame. It's better to rely
        on handlers to catch this event.
        """
        if not(self.state.can_be_toggled):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.toggled

    @property
    def visible(self):
        """
        True if the item was rendered (inside the rendering region + show = True
        for the item and its ancestors). Not impacted by occlusion.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.visible

    @property
    def content_region_avail(self):
        """
        Region available for the current element size if scrolling was disallowed
        """
        if not(self.state.has_content_region):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return IntPairFromVec2(self.state.content_region)

    @property
    def rect_min(self):
        """
        Requested minimum size (width, height) allowed for the item.
        Writable attribute
        """
        if not(self.state.has_rect_min):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return IntPairFromVec2(self.state.rect_min)

    @rect_min.setter
    def rect_min(self, value):
        if not(self.state.has_rect_min):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        if len(value) != 2:
            raise ValueError("Expected tuple for rect_min: (width, height)")
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.state.rect_min.x = value[0]
        self.state.rect_min.y = value[1]

    @property
    def rect_max(self):
        """
        Requested minimum size (width, height) allowed for the item.
        Writable attribute
        """
        if not(self.state.has_rect_max):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return IntPairFromVec2(self.state.rect_max)

    @rect_max.setter
    def rect_max(self, value):
        if not(self.state.has_rect_max):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        if len(value) != 2:
            raise ValueError("Expected tuple for rect_max: (width, height)")
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.state.rect_max.x = value[0]
        self.state.rect_max.y = value[1]

    @property
    def rect_size(self):
        """
        Readonly attribute: actual (width, height) of the element
        """
        if not(self.state.has_rect_size):
            raise AttributeError("Field undefined for type {}".format(type(self)))
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return IntPairFromVec2(self.state.rect_size)

    @property
    def callback(self):
        """
        Writable attribute: callback object which is called when the value
        of the item is changed
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._callback

    @callback.setter
    def callback(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._callback = value if isinstance(value, Callback) or value is None else Callback(value)

    @property
    def enabled(self):
        """
        Writable attribute: Should the object be displayed as enabled ?
        the enabled state can be used to prevent edition of editable fields,
        or to use a specific disabled element theme.
        Note a disabled item is still rendered. Use show=False to hide
        an object.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._enabled
    @enabled.setter
    def enabled(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if not(self.can_be_disabled) and value != True:
            raise AttributeError(f"Objects of type {type(self)} cannot be disabled")
        self.theme_condition_enabled = theme_enablers.t_enabled_True if value else theme_enablers.t_enabled_False
        self.enabled_update_requested = True
        self._enabled = value

    @property
    def height(self):
        """
        Writable attribute: requested height of the item.
        When it is written, it is set to a 'requested value' that is not
        entirely guaranteed to be enforced.
        Specific values:
            . Windows: 0 means fit to take the maximum size available
            . Some Items: <0. means align of ... pixels to the right of the window
            . Some Items: 0 can mean use remaining space or fit to content 
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return <int>self.requested_size.y

    @height.setter
    def height(self, int value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.requested_size.y = <float>value
        self.state.rect_size.y = <float>value
        self.size_update_requested = True

    @property
    def indent(self):
        """
        Writable attribute: requested indentation relative to the parent of the item.
        (No effect on top-level windows)
        0 means no indentation.
        Negative value means use an indentation of the default width.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._indent

    @indent.setter
    def indent(self, int value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._indent = value

    @property
    def label(self):
        """
        Writable attribute: label assigned to the item.
        Used for text fields, window titles, etc
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.user_label
    @label.setter
    def label(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if value is None:
            self.user_label = ""
        else:
            self.user_label = value
        # Using ### means that imgui will ignore the user_label for
        # its internal ID of the object. Indeed else the ID would change
        # when the user label would change
        self.imgui_label = bytes(self.user_label, 'utf-8') + b'###%ld'% self.uuid

    @property
    def pos(self):
        """
        Writable attribute: Relative position (x, y) of the element inside
        the drawable region of the parent.
        Setting a value will override the default position, while
        setting an empty value will reset to the default position next
        time the object is drawn.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return IntPairFromVec2(self._relative_position)

    @pos.setter
    def pos(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if value is None or len(value) == 0:
            # Used to indicate "keep default value" during init
            self.pos_update_requested = False # Reset to default position for items
            return
        if len(value) != 2:
            raise ValueError("Expected tuple for pos: (x, y)")
        self._relative_position.x = value[0]
        self._relative_position.y = value[1]
        self.pos_update_requested = True

    @property
    def absolute_pos(self):
        """
        Readable attribute:
        Last screen position of the top left corner of the
        item.
        If the item is not visible, may or may not be updated,
        and thus may be outside the screen.
        Useful when manipulating mouse coordinates.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return IntPairFromVec2(self._absolute_position)

    @property
    def value(self):
        """
        Writable attribute: main internal value for the object.
        For buttons, it is set when pressed; For text it is the
        text itself; For selectable whether it is selected, etc.
        Reading the value attribute returns a copy, while writing
        to the value attribute will edit the field of the value.
        In case the value is shared among items, setting the value
        attribute will change it for all the sharing items.
        To share a value attribute among objects, one should use
        the shareable_value attribute
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._value.value

    @value.setter
    def value(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._value.value = value

    @property
    def shareable_value(self):
        """
        Same as the value field, but rather than a copy of the internal value
        of the object, return a python object that holds a value field that
        is in sync with the internal value of the object. This python object
        can be passed to other items using an internal value of the same
        type to share it.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._value

    @shareable_value.setter
    def shareable_value(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if self._value is value:
            return
        if type(self._value) is not type(value):
            raise ValueError(f"Expected a shareable value of type {type(self._value)}. Received {type(value)}")
        self._value.dec_num_attached()
        self._value = value
        self._value.inc_num_attached()

    @property
    def show(self):
        """
        Writable attribute: Should the object be drawn/shown ?
        In case show is set to False, this disables any
        callback (for example the close callback won't be called
        if a window is hidden with show = False).
        In the case of items that can be closed,
        show is set to False automatically on close.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return <bint>self._show
    @show.setter
    def show(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.show_update_requested = True
        self._show = value

    @property
    def handler(self):
        """
        Writable attribute: bound handler for the item.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._handler

    @handler.setter
    def handler(self, baseHandler value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        # Check the list of handlers can use our states. Else raise error
        value.check_bind(self, self.state)
        # yes: bind
        self._handler = value

    @property
    def theme(self):
        """
        Writable attribute: bound theme for the item
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._theme

    @theme.setter
    def theme(self, baseTheme value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._theme = value

    @property
    def width(self):
        """
        Writable attribute: requested width of the item.
        When it is written, it is set to a 'requested value' that is not
        entirely guaranteed to be enforced
        Specific values:
            . Windows: 0 means fit to take the maximum size available
            . Some Items: <0. means align of ... pixels to the right of the window
            . Some Items: 0 can mean use remaining space or fit to content 
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return <int>self.requested_size.x

    @width.setter
    def width(self, int value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.requested_size.x = <float>value
        self.state.rect_size.x = <float>value
        self.size_update_requested = True

    cdef void draw(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        if self._prev_sibling is not None:
            (<uiItem>self._prev_sibling).draw()

        if not(self._show):
            if self.show_update_requested:
                self.set_hidden_and_propagate()
                self.show_update_requested = False
            return

        if self.focus_update_requested:
            if self.state.focused:
                imgui.SetKeyboardFocusHere(0)
            self.focus_update_requested = False

        # Does not affect all items, but is cheap to set
        if self.requested_size.x != 0:
            imgui.SetNextItemWidth(self.requested_size.x)

        # If the position is user set, it would probably
        # make more sense to apply indent after (else it will
        # have not effect, and thus is likely not the expected behaviour).
        # However this will shift relative_position, updated by
        # update_current_state. If needed we could restore relative_position ?
        # For now make the indent have no effect when the position is set
        if self._indent != 0.:
            imgui.Indent(self._indent)

        cdef ImVec2 cursor_pos_backup
        if self.pos_update_requested:
            cursor_pos_backup = imgui.GetCursorPos()
            imgui.SetCursorPos(self._relative_position)
            # Never reset self.pos_update_requested as we always
            # need to set at the requested position 
        else:
            self._relative_position = imgui.GetCursorPos()
        self._absolute_position = imgui.GetCursorScreenPos()

        # handle fonts
        """
        if self.font:
            ImFont* fontptr = static_cast<mvFont*>(item.font.get())->getFontPtr();
            ImGui::PushFont(fontptr);
        """

        # themes
        self.context.viewport.push_pending_theme_actions(
            self.theme_condition_enabled,
            self.theme_condition_category
        )
        if self._theme is not None:
            self._theme.push()

        cdef bint action = self.draw_item()
        if action:
            self.context.queue_callback_arg1value(self._callback, self, self._value)

        if self._theme is not None:
            self._theme.pop()
        self.context.viewport.pop_applied_pending_theme_actions()

        if self.pos_update_requested:
            imgui.SetCursorPos(cursor_pos_backup)

        if self._indent != 0.:
            imgui.Unindent(self._indent)

        if self._handler is not None:
            self._handler.run_handler(self, self.state)


    cdef bint draw_item(self) noexcept nogil:
        """
        Function to override for the core rendering of the item.
        What is already handled outside draw_item (see draw()):
        . The mutex is held (as is the mutex of the following siblings,
          and the mutex of the parents, including the viewport and imgui
          mutexes)
        . The previous siblings are already rendered
        . Current themes, fonts
        . Widget starting position (GetCursorPos to get it)
        . Focus

        What remains to be done by draw_item:
        . Rendering the item. Set its width, its height, etc
        . Calling update_current_state or manage itself the state
        . Render children if any

        The return value indicates if the main callback should be triggered.
        """
        return False

"""
Simple ui items
"""

cdef class SimplePlot(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_simpleplot
        self._value = <SharedValue>(SharedFloatVect.__new__(SharedFloatVect, self.context))
        self.state.can_be_activated = True
        self.state.can_be_active = True
        self.state.can_be_clicked = True
        self.state.can_be_deactivated = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        self.state.has_rect_min = True
        self.state.has_rect_max = True
        self.state.has_rect_size = True
        self.state.has_content_region = True
        self._scale_min = 0.
        self._scale_max = 0.
        self.histogram = False
        self._autoscale = True
        self.last_frame_autoscale_update = -1

    def configure(self, **kwargs):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        # Map old attribute names (the new names are handled in uiItem)
        self._scale_min = kwargs.pop("scaleMin", self._scale_min)
        self._scale_max = kwargs.pop("scaleMax", self._scale_max)
        self._autoscale = kwargs.pop("autosize", self._autoscale)
        return super().configure(**kwargs)

    @property
    def scale_min(self):
        """
        Writable attribute: value corresponding to the minimum value of plot scale
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._scale_min

    @scale_min.setter
    def scale_min(self, float value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._scale_min = value

    @property
    def scale_max(self):
        """
        Writable attribute: value corresponding to the maximum value of plot scale
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._scale_max

    @scale_max.setter
    def scale_max(self, float value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._scale_max = value

    @property
    def histogram(self):
        """
        Writable attribute: Whether the data should be plotted as an histogram
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._histogram

    @histogram.setter
    def histogram(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._histogram = value

    @property
    def autoscale(self):
        """
        Writable attribute: Whether scale_min and scale_max should be deduced
        from the data
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._autoscale

    @autoscale.setter
    def autoscale(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._autoscale = value

    @property
    def overlay(self):
        """
        Writable attribute: Overlay text
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._overlay

    @overlay.setter
    def overlay(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._overlay = bytes(str(value), 'utf-8')

    cdef bint draw_item(self) noexcept nogil:
        cdef float[:] data = SharedFloatVect.get(<SharedFloatVect>self._value)
        cdef int i
        if self._autoscale and data.shape[0] > 0:
            if self._value._last_frame_change != self.last_frame_autoscale_update:
                self.last_frame_autoscale_update = self._value._last_frame_change
                self._scale_min = data[0]
                self._scale_max = data[0]
                for i in range(1, data.shape[0]):
                    if self._scale_min > data[i]:
                        self._scale_min = data[i]
                    if self._scale_max < data[i]:
                        self._scale_max = data[i]

        if self._histogram:
            imgui.PlotHistogram(self.imgui_label.c_str(),
                                &data[0],
                                <int>data.shape[0],
                                0,
                                self._overlay.c_str(),
                                self._scale_min,
                                self._scale_max,
                                self.requested_size,
                                sizeof(float))
        else:
            imgui.PlotLines(self.imgui_label.c_str(),
                            &data[0],
                            <int>data.shape[0],
                            0,
                            self._overlay.c_str(),
                            self._scale_min,
                            self._scale_max,
                            self.requested_size,
                            sizeof(float))
        self.update_current_state()
        return False

cdef class Button(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_button
        self._value = <SharedValue>(SharedBool.__new__(SharedBool, self.context))
        self.state.can_be_activated = True
        self.state.can_be_active = True
        self.state.can_be_clicked = True
        self.state.can_be_deactivated = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        #self.state.has_rect_min = True
        #self.state.has_rect_max = True
        #self.state.has_rect_size = True
        #self.state.has_content_region = True
        self._direction = imgui.ImGuiDir_Up
        self._small = False
        self._arrow = False
        self._repeat = False

    @property
    def direction(self):
        """
        Writable attribute: Direction of the arrow if any
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return <int>self._direction

    @direction.setter
    def direction(self, int value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if value < imgui.ImGuiDir_None or value >= imgui.ImGuiDir_COUNT:
            raise ValueError("Invalid direction {value}")
        self._direction = <imgui.ImGuiDir>value

    @property
    def small(self):
        """
        Writable attribute: Whether to display a small button
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._small

    @small.setter
    def small(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._small = value

    @property
    def arrow(self):
        """
        Writable attribute: Whether to display an arrow.
        Not compatible with small
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._arrow

    @arrow.setter
    def arrow(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._arrow = value

    @property
    def repeat(self):
        """
        Writable attribute: Whether to generate many clicked events
        when the button is held repeatedly, instead of a single.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._repeat

    @repeat.setter
    def repeat(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._repeat = value

    cdef bint draw_item(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef bint activated
        imgui.PushItemFlag(imgui.ImGuiItemFlags_ButtonRepeat, self._repeat)
        if self._small:
            activated = imgui.SmallButton(self.imgui_label.c_str())
        elif self._arrow:
            activated = imgui.ArrowButton(self.imgui_label.c_str(), self._direction)
        else:
            activated = imgui.Button(self.imgui_label.c_str(),
                                     self.requested_size)
        imgui.PopItemFlag()
        self.update_current_state()
        SharedBool.set(<SharedBool>self._value, self.state.active) # Unsure. Not in original
        return activated


cdef class Combo(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_combo
        self._value = <SharedValue>(SharedStr.__new__(SharedStr, self.context))
        self.state.can_be_activated = True
        self.state.can_be_active = True
        self.state.can_be_clicked = True
        self.state.can_be_deactivated = True
        self.state.can_be_deactivated_after_edited = True
        self.state.can_be_edited = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        # Frankly unsure why these. Should it include popup ?:
        #self.state.has_rect_min = True
        #self.state.has_rect_max = True
        #self.state.has_rect_size = True
        #self.state.has_content_region = True
        self.flags = imgui.ImGuiComboFlags_HeightRegular

    @property
    def items(self):
        """
        Writable attribute: List of text values to select
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return [str(v, encoding='utf-8') for v in self._items]

    @items.setter
    def items(self, value):
        cdef unique_lock[recursive_mutex] m
        cdef unique_lock[recursive_mutex] value_m
        lock_gil_friendly(m, self.mutex)
        self._items.clear()
        if value is None:
            return
        if value is str:
            self._items.push_back(bytes(value, 'utf-8'))
        elif hasattr(value, '__len__'):
            for v in value:
                self._items.push_back(bytes(v, 'utf-8'))
        else:
            raise ValueError(f"Invalid type {type(value)} passed as items. Expected array of strings")
        lock_gil_friendly(value_m, self._value.mutex)
        if self._value.num_attached == 1 and \
           self._value._last_frame_update == -1 and \
           self._items.size() > 0:
            # initialize the value with the first element
            SharedStr.set(<SharedStr>self._value, self._items[0])

    @property
    def height_mode(self):
        """
        Writable attribute: height mode of the combo.
        Supported values are
        "small"
        "regular"
        "large"
        "largest"
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if (self.flags & imgui.ImGuiComboFlags_HeightSmall) != 0:
            return "small"
        elif (self.flags & imgui.ImGuiComboFlags_HeightLargest) != 0:
            return "largest"
        elif (self.flags & imgui.ImGuiComboFlags_HeightLarge) != 0:
            return "large"
        return "regular"

    @height_mode.setter
    def height_mode(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~(imgui.ImGuiComboFlags_HeightSmall |
                        imgui.ImGuiComboFlags_HeightRegular |
                        imgui.ImGuiComboFlags_HeightLarge |
                        imgui.ImGuiComboFlags_HeightLargest)
        if value == "small":
            self.flags |= imgui.ImGuiComboFlags_HeightSmall
        elif value == "regular":
            self.flags |= imgui.ImGuiComboFlags_HeightRegular
        elif value == "large":
            self.flags |= imgui.ImGuiComboFlags_HeightLarge
        elif value == "largest":
            self.flags |= imgui.ImGuiComboFlags_HeightLargest
        else:
            self.flags |= imgui.ImGuiComboFlags_HeightRegular
            raise ValueError("Invalid height mode {value}")

    @property
    def popup_align_left(self):
        """
        Writable attribute: Whether to align left
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiComboFlags_PopupAlignLeft) != 0

    @popup_align_left.setter
    def popup_align_left(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiComboFlags_PopupAlignLeft
        if value:
            self.flags |= imgui.ImGuiComboFlags_PopupAlignLeft

    @property
    def no_arrow_button(self):
        """
        Writable attribute: Whether the combo should not display an arrow on top
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiComboFlags_NoArrowButton) != 0

    @no_arrow_button.setter
    def no_arrow_button(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiComboFlags_NoArrowButton
        if value:
            self.flags |= imgui.ImGuiComboFlags_NoArrowButton

    @property
    def no_preview(self):
        """
        Writable attribute: Whether the preview should be disabled
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiComboFlags_NoPreview) != 0

    @no_preview.setter
    def no_preview(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiComboFlags_NoPreview
        if value:
            self.flags |= imgui.ImGuiComboFlags_NoPreview

    @property
    def fit_width(self):
        """
        Writable attribute: Whether the combo should fit available width
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiComboFlags_WidthFitPreview) != 0

    @fit_width.setter
    def fit_width(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiComboFlags_WidthFitPreview
        if value:
            self.flags |= imgui.ImGuiComboFlags_WidthFitPreview

    cdef bint draw_item(self) noexcept nogil:
        cdef bint open
        cdef int i
        cdef string current_value
        SharedStr.get(<SharedStr>self._value, current_value)
        open = imgui.BeginCombo(self.imgui_label.c_str(),
                                current_value.c_str(),
                                self.flags)
        # Old code called update_current_state now, and updated edited state
        # later. Looking at ImGui code there seems to be two items. One
        # for the combo, and one for the popup that opens. The edited flag
        # is not set, looking at imgui demo so we have to handle it manually.
        self.state.activated = not(self.state.active) and open
        self.state.deactivated = self.state.active and not(open)
        self.state.active = open
        self.state.can_be_deactivated = True
        self.state.can_be_deactivated_after_edited = True
        self.state.can_be_edited = True
        self.state.focused = imgui.IsItemFocused()
        self.state.hovered = imgui.IsItemHovered(imgui.ImGuiHoveredFlags_None)
        for i in range(<int>imgui.ImGuiMouseButton_COUNT):
            self.state.clicked[i] = self.state.hovered and imgui.IsItemClicked(i)
            self.state.double_clicked[i] = self.state.hovered and imgui.IsMouseDoubleClicked(i)


        cdef bool pressed = False
        cdef bint changed = False
        cdef bool selected
        cdef bool selected_backup
        # we push an ID because we didn't append ###uuid to the items
        
        # TODO: there are nice ImGuiSelectableFlags to add in the future
        if open:
            imgui.PushID(self.uuid)
            if self._enabled:
                for i in range(<int>self._items.size()):
                    selected = self._items[i] == current_value
                    selected_backup = selected
                    pressed |= imgui.Selectable(self._items[i].c_str(),
                                                &selected,
                                                imgui.ImGuiSelectableFlags_None,
                                                self.requested_size)
                    if selected:
                        imgui.SetItemDefaultFocus()
                    if selected and selected != selected_backup:
                        changed = True
                        SharedStr.set(<SharedStr>self._value, self._items[i])
            else:
                # TODO: test
                selected = True
                imgui.Selectable(current_value.c_str(),
                                 &selected,
                                 imgui.ImGuiSelectableFlags_Disabled,
                                 self.requested_size)
            imgui.PopID()
            imgui.EndCombo()
        # TODO: rect_size/min/max: with the popup ? Use clipper for rect_max ?
        self.state.edited = changed
        self.state.deactivated_after_edited = self.state.deactivated and changed
        return pressed


cdef class Checkbox(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_checkbox
        self._value = <SharedValue>(SharedBool.__new__(SharedBool, self.context))
        self.state.can_be_activated = True
        self.state.can_be_clicked = True
        self.state.can_be_deactivated = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        self.can_be_disabled = True
        self.theme_condition_enabled = theme_enablers.t_enabled_True
        

    cdef bint draw_item(self) noexcept nogil:
        cdef bool checked = SharedBool.get(<SharedBool>self._value)
        cdef bint pressed = imgui.Checkbox(self.imgui_label.c_str(),
                                             &checked)
        if self._enabled:
            SharedBool.set(<SharedBool>self._value, checked)
        self.update_current_state()
        return pressed

cdef class Slider(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_slider
        self._format = 1
        self._size = 1
        self._drag = False
        self._drag_speed = 1.
        self._print_format = b"%.3f"
        self.flags = 0
        self._min = 0.
        self._max = 100.
        self._vertical = False
        self._value = <SharedValue>(SharedFloat.__new__(SharedFloat, self.context))
        self.state.can_be_active = True # unsure
        self.state.can_be_clicked = True
        self.state.can_be_edited = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        self.can_be_disabled = True
        self.theme_condition_enabled = theme_enablers.t_enabled_True

    def configure(self, **kwargs):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        # Since some options cancel each other, one
        # must enable them in a specific order
        if "format" in kwargs:
            self.format = kwargs.pop("format")
        if "size" in kwargs:
            self.size = kwargs.pop("size")
        if "logarithmic" in kwargs:
            self.logarithmic = kwargs.pop("logarithmic")
        # baseItem configure will configure the rest.
        return super().configure(**kwargs)

    @property
    def format(self):
        """
        Writable attribute: Format of the slider.
        Must be "int", "float" or "double".
        Note that float here means the 32 bits version.
        The python float corresponds to a double.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if self._format == 1:
            return "float"
        elif self._format == 0:
            return "int"
        return "double"

    @format.setter
    def format(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef int target_format
        if value == "int":
            target_format = 0
        elif value == "float":
            target_format = 1
        elif value == "double":
            target_format = 2
        else:
            raise ValueError(f"Expected 'int', 'float' or 'double'. Got {value}")
        if target_format == self._format:
            return
        self._format = target_format
        # Allocate a new value of the right type
        previous_value = self.value # Pass though the property to do the conversion for us
        if self._size == 1:
            if target_format == 0:
                self._value = <SharedValue>(SharedInt.__new__(SharedInt, self.context))
            elif target_format == 0:
                self._value = <SharedValue>(SharedFloat.__new__(SharedFloat, self.context))
            else:
                self._value = <SharedValue>(SharedDouble.__new__(SharedDouble, self.context))
        else:
            if target_format == 0:
                self._value = <SharedValue>(SharedInt4.__new__(SharedInt4, self.context))
            elif target_format == 0:
                self._value = <SharedValue>(SharedFloat4.__new__(SharedFloat4, self.context))
            else:
                self._value = <SharedValue>(SharedDouble4.__new__(SharedDouble4, self.context))
        self.value = previous_value # Use property to pass through python for the conversion
        self._print_format = b"%d" if target_format == 0 else b"%.3f"

    @property
    def size(self):
        """
        Writable attribute: Size of the slider.
        Can be 1, 2, 3 or 4.
        When 1 the item's value is held with
        a scalar shared value, else it is held
        with a vector of 4 elements (even for
        size 2 and 3)
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._size
        

    @size.setter
    def size(self, int target_size):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if target_size < 0 or target_size > 4:
            raise ValueError(f"Expected 1, 2, 3, or 4 for size. Got {target_size}")
        if self._size == target_size:
            return
        if (self._size > 1 and target_size > 1):
            self._size = target_size
            return
        # Reallocate the internal vector
        previous_value = self.value # Pass though the property to do the conversion for us
        if target_size == 1:
            if self._format == 0:
                self._value = <SharedValue>(SharedInt.__new__(SharedInt, self.context))
            elif self._format == 1:
                self._value = <SharedValue>(SharedFloat.__new__(SharedFloat, self.context))
            else:
                self._value = <SharedValue>(SharedDouble.__new__(SharedDouble, self.context))
            self.value = previous_value[0]
        else:
            if self._format == 0:
                self._value = <SharedValue>(SharedInt4.__new__(SharedInt4, self.context))
            elif self._format == 1:
                self._value = <SharedValue>(SharedFloat4.__new__(SharedFloat4, self.context))
            else:
                self._value = <SharedValue>(SharedDouble4.__new__(SharedDouble4, self.context))
            self.value = (previous_value, 0, 0, 0)
        self._size = target_size

    @property
    def clamped(self):
        """
        Writable attribute: Whether the slider value should be clamped even when keyboard set
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiSliderFlags_AlwaysClamp) != 0

    @clamped.setter
    def clamped(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiSliderFlags_AlwaysClamp
        if value:
            self.flags |= imgui.ImGuiSliderFlags_AlwaysClamp

    @property
    def drag(self):
        """
        Writable attribute: Whether the use a 'drag'
        slider rather than a regular one.
        Incompatible with 'vertical'.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._drag

    @drag.setter
    def drag(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._drag = value
        if value:
            self._vertical = False

    @property
    def logarithmic(self):
        """
        Writable attribute: Make the slider logarithmic.
        Disables round_to_format if enabled
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiSliderFlags_Logarithmic) != 0

    @logarithmic.setter
    def logarithmic(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~(imgui.ImGuiSliderFlags_Logarithmic | imgui.ImGuiSliderFlags_NoRoundToFormat)
        if value:
            self.flags |= (imgui.ImGuiSliderFlags_Logarithmic | imgui.ImGuiSliderFlags_NoRoundToFormat)

    @property
    def min_value(self):
        """
        Writable attribute: Minimum value the slider
        will be clamped to.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._min

    @min_value.setter
    def min_value(self, double value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._min = value

    @property
    def max_value(self):
        """
        Writable attribute: Maximum value the slider
        will be clamped to.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._max

    @max_value.setter
    def max_value(self, double value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._max = value

    @property
    def no_input(self):
        """
        Writable attribute: Disable Ctrl+Click and Enter key to
        manually set the value
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiSliderFlags_NoInput) != 0

    @no_input.setter
    def no_input(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiSliderFlags_NoInput
        if value:
            self.flags |= imgui.ImGuiSliderFlags_NoInput

    @property
    def print_format(self):
        """
        Writable attribute: format string
        for the value -> string conversion
        for display. If round_to_format is
        enabled, the value is converted
        back and thus appears rounded.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return str(bytes(self._print_format), encoding="utf-8")

    @print_format.setter
    def print_format(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._print_format = bytes(value, 'utf-8')

    @property
    def round_to_format(self):
        """
        Writable attribute: If set (default),
        the value will not have more digits precision
        than the requested format string for display.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiSliderFlags_NoRoundToFormat) == 0

    @round_to_format.setter
    def round_to_format(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if value and (self.flags & imgui.ImGuiSliderFlags_Logarithmic) != 0:
            # Note this is not a limitation from imgui, but they strongly
            # advise not to combine both, and thus we let the user do his
            # own rounding if he really wants to.
            raise ValueError("round_to_format cannot be enabled with logarithmic set")
        self.flags &= ~imgui.ImGuiSliderFlags_NoRoundToFormat
        if not(value):
            self.flags |= imgui.ImGuiSliderFlags_NoRoundToFormat

    @property
    def speed(self):
        """
        Writable attribute: When drag is true,
        this attributes sets the drag speed.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._drag_speed

    @speed.setter
    def speed(self, float value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._drag_speed = value

    @property
    def vertical(self):
        """
        Writable attribute: Whether the use a vertical
        slider. Only sliders of size 1 and drag False
        are supported.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._vertical

    @vertical.setter
    def vertical(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if self._size != 1:
            return
        self._drag = False
        self._vertical = value
        if value:
            self._drag = False

    cdef bint draw_item(self) noexcept nogil:
        cdef imgui.ImGuiSliderFlags flags = self.flags
        if not(self._enabled):
            flags |= imgui.ImGuiSliderFlags_NoInput
        cdef imgui.ImGuiDataType type
        cdef int value_int
        cdef float value_float
        cdef double value_double
        cdef int[4] value_int4
        cdef float[4] value_float4
        cdef double[4] value_double4
        cdef void *data
        cdef void *data_min
        cdef void *data_max
        cdef bint modified
        cdef int imin, imax
        cdef float fmin, fmax
        cdef double dmin, dmax
        # Prepare data type
        if self._format == 0:
            type = imgui.ImGuiDataType_S32
            imin = <int>self._min
            imax = <int>self._max
            data_min = &imin
            data_max = &imax
        elif self._format == 1:
            type = imgui.ImGuiDataType_Float
            fmin = <float>self._min
            fmax = <float>self._max
            data_min = &fmin
            data_max = &fmax
        else:
            type = imgui.ImGuiDataType_Double
            dmin = <double>self._min
            dmax = <double>self._max
            data_min = &dmin
            data_max = &dmax

        # Read the value
        if self._format == 0:
            if self._size == 1:
                value_int = SharedInt.get(<SharedInt>self._value)
                data = &value_int
            else:
                SharedInt4.get(<SharedInt4>self._value, value_int4)
                data = &value_int4
        elif self._format == 1:
            if self._size == 1:
                value_float = SharedFloat.get(<SharedFloat>self._value)
                data = &value_float
            else:
                SharedFloat4.get(<SharedFloat4>self._value, value_float4)
                data = &value_float4
        else:
            if self._size == 1:
                value_double = SharedDouble.get(<SharedDouble>self._value)
                data = &value_double
            else:
                SharedDouble4.get(<SharedDouble4>self._value, value_double4)
                data = &value_double4

        # Draw
        if self._drag:
            if self._size == 1:
                modified = imgui.DragScalar(self.imgui_label.c_str(),
                                            type,
                                            data,
                                            self._drag_speed,
                                            data_min,
                                            data_max,
                                            self._print_format.c_str(),
                                            flags)
            else:
                modified = imgui.DragScalarN(self.imgui_label.c_str(),
                                             type,
                                             data,
                                             self._size,
                                             self._drag_speed,
                                             data_min,
                                             data_max,
                                             self._print_format.c_str(),
                                             flags)
        else:
            if self._size == 1:
                if self._vertical:
                    modified = imgui.VSliderScalar(self.imgui_label.c_str(),
                                                   self.requested_size,
                                                   type,
                                                   data,
                                                   data_min,
                                                   data_max,
                                                   self._print_format.c_str(),
                                                   flags)
                else:
                    modified = imgui.SliderScalar(self.imgui_label.c_str(),
                                                  type,
                                                  data,
                                                  data_min,
                                                  data_max,
                                                  self._print_format.c_str(),
                                                  flags)
            else:
                modified = imgui.SliderScalarN(self.imgui_label.c_str(),
                                               type,
                                               data,
                                               self._size,
                                               data_min,
                                               data_max,
                                               self._print_format.c_str(),
                                               flags)
		
        # Write the value
        if self._enabled:
            if self._format == 0:
                if self._size == 1:
                    SharedInt.set(<SharedInt>self._value, value_int)
                else:
                    SharedInt4.set(<SharedInt4>self._value, value_int4)
            elif self._format == 1:
                if self._size == 1:
                    SharedFloat.set(<SharedFloat>self._value, value_float)
                else:
                    SharedFloat4.set(<SharedFloat4>self._value, value_float4)
            else:
                if self._size == 1:
                    SharedDouble.set(<SharedDouble>self._value, value_double)
                else:
                    SharedDouble4.set(<SharedDouble4>self._value, value_double4)
        self.update_current_state()
        return modified


cdef class ListBox(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_listbox
        self._value = <SharedValue>(SharedStr.__new__(SharedStr, self.context))
        self.state.can_be_activated = True
        self.state.can_be_active = True
        self.state.can_be_clicked = True
        self.state.can_be_deactivated = True
        self.state.can_be_deactivated_after_edited = True
        self.state.can_be_edited = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        self._num_items_shown_when_open = -1
        # Frankly unsure why these. Should it include popup ?:
        #self.state.has_rect_min = True
        #self.state.has_rect_max = True
        #self.state.has_rect_size = True
        #self.state.has_content_region = True

    @property
    def items(self):
        """
        Writable attribute: List of text values to select
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return [str(v, encoding='utf-8') for v in self._items]

    @items.setter
    def items(self, value):
        cdef unique_lock[recursive_mutex] m
        cdef unique_lock[recursive_mutex] value_m
        lock_gil_friendly(m, self.mutex)
        self._items.clear()
        if value is None:
            return
        if value is str:
            self._items.push_back(bytes(value, 'utf-8'))
        elif hasattr(value, '__len__'):
            for v in value:
                self._items.push_back(bytes(v, 'utf-8'))
        else:
            raise ValueError(f"Invalid type {type(value)} passed as items. Expected array of strings")
        lock_gil_friendly(value_m, self._value.mutex)
        if self._value.num_attached == 1 and \
           self._value._last_frame_update == -1 and \
           self._items.size() > 0:
            # initialize the value with the first element
            SharedStr.set(<SharedStr>self._value, self._items[0])

    @property
    def num_items_shown_when_open(self):
        """
        Writable attribute: Number of items
        shown when the menu is opened
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._num_items_shown_when_open

    @num_items_shown_when_open.setter
    def num_items_shown_when_open(self, int value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._num_items_shown_when_open = value

    cdef bint draw_item(self) noexcept nogil:
        # TODO: Merge with ComboBox
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef bint open
        cdef int i
        cdef string current_value
        SharedStr.get(<SharedStr>self._value, current_value)
        cdef imgui.ImVec2 popup_size = imgui.ImVec2(0., 0.)
        cdef float text_height = imgui.GetTextLineHeightWithSpacing()
        cdef int num_items = min(7, <int>self._items.size())
        if self._num_items_shown_when_open > 0:
            num_items = self._num_items_shown_when_open
        # Computation from imgui
        popup_size.y = trunc(<float>0.25 + <float>num_items) * text_height
        popup_size.y += 2. * imgui.GetStyle().FramePadding.y
        open = imgui.BeginListBox(self.imgui_label.c_str(),
                                  popup_size)

        # Old code called update_current_state now, and updated edited state
        # later. Looking at ImGui code there seems to be two items. One
        # for the combo, and one for the popup that opens. The edited flag
        # is not set, looking at imgui demo so we have to handle it manually.
        self.state.activated = not(self.state.active) and open
        self.state.deactivated = self.state.active and not(open)
        self.state.active = open
        self.state.can_be_deactivated = True
        self.state.can_be_deactivated_after_edited = True
        self.state.can_be_edited = True
        self.state.focused = imgui.IsItemFocused()
        self.state.hovered = imgui.IsItemHovered(imgui.ImGuiHoveredFlags_None)
        for i in range(<int>imgui.ImGuiMouseButton_COUNT):
            self.state.clicked[i] = self.state.hovered and imgui.IsItemClicked(i)
            self.state.double_clicked[i] = self.state.hovered and imgui.IsMouseDoubleClicked(i)


        cdef bool pressed = False
        cdef bint changed = False
        cdef bool selected
        cdef bool selected_backup
        # we push an ID because we didn't append ###uuid to the items
        
        # TODO: there are nice ImGuiSelectableFlags to add in the future
        # TODO: use clipper
        if open:
            imgui.PushID(self.uuid)
            if self._enabled:
                for i in range(<int>self._items.size()):
                    imgui.PushID(i)
                    selected = self._items[i] == current_value
                    selected_backup = selected
                    pressed |= imgui.Selectable(self._items[i].c_str(),
                                                &selected,
                                                imgui.ImGuiSelectableFlags_None,
                                                self.requested_size)
                    if selected:
                        imgui.SetItemDefaultFocus()
                    if selected and selected != selected_backup:
                        changed = True
                        SharedStr.set(<SharedStr>self._value, self._items[i])
                    imgui.PopID()
            else:
                # TODO: test
                selected = True
                imgui.Selectable(current_value.c_str(),
                                 &selected,
                                 imgui.ImGuiSelectableFlags_Disabled,
                                 self.requested_size)
            imgui.PopID()
            imgui.EndListBox()
        # TODO: rect_size/min/max: with the popup ? Use clipper for rect_max ?
        self.state.edited = changed
        self.state.deactivated_after_edited = self.state.deactivated and changed
        return pressed


cdef class RadioButton(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_radiobutton
        self._value = <SharedValue>(SharedStr.__new__(SharedStr, self.context))
        self.state.can_be_activated = True
        self.state.can_be_active = True
        self.state.can_be_clicked = True
        self.state.can_be_deactivated = True
        self.state.can_be_deactivated_after_edited = True
        self.state.can_be_edited = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        self._horizontal = False
        # Frankly unsure why these. Should it include popup ?:
        #self.state.has_rect_min = True
        #self.state.has_rect_max = True
        #self.state.has_rect_size = True
        #self.state.has_content_region = True

    @property
    def items(self):
        """
        Writable attribute: List of text values to select
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return [str(v, encoding='utf-8') for v in self._items]

    @items.setter
    def items(self, value):
        cdef unique_lock[recursive_mutex] m
        cdef unique_lock[recursive_mutex] value_m
        lock_gil_friendly(m, self.mutex)
        self._items.clear()
        if value is None:
            return
        if value is str:
            self._items.push_back(bytes(value, 'utf-8'))
        elif hasattr(value, '__len__'):
            for v in value:
                self._items.push_back(bytes(v, 'utf-8'))
        else:
            raise ValueError(f"Invalid type {type(value)} passed as items. Expected array of strings")
        lock_gil_friendly(value_m, self._value.mutex)
        if self._value.num_attached == 1 and \
           self._value._last_frame_update == -1 and \
           self._items.size() > 0:
            # initialize the value with the first element
            SharedStr.set(<SharedStr>self._value, self._items[0])

    @property
    def horizontal(self):
        """
        Writable attribute: Horizontal vs vertical placement
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._horizontal

    @horizontal.setter
    def horizontal(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._horizontal = value

    cdef bint draw_item(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef bint open
        cdef int i
        cdef string current_value
        SharedStr.get(<SharedStr>self._value, current_value)
        imgui.PushID(self.uuid)
        imgui.BeginGroup()

        cdef bint changed = False
        cdef bool selected
        cdef bool selected_backup
        # we push an ID because we didn't append ###uuid to the items
        
        imgui.PushID(self.uuid)
        for i in range(<int>self._items.size()):
            imgui.PushID(i)
            if (self._horizontal and i != 0):
                imgui.SameLine(0., -1.)
            selected_backup = self._items[i] == current_value
            selected = imgui.RadioButton(self._items[i].c_str(),
                                         selected_backup)
            if self._enabled and selected and selected != selected_backup:
                changed = True
                SharedStr.set(<SharedStr>self._value, self._items[i])
            imgui.PopID()
        imgui.EndGroup()
        imgui.PopID()
        self.update_current_state()
        return changed


cdef class InputText(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_inputtext
        self._value = <SharedValue>(SharedStr.__new__(SharedStr, self.context))
        self.state.can_be_activated = True
        self.state.can_be_active = True
        self.state.can_be_clicked = True
        self.state.can_be_deactivated = True
        self.state.can_be_deactivated_after_edited = True
        self.state.can_be_edited = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        # Frankly unsure why these. Should it include popup ?:
        #self.state.has_rect_min = True
        #self.state.has_rect_max = True
        #self.state.has_rect_size = True
        #self.state.has_content_region = True
        self._multiline = False
        self._max_characters = 1024
        self.flags = imgui.ImGuiInputTextFlags_None

    @property
    def hint(self):
        """
        Writable attribute: text hint.
        Doesn't work with multiline.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return str(self._hint, encoding='utf-8')

    @hint.setter
    def hint(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._hint = bytes(value, 'utf-8')
        if len(value) > 0:
            self.multiline = False

    @property
    def multiline(self):
        """
        Writable attribute: multiline text input.
        Doesn't work with non-empty hint.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._multiline

    @multiline.setter
    def multiline(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._multiline = value
        if value:
            self._hint = b""

    @property
    def max_characters(self):
        """
        Writable attribute: Maximal number of characters that can be written
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._max_characters

    @max_characters.setter
    def max_characters(self, int value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if value < 1:
            raise ValueError("There must be at least space for one character")
        self._max_characters = value

    @property
    def decimal(self):
        """
        Writable attribute: Allow 0123456789.+-
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_CharsDecimal) != 0

    @decimal.setter
    def decimal(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_CharsDecimal
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_CharsDecimal

    @property
    def hexadecimal(self):
        """
        Writable attribute:  Allow 0123456789ABCDEFabcdef
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_CharsHexadecimal) != 0

    @hexadecimal.setter
    def hexadecimal(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_CharsHexadecimal
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_CharsHexadecimal

    @property
    def scientific(self):
        """
        Writable attribute: Allow 0123456789.+-*/eE
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_CharsScientific) != 0

    @scientific.setter
    def scientific(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_CharsScientific
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_CharsScientific

    @property
    def uppercase(self):
        """
        Writable attribute: Turn a..z into A..Z
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_CharsUppercase) != 0

    @uppercase.setter
    def uppercase(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_CharsUppercase
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_CharsUppercase

    @property
    def no_spaces(self):
        """
        Writable attribute: Filter out spaces, tabs
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_CharsNoBlank) != 0

    @no_spaces.setter
    def no_spaces(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_CharsNoBlank
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_CharsNoBlank

    @property
    def tab_input(self):
        """
        Writable attribute: Pressing TAB input a '\t' character into the text field
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_AllowTabInput) != 0

    @tab_input.setter
    def tab_input(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_AllowTabInput
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_AllowTabInput

    @property
    def on_enter(self):
        """
        Writable attribute: Callback called everytime Enter is pressed,
        not just when the value is modified.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_EnterReturnsTrue) != 0

    @on_enter.setter
    def on_enter(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_EnterReturnsTrue
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_EnterReturnsTrue

    @property
    def escape_clears_all(self):
        """
        Writable attribute: Escape key clears content if not empty,
        and deactivate otherwise
        (contrast to default behavior of Escape to revert)
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_EscapeClearsAll) != 0

    @escape_clears_all.setter
    def escape_clears_all(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_EscapeClearsAll
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_EscapeClearsAll

    @property
    def ctrl_enter_for_new_line(self):
        """
        Writable attribute: In multi-line mode, validate with Enter,
        add new line with Ctrl+Enter
        (default is opposite: validate with Ctrl+Enter, add line with Enter).
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_CtrlEnterForNewLine) != 0

    @ctrl_enter_for_new_line.setter
    def ctrl_enter_for_new_line(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_CtrlEnterForNewLine
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_CtrlEnterForNewLine

    @property
    def readonly(self):
        """
        Writable attribute: Read-only mode
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_ReadOnly) != 0

    @readonly.setter
    def readonly(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_ReadOnly
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_ReadOnly

    @property
    def password(self):
        """
        Writable attribute: Password mode, display all characters as '*', disable copy
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_Password) != 0

    @password.setter
    def password(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_Password
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_Password

    @property
    def always_overwrite(self):
        """
        Writable attribute: Overwrite mode
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_AlwaysOverwrite) != 0

    @always_overwrite.setter
    def always_overwrite(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_AlwaysOverwrite
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_AlwaysOverwrite

    @property
    def auto_select_all(self):
        """
        Writable attribute: Select entire text when first taking mouse focus
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_AutoSelectAll) != 0

    @auto_select_all.setter
    def auto_select_all(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_AutoSelectAll
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_AutoSelectAll

    @property
    def no_horizontal_scroll(self):
        """
        Writable attribute: Disable following the scroll horizontally
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_NoHorizontalScroll) != 0

    @no_horizontal_scroll.setter
    def no_horizontal_scroll(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_NoHorizontalScroll
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_NoHorizontalScroll

    @property
    def no_undo_redo(self):
        """
        Writable attribute: Disable undo/redo.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_NoUndoRedo) != 0

    @no_undo_redo.setter
    def no_undo_redo(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_NoUndoRedo
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_NoUndoRedo

    cdef bint draw_item(self) noexcept nogil:
        cdef string current_value
        cdef imgui.ImGuiInputTextFlags flags = self.flags
        SharedStr.get(<SharedStr>self._value, current_value)

        cdef bint changed = False
        if not(self._enabled):
            flags |= imgui.ImGuiInputTextFlags_ReadOnly
        if current_value.size() != (self._max_characters+1):
            # TODO: avoid the copies that occur
            # In theory the +1 is not needed here
            current_value.resize(self._max_characters+1)
        cdef char* data = current_value.data()
        if self._multiline:
            changed = imgui.InputTextMultiline(self.imgui_label.c_str(),
                                               data,
                                               self._max_characters+1,
                                               self.requested_size,
                                               self.flags,
                                               NULL, NULL)
        elif self._hint.empty():
            changed = imgui.InputText(self.imgui_label.c_str(),
                                      data,
                                      self._max_characters+1,
                                      self.flags,
                                      NULL, NULL)
        else:
            changed = imgui.InputTextWithHint(self.imgui_label.c_str(),
                                              self._hint.c_str(),
                                              data,
                                              self._max_characters+1,
                                              self.flags,
                                              NULL, NULL)
        self.update_current_state()
        if changed:
            SharedStr.set(<SharedStr>self._value, current_value)
        if not(self._enabled):
            changed = False
            self.state.edited = False
            self.state.deactivated_after_edited = False
            self.state.activated = False
            self.state.active = False
            self.state.deactivated = False
        return changed

ctypedef fused clamp_types:
    int
    float
    double

cdef inline void clamp1(clamp_types &value, double lower, double upper) noexcept nogil:
    if lower != -INFINITY:
        value = <clamp_types>max(<double>value, lower)
    if upper != INFINITY:
        value = <clamp_types>min(<double>value, upper)

cdef inline void clamp4(clamp_types[4] &value, double lower, double upper) noexcept nogil:
    if lower != -INFINITY:
        value[0] = <clamp_types>max(<double>value[0], lower)
        value[1] = <clamp_types>max(<double>value[1], lower)
        value[2] = <clamp_types>max(<double>value[2], lower)
        value[3] = <clamp_types>max(<double>value[3], lower)
    if upper != INFINITY:
        value[0] = <clamp_types>min(<double>value[0], upper)
        value[1] = <clamp_types>min(<double>value[1], upper)
        value[2] = <clamp_types>min(<double>value[2], upper)
        value[3] = <clamp_types>min(<double>value[3], upper)

cdef class InputValue(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_inputvalue
        self._format = 1
        self._size = 1
        self._print_format = b"%.3f"
        self.flags = 0
        self._min = -INFINITY
        self._max = INFINITY
        self._step = 0.1
        self._step_fast = 1.
        self.flags = imgui.ImGuiInputTextFlags_None
        self._value = <SharedValue>(SharedFloat.__new__(SharedFloat, self.context))
        self.state.can_be_active = True # unsure
        self.state.can_be_clicked = True
        self.state.can_be_edited = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        self.can_be_disabled = True
        self.theme_condition_enabled = theme_enablers.t_enabled_True

    def configure(self, **kwargs):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        # Since some options cancel each other, one
        # must enable them in a specific order
        if "format" in kwargs:
            self.format = kwargs.pop("format")
        if "size" in kwargs:
            self.size = kwargs.pop("size")
        # legacy support
        if "min_clamped" in kwargs:
            if kwargs.pop("min_clamped"):
                self._min = kwargs.pop("minv", 0.)
        if "max_clamped" in kwargs:
            if kwargs.pop("max_clamped"):
                self._max = kwargs.pop("maxv", 100.)
        if "minv" in kwargs:
            del kwargs["minv"]
        if "maxv" in kwargs:
            del kwargs["maxv"]
        # baseItem configure will configure the rest.
        return super().configure(**kwargs)

    @property
    def format(self):
        """
        Writable attribute: Format of the slider.
        Must be "int", "float" or "double".
        Note that float here means the 32 bits version.
        The python float corresponds to a double.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if self._format == 1:
            return "float"
        elif self._format == 0:
            return "int"
        return "double"

    @format.setter
    def format(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef int target_format
        if value == "int":
            target_format = 0
        elif value == "float":
            target_format = 1
        elif value == "double":
            target_format = 2
        else:
            raise ValueError(f"Expected 'int', 'float' or 'double'. Got {value}")
        if target_format == self._format:
            return
        self._format = target_format
        # Allocate a new value of the right type
        previous_value = self.value # Pass though the property to do the conversion for us
        if self._size == 1:
            if target_format == 0:
                self._value = <SharedValue>(SharedInt.__new__(SharedInt, self.context))
            elif target_format == 0:
                self._value = <SharedValue>(SharedFloat.__new__(SharedFloat, self.context))
            else:
                self._value = <SharedValue>(SharedDouble.__new__(SharedDouble, self.context))
        else:
            if target_format == 0:
                self._value = <SharedValue>(SharedInt4.__new__(SharedInt4, self.context))
            elif target_format == 0:
                self._value = <SharedValue>(SharedFloat4.__new__(SharedFloat4, self.context))
            else:
                self._value = <SharedValue>(SharedDouble4.__new__(SharedDouble4, self.context))
        self.value = previous_value # Use property to pass through python for the conversion
        self._print_format = b"%d" if target_format == 0 else b"%.3f"

    @property
    def size(self):
        """
        Writable attribute: Size of the slider.
        Can be 1, 2, 3 or 4.
        When 1 the item's value is held with
        a scalar shared value, else it is held
        with a vector of 4 elements (even for
        size 2 and 3)
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._size
        

    @size.setter
    def size(self, int target_size):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if target_size < 0 or target_size > 4:
            raise ValueError(f"Expected 1, 2, 3, or 4 for size. Got {target_size}")
        if self._size == target_size:
            return
        if (self._size > 1 and target_size > 1):
            self._size = target_size
            return
        # Reallocate the internal vector
        previous_value = self.value # Pass though the property to do the conversion for us
        if target_size == 1:
            if self._format == 0:
                self._value = <SharedValue>(SharedInt.__new__(SharedInt, self.context))
            elif self._format == 1:
                self._value = <SharedValue>(SharedFloat.__new__(SharedFloat, self.context))
            else:
                self._value = <SharedValue>(SharedDouble.__new__(SharedDouble, self.context))
            self.value = previous_value[0]
        else:
            if self._format == 0:
                self._value = <SharedValue>(SharedInt4.__new__(SharedInt4, self.context))
            elif self._format == 1:
                self._value = <SharedValue>(SharedFloat4.__new__(SharedFloat4, self.context))
            else:
                self._value = <SharedValue>(SharedDouble4.__new__(SharedDouble4, self.context))
            self.value = (previous_value, 0, 0, 0)
        self._size = target_size

    @property
    def step(self):
        """
        Writable attribute: 
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._step

    @step.setter
    def step(self, double value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._step = value

    @property
    def step_fast(self):
        """
        Writable attribute: 
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._step_fast

    @step_fast.setter
    def step_fast(self, double value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._step_fast = value

    @property
    def min_value(self):
        """
        Writable attribute: Minimum value the input
        will be clamped to.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._min

    @min_value.setter
    def min_value(self, double value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._min = value

    @property
    def max_value(self):
        """
        Writable attribute: Maximum value the input
        will be clamped to.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._max

    @max_value.setter
    def max_value(self, double value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._max = value

    @property
    def print_format(self):
        """
        Writable attribute: format string
        for the value -> string conversion
        for display. If round_to_format is
        enabled, the value is converted
        back and thus appears rounded.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return str(bytes(self._print_format), encoding="utf-8")

    @print_format.setter
    def print_format(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._print_format = bytes(value, 'utf-8')

    @property
    def decimal(self):
        """
        Writable attribute: Allow 0123456789.+-
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_CharsDecimal) != 0

    @decimal.setter
    def decimal(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_CharsDecimal
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_CharsDecimal

    @property
    def hexadecimal(self):
        """
        Writable attribute:  Allow 0123456789ABCDEFabcdef
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_CharsHexadecimal) != 0

    @hexadecimal.setter
    def hexadecimal(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_CharsHexadecimal
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_CharsHexadecimal

    @property
    def scientific(self):
        """
        Writable attribute: Allow 0123456789.+-*/eE
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_CharsScientific) != 0

    @scientific.setter
    def scientific(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_CharsScientific
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_CharsScientific

    @property
    def on_enter(self):
        """
        Writable attribute: Callback called everytime Enter is pressed,
        not just when the value is modified.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_EnterReturnsTrue) != 0

    @on_enter.setter
    def on_enter(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_EnterReturnsTrue
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_EnterReturnsTrue

    @property
    def escape_clears_all(self):
        """
        Writable attribute: Escape key clears content if not empty,
        and deactivate otherwise
        (contrast to default behavior of Escape to revert)
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_EscapeClearsAll) != 0

    @escape_clears_all.setter
    def escape_clears_all(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_EscapeClearsAll
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_EscapeClearsAll

    @property
    def readonly(self):
        """
        Writable attribute: Read-only mode
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_ReadOnly) != 0

    @readonly.setter
    def readonly(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_ReadOnly
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_ReadOnly

    @property
    def password(self):
        """
        Writable attribute: Password mode, display all characters as '*', disable copy
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_Password) != 0

    @password.setter
    def password(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_Password
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_Password

    @property
    def always_overwrite(self):
        """
        Writable attribute: Overwrite mode
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_AlwaysOverwrite) != 0

    @always_overwrite.setter
    def always_overwrite(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_AlwaysOverwrite
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_AlwaysOverwrite

    @property
    def auto_select_all(self):
        """
        Writable attribute: Select entire text when first taking mouse focus
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_AutoSelectAll) != 0

    @auto_select_all.setter
    def auto_select_all(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_AutoSelectAll
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_AutoSelectAll

    @property
    def empty_as_zero(self):
        """
        Writable attribute: parse empty string as zero value
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_ParseEmptyRefVal) != 0

    @empty_as_zero.setter
    def empty_as_zero(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_ParseEmptyRefVal
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_ParseEmptyRefVal

    @property
    def empty_if_zero(self):
        """
        Writable attribute: when value is zero, do not display it
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_DisplayEmptyRefVal) != 0

    @empty_if_zero.setter
    def empty_if_zero(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_DisplayEmptyRefVal
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_DisplayEmptyRefVal

    @property
    def no_horizontal_scroll(self):
        """
        Writable attribute: Disable following the scroll horizontally
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_NoHorizontalScroll) != 0

    @no_horizontal_scroll.setter
    def no_horizontal_scroll(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_NoHorizontalScroll
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_NoHorizontalScroll

    @property
    def no_undo_redo(self):
        """
        Writable attribute: Disable undo/redo.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiInputTextFlags_NoUndoRedo) != 0

    @no_undo_redo.setter
    def no_undo_redo(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiInputTextFlags_NoUndoRedo
        if value:
            self.flags |= imgui.ImGuiInputTextFlags_NoUndoRedo

    cdef bint draw_item(self) noexcept nogil:
        cdef imgui.ImGuiInputTextFlags flags = self.flags
        if not(self._enabled):
            flags |= imgui.ImGuiInputTextFlags_ReadOnly
        cdef imgui.ImGuiDataType type
        cdef int value_int
        cdef float value_float
        cdef double value_double
        cdef int[4] value_int4
        cdef float[4] value_float4
        cdef double[4] value_double4
        cdef void *data
        cdef void *data_step
        cdef void *data_step_fast
        cdef bint modified
        cdef int istep, istep_fast
        cdef float fstep, fstep_fast
        cdef double dstep, dstep_fast
        # Prepare data type
        if self._format == 0:
            type = imgui.ImGuiDataType_S32
            istep = <int>self._step
            istep_fast = <int>self._step_fast
            data_step = &istep
            data_step_fast = &istep_fast
        elif self._format == 1:
            type = imgui.ImGuiDataType_Float
            fstep = <float>self._step
            fstep_fast = <float>self._step_fast
            data_step = &fstep
            data_step_fast = &fstep_fast
        else:
            type = imgui.ImGuiDataType_Double
            dstep = <double>self._step
            dstep_fast = <double>self._step_fast
            data_step = &dstep
            data_step_fast = &dstep_fast

        # Read the value
        if self._format == 0:
            if self._size == 1:
                value_int = SharedInt.get(<SharedInt>self._value)
                data = &value_int
            else:
                SharedInt4.get(<SharedInt4>self._value, value_int4)
                data = &value_int4
        elif self._format == 1:
            if self._size == 1:
                value_float = SharedFloat.get(<SharedFloat>self._value)
                data = &value_float
            else:
                SharedFloat4.get(<SharedFloat4>self._value, value_float4)
                data = &value_float4
        else:
            if self._size == 1:
                value_double = SharedDouble.get(<SharedDouble>self._value)
                data = &value_double
            else:
                SharedDouble4.get(<SharedDouble4>self._value, value_double4)
                data = &value_double4

        # Draw
        if self._size == 1:
            modified = imgui.InputScalar(self.imgui_label.c_str(),
                                         type,
                                         data,
                                         data_step,
                                         data_step_fast,
                                         self._print_format.c_str(),
                                         flags)
        else:
            modified = imgui.InputScalarN(self.imgui_label.c_str(),
                                          type,
                                          data,
                                          self._size,
                                          data_step,
                                          data_step_fast,
                                          self._print_format.c_str(),
                                          flags)

        # Clamp and write the value
        if self._enabled:
            if self._format == 0:
                if self._size == 1:
                    if modified:
                        clamp1[int](value_int, self._min, self._max)
                    SharedInt.set(<SharedInt>self._value, value_int)
                else:
                    if modified:
                        clamp4[int](value_int4, self._min, self._max)
                    SharedInt4.set(<SharedInt4>self._value, value_int4)
            elif self._format == 1:
                if self._size == 1:
                    if modified:
                        clamp1[float](value_float, self._min, self._max)
                    SharedFloat.set(<SharedFloat>self._value, value_float)
                else:
                    if modified:
                        clamp4[float](value_float4, self._min, self._max)
                    SharedFloat4.set(<SharedFloat4>self._value, value_float4)
            else:
                if self._size == 1:
                    if modified:
                        clamp1[double](value_double, self._min, self._max)
                    SharedDouble.set(<SharedDouble>self._value, value_double)
                else:
                    if modified:
                        clamp4[double](value_double4, self._min, self._max)
                    SharedDouble4.set(<SharedDouble4>self._value, value_double4)
            modified = modified and (self._value._last_frame_update == self._value._last_frame_change)
        self.update_current_state()
        return modified


cdef class Text(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_text
        self._color = 0 # invisible
        self._wrap = -1
        self._bullet = False
        self._show_label = False
        self._value = <SharedValue>(SharedStr.__new__(SharedStr, self.context))
        self.state.can_be_active = True # unsure
        self.state.can_be_clicked = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        self.state.has_rect_min = True
        self.state.has_rect_max = True
        self.state.has_rect_size = True
        self.state.has_content_region = True
        self.theme_condition_enabled = theme_enablers.t_enabled_True

    @property
    def color(self):
        """
        Writable attribute: text color.
        If set to 0 (default), that is
        full transparent text, use the
        default value given by the style
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return <int>self._color

    @color.setter
    def color(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._color = parse_color(value)

    @property
    def label(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        """
        Writable attribute: label assigned to the item.
        Used for text fields, window titles, etc
        """
        return self.user_label
    @label.setter
    def label(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if value is None:
            self.user_label = ""
        else:
            self.user_label = value
        # uuid is not used for text, and we don't want to
        # add it when we show the label, thus why we override
        # the label property here.
        self.imgui_label = bytes(self.user_label, 'utf-8')

    @property
    def wrap(self):
        """
        Writable attribute: wrap width in pixels
        -1 for no wrapping
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return <int>self._wrap

    @wrap.setter
    def wrap(self, int value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._wrap = value

    @property
    def bullet(self):
        """
        Writable attribute: Whether to add a bullet
        before the text
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._bullet

    @bullet.setter
    def bullet(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._bullet = value

    @property
    def show_label(self):
        """
        Writable attribute: Whether to display the
        label next to the text stored in value
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._show_label

    @show_label.setter
    def show_label(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._show_label = value

    cdef bint draw_item(self) noexcept nogil:
        imgui.AlignTextToFramePadding()
        if self._color > 0:
            imgui.PushStyleColor(imgui.ImGuiCol_Text, self._color)
        if self._wrap == 0:
            imgui.PushTextWrapPos(0.)
        elif self._wrap > 0:
            imgui.PushTextWrapPos(imgui.GetCursorPosX() + <float>self._wrap)
        if self._show_label or self._bullet:
            imgui.BeginGroup()
        if self._bullet:
            imgui.Bullet()

        cdef string current_value
        SharedStr.get(<SharedStr>self._value, current_value)

        imgui.TextUnformatted(current_value.c_str(), current_value.c_str()+current_value.size())

        if self._wrap >= 0:
            imgui.PopTextWrapPos()
        if self._color > 0:
            imgui.PopStyleColor(1)

        if self._show_label:
            imgui.SameLine(0., -1.)
            imgui.TextUnformatted(self.imgui_label.c_str(), NULL)
        if self._show_label or self._bullet:
            # Group enables to share the states for all items
            imgui.EndGroup()

        self.update_current_state()
        return False


cdef class Selectable(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_selectable
        self._value = <SharedValue>(SharedBool.__new__(SharedBool, self.context))
        self.state.can_be_activated = True
        self.state.can_be_active = True
        self.state.can_be_clicked = True
        self.state.can_be_deactivated = True
        self.state.can_be_deactivated_after_edited = True
        self.state.can_be_edited = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        # Frankly unsure why these. Should it include popup ?:
        #self.state.has_rect_min = True
        #self.state.has_rect_max = True
        #self.state.has_rect_size = True
        #self.state.has_content_region = True
        self.flags = imgui.ImGuiSelectableFlags_None

    @property
    def disable_popup_close(self):
        """
        Writable attribute: Clicking this doesn't close parent popup window
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiSelectableFlags_NoAutoClosePopups) != 0

    @disable_popup_close.setter
    def disable_popup_close(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiSelectableFlags_NoAutoClosePopups
        if value:
            self.flags |= imgui.ImGuiSelectableFlags_NoAutoClosePopups

    @property
    def span_columns(self):
        """
        Writable attribute: Frame will span all columns of its container table (text will still fit in current column)
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiSelectableFlags_SpanAllColumns) != 0

    @span_columns.setter
    def span_columns(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiSelectableFlags_SpanAllColumns
        if value:
            self.flags |= imgui.ImGuiSelectableFlags_SpanAllColumns

    @property
    def on_double_click(self):
        """
        Writable attribute: call callbacks on double clicks too
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiSelectableFlags_AllowDoubleClick) != 0

    @on_double_click.setter
    def on_double_click(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiSelectableFlags_AllowDoubleClick
        if value:
            self.flags |= imgui.ImGuiSelectableFlags_AllowDoubleClick

    @property
    def highlighted(self):
        """
        Writable attribute: highlighted as if hovered
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiSelectableFlags_Highlight) != 0

    @highlighted.setter
    def highlighted(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiSelectableFlags_Highlight
        if value:
            self.flags |= imgui.ImGuiSelectableFlags_Highlight

    cdef bint draw_item(self) noexcept nogil:
        cdef imgui.ImGuiSelectableFlags flags = self.flags
        if not(self._enabled):
            flags |= imgui.ImGuiSelectableFlags_Disabled

        cdef bool checked = SharedBool.get(<SharedBool>self._value)
        cdef bint changed = imgui.Selectable(self.imgui_label.c_str(),
                                             &checked,
                                             flags,
                                             self.requested_size)
        if self._enabled:
            SharedBool.set(<SharedBool>self._value, checked)
        self.update_current_state()
        return changed


cdef class MenuItem(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_menuitem
        self._value = <SharedValue>(SharedBool.__new__(SharedBool, self.context))
        self.state.can_be_activated = True
        self.state.can_be_active = True
        self.state.can_be_clicked = True
        self.state.can_be_deactivated = True
        self.state.can_be_deactivated_after_edited = True
        self.state.can_be_edited = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        # Frankly unsure why these. Should it include popup ?:
        #self.state.has_rect_min = True
        #self.state.has_rect_max = True
        #self.state.has_rect_size = True
        #self.state.has_content_region = True
        self._check = False

    @property
    def check(self):
        """
        Writable attribute:
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._check

    @check.setter
    def check(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._check = value

    @property
    def shortcut(self):
        """
        Writable attribute:
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return str(self._shortcut, encoding='utf-8')

    @shortcut.setter
    def shortcut(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._shortcut = bytes(value, 'utf-8')

    cdef bint draw_item(self) noexcept nogil:
        # TODO dpg does overwrite textdisabled...
        cdef bool current_value = SharedBool.get(<SharedBool>self._value)
        cdef bint activated = imgui.MenuItem(self.imgui_label.c_str(),
                                             self._shortcut.c_str(),
                                             &current_value if self._check else NULL,
                                             self._enabled)
        self.update_current_state()
        SharedBool.set(<SharedBool>self._value, current_value)
        return activated

cdef class ProgressBar(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_progressbar
        self._value = <SharedValue>(SharedFloat.__new__(SharedFloat, self.context))
        self.state.can_be_clicked = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        # Frankly unsure why these. Should it include popup ?:
        self.state.has_rect_min = True
        self.state.has_rect_max = True
        self.state.has_rect_size = True
        self.state.has_content_region = True

    @property
    def overlay(self):
        """
        Writable attribute:
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return str(self._overlay, encoding='utf-8')

    @overlay.setter
    def overlay(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._overlay = bytes(value, 'utf-8')

    cdef bint draw_item(self) noexcept nogil:
        cdef float current_value = SharedFloat.get(<SharedFloat>self._value)
        cdef const char *overlay_text = self._overlay.c_str()
        imgui.PushID(self.uuid)
        imgui.ProgressBar(current_value,
                          self.requested_size,
                          <const char *>NULL if self._overlay.size() == 0 else overlay_text)
        imgui.PopID()
        self.update_current_state()
        return False

cdef class Image(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_image
        self.state.can_be_clicked = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        # Frankly unsure why these. Should it include popup ?:
        self.state.has_rect_min = True
        self.state.has_rect_max = True
        self.state.has_rect_size = True
        self.state.has_content_region = True
        self._border_color = 0
        self._color_multiplier = 4294967295

    @property
    def texture(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._texture
    @texture.setter
    def texture(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if not(isinstance(value, Texture)):
            raise TypeError("texture must be a Texture")
        # TODO: MV_ATLAS_UUID
        self._texture = value
    @property
    def uv(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return list(self._uv)
    @uv.setter
    def uv(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        read_point[float](self._uv, value)
    @property
    def color_multiplier(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef float[4] color_multiplier
        unparse_color(color_multiplier, self._color_multiplier)
        return list(color_multiplier)
    @color_multiplier.setter
    def color_multiplier(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._color_multiplier = parse_color(value)
    @property
    def border_color(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef float[4] border_color
        unparse_color(border_color, self._border_color)
        return list(border_color)
    @border_color.setter
    def border_color(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._border_color = parse_color(value)

    cdef bint draw_item(self) noexcept nogil:
        if self._texture is None:
            return False
        cdef imgui.ImVec2 size = self.requested_size
        if size.x == 0.:
            size.x = self._texture._width
        if size.y == 0.:
            size.y = self._texture._height

        imgui.PushID(self.uuid)
        imgui.Image(self._texture.allocated_texture,
                    size,
                    imgui.ImVec2(self._uv[0], self._uv[1]),
                    imgui.ImVec2(self._uv[2], self._uv[3]),
                    imgui.ColorConvertU32ToFloat4(self._color_multiplier),
                    imgui.ColorConvertU32ToFloat4(self._border_color))
        imgui.PopID()
        self.update_current_state()
        return False


cdef class ImageButton(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_imagebutton
        self._value = <SharedValue>(SharedBool.__new__(SharedBool, self.context))
        self.state.can_be_clicked = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        self.state.can_be_activated = True
        # Frankly unsure why these. Should it include popup ?:
        self.state.has_rect_min = True
        self.state.has_rect_max = True
        self.state.has_rect_size = True
        self.state.has_content_region = True
        self._background_color = 0
        self._color_multiplier = 4294967295
        self._frame_padding = -1

    @property
    def texture(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._texture
    @texture.setter
    def texture(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if not(isinstance(value, Texture)):
            raise TypeError("texture must be a Texture")
        # TODO: MV_ATLAS_UUID
        self._texture = value
    @property
    def frame_padding(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._frame_padding
    @frame_padding.setter
    def frame_padding(self, int value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._frame_padding = value
    @property
    def uv(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return list(self._uv)
    @uv.setter
    def uv(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        read_point[float](self._uv, value)
    @property
    def color_multiplier(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef float[4] color_multiplier
        unparse_color(color_multiplier, self._color_multiplier)
        return list(color_multiplier)
    @color_multiplier.setter
    def color_multiplier(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._color_multiplier = parse_color(value)
    @property
    def background_color(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef float[4] background_color
        unparse_color(background_color, self._background_color)
        return list(background_color)
    @background_color.setter
    def background_color(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._background_color = parse_color(value)

    cdef bint draw_item(self) noexcept nogil:
        if self._texture is None:
            return False
        cdef imgui.ImVec2 size = self.requested_size
        if size.x == 0.:
            size.x = self._texture._width
        if size.y == 0.:
            size.y = self._texture._height

        imgui.PushID(self.uuid)
        if self._frame_padding >= 0:
            imgui.PushStyleVar(imgui.ImGuiStyleVar_FramePadding,
                               imgui.ImVec2(<float>self._frame_padding,
                                            <float>self._frame_padding))
        cdef bint activated
        activated = imgui.ImageButton(self.imgui_label.c_str(),
                                      self._texture.allocated_texture,
                                      size,
                                      imgui.ImVec2(self._uv[0], self._uv[1]),
                                      imgui.ImVec2(self._uv[2], self._uv[3]),
                                      imgui.ColorConvertU32ToFloat4(self._color_multiplier),
                                      imgui.ColorConvertU32ToFloat4(self._background_color))
        if self._frame_padding >= 0:
            imgui.PopStyleVar(1)
        imgui.PopID()
        self.update_current_state()
        return activated

cdef class Separator(uiItem):
    # TODO: is label override really needed ?
    @property
    def label(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        """
        Writable attribute: label assigned to the item.
        Used for text fields, window titles, etc
        """
        return self.user_label
    @label.setter
    def label(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if value is None:
            self.user_label = ""
        else:
            self.user_label = value
        # uuid is not used for text, and we don't want to
        # add it when we show the label, thus why we override
        # the label property here.
        self.imgui_label = bytes(self.user_label, 'utf-8')

    cdef bint draw_item(self) noexcept nogil:
        if self.user_label is None:
            imgui.Separator()
        else:
            imgui.SeparatorText(self.imgui_label.c_str())
        return False

cdef class Spacer(uiItem):
    cdef bint draw_item(self) noexcept nogil:
        if self.requested_size.x == 0 and \
           self.requested_size.y == 0:
            imgui.Spacing()
        else:
            imgui.Dummy(self.requested_size)
        return False

cdef class MenuBar(uiItem):
    # TODO: must be allowed as viewport child
    def __cinit__(self):
        # We should maybe restrict to menuitem ?
        self.can_have_widget_child = True
        self.element_child_category = child_type.cat_menubar
        self.theme_condition_category = theme_categories.t_menubar
        self.state.can_be_clicked = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        self.state.can_be_activated = True
        self.state.has_rect_min = True
        self.state.has_rect_max = True
        self.state.has_rect_size = True
        self.state.has_content_region = True

    cdef bint draw_item(self) noexcept nogil:
        cdef bint menu_allowed
        cdef bint parent_viewport = self._parent is self.context.viewport
        if parent_viewport:
            menu_allowed = imgui.BeginMainMenuBar()
        else:
            menu_allowed = imgui.BeginMenuBar()
        if menu_allowed:
            if self.last_widgets_child is not None:
                self.last_widgets_child.draw()
            if parent_viewport:
                imgui.EndMainMenuBar()
            else:
                imgui.EndMenuBar()
            self.update_current_state()
        else:
            # We should hit this only if window is invisible
            # or has no menu bar
            self.set_hidden_and_propagate()
        return self.state.activated


cdef class Menu(uiItem):
    def __cinit__(self):
        # We should maybe restrict to menuitem ?
        self._value = <SharedValue>(SharedBool.__new__(SharedBool, self.context))
        self.can_have_widget_child = True
        self.theme_condition_category = theme_categories.t_menu
        self.state.can_be_clicked = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        self.state.can_be_activated = True
        self.state.can_be_active = True
        self.state.can_be_deactivated = True
        self.state.has_rect_size = True
        self.state.has_content_region = True

    cdef bint draw_item(self) noexcept nogil:
        cdef bint menu_open = imgui.BeginMenu(self.imgui_label.c_str(),
                                              self._enabled)
        self.update_current_state()
        if menu_open:
            self.state.hovered = imgui.IsWindowHovered(imgui.ImGuiHoveredFlags_None)
            self.state.focused = imgui.IsWindowFocused(imgui.ImGuiFocusedFlags_None)
            self.state.rect_size.x = imgui.GetWindowWidth()
            self.state.rect_size.y = imgui.GetWindowHeight()
            if self.last_widgets_child is not None:
                self.last_widgets_child.draw()
            imgui.EndMenu()
        else:
            self.propagate_hidden_state_to_children()
        SharedBool.set(<SharedBool>self._value, menu_open)
        return self.state.activated

cdef class Tooltip(uiItem):
    def __cinit__(self):
        # We should maybe restrict to menuitem ?
        self.can_have_widget_child = True
        self.theme_condition_category = theme_categories.t_tooltip
        self.state.can_be_active = True
        self.state.has_rect_min = True
        self.state.has_rect_max = True
        self.state.has_rect_size = True
        self.state.has_content_region = True
        self._delay = 0.
        self._hide_on_activity = False
        self._target = None


    @property
    def target(self):
        """
        Target item which state will be checked
        to trigger the tooltip.
        Note if the item is after this tooltip
        in the rendering tree, there will be
        a frame delay.
        If no target is set, the previous sibling
        is the target.
        If the target is not the previous sibling,
        delay will have no effect.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._delay

    @target.setter
    def target(self, baseItem target):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._target = None
        cdef bint success = True
        if isinstance(target, uiItem):
            self.target_state = &(<uiItem>target).state
        elif isinstance(target, PlotAxisConfig):
            self.target_state = &(<PlotAxisConfig>target).state
        elif isinstance(target, plotElement):
            self.target_state = &(<plotElement>target).state
        else:
            success = False
        if not(self.target_state.can_be_hovered) or not(success):
            raise TypeError(f"Unsupported target instance {target}")
        self._target = target

    @property
    def condition_from_handler(self):
        """
        When set, the handler referenced in
        this field will be used to replace
        the target hovering check.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.secondary_handler

    @condition_from_handler.setter
    def condition_from_handler(self, baseHandler handler):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.secondary_handler = handler

    @property
    def delay(self):
        """
        Delay in seconds with no motion before showing the tooltip
        -1: Use imgui defaults
        Has no effect if the target is not the previous sibling,
        or if condition_from_handler is set.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._delay

    @delay.setter
    def delay(self, float value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._delay = value

    @property
    def hide_on_activity(self):
        """
        Hide the tooltip when the mouse moves
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._delay

    @hide_on_activity.setter
    def hide_on_activity(self, float value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._delay = value

    cdef bint draw_item(self) noexcept nogil:
        cdef float hoverDelay_backup
        cdef bint display_condition
        if self.secondary_handler is None:
            if self._target is None or self._target is self._prev_sibling:
                if self._delay > 0.:
                    hoverDelay_backup = imgui.GetStyle().HoverStationaryDelay
                    imgui.GetStyle().HoverStationaryDelay = self._delay
                    display_condition = imgui.IsItemHovered(imgui.ImGuiHoveredFlags_Stationary)
                    imgui.GetStyle().HoverStationaryDelay = hoverDelay_backup
                elif self._delay == 0:
                    display_condition = imgui.IsItemHovered(imgui.ImGuiHoveredFlags_None)
                else:
                    display_condition = imgui.IsItemHovered(imgui.ImGuiHoveredFlags_ForTooltip)
            else:
                display_condition = self.target_state.hovered
        else:
            display_condition = self.secondary_handler.check_state(self._target, dereference(self.target_state))

        if self._hide_on_activity and imgui.GetIO().MouseDelta.x != 0. and \
           imgui.GetIO().MouseDelta.y != 0.:
            display_condition = False

        cdef bint was_visible = self.state.visible
        if display_condition and imgui.BeginTooltip():
            if self.last_widgets_child is not None:
                self.last_widgets_child.draw()
            imgui.EndTooltip()
            self.update_current_state()
        else:
            self.set_hidden_and_propagate()
            # NOTE: we could also set the rects. DPG does it.
        return self.state.visible and not(was_visible)

cdef class TabButton(uiItem):
    def __cinit__(self):
        self.theme_condition_category = theme_categories.t_tabbutton
        self.element_child_category = child_type.cat_tab
        self._value = <SharedValue>(SharedBool.__new__(SharedBool, self.context))
        self.state.can_be_activated = True
        self.state.can_be_active = True
        self.state.can_be_clicked = True
        self.state.can_be_deactivated = True
        self.state.can_be_deactivated_after_edited = True
        self.state.can_be_edited = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        # Frankly unsure why these. Should it include popup ?:
        #self.state.has_rect_min = True
        #self.state.has_rect_max = True
        #self.state.has_rect_size = True
        #self.state.has_content_region = True
        self.flags = imgui.ImGuiTabItemFlags_None

    @property
    def no_reorder(self):
        """
        Writable attribute: Disable reordering this tab or
        having another tab cross over this tab
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabItemFlags_NoReorder) != 0

    @no_reorder.setter
    def no_reorder(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabItemFlags_NoReorder
        if value:
            self.flags |= imgui.ImGuiTabItemFlags_NoReorder

    @property
    def leading(self):
        """
        Writable attribute: Enforce the tab position to the
        left of the tab bar (after the tab list popup button)
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabItemFlags_Leading) != 0

    @leading.setter
    def leading(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabItemFlags_Leading
        if value:
            self.flags &= ~imgui.ImGuiTabItemFlags_Trailing
            self.flags |= imgui.ImGuiTabItemFlags_Leading

    @property
    def trailing(self):
        """
        Writable attribute: Enforce the tab position to the
        right of the tab bar (before the scrolling buttons)
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabItemFlags_Trailing) != 0

    @trailing.setter
    def trailing(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabItemFlags_Trailing
        if value:
            self.flags &= ~imgui.ImGuiTabItemFlags_Leading
            self.flags |= imgui.ImGuiTabItemFlags_Trailing

    @property
    def no_tooltip(self):
        """
        Writable attribute: Disable tooltip for the given tab
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabItemFlags_NoTooltip) != 0

    @no_tooltip.setter
    def no_tooltip(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabItemFlags_NoTooltip
        if value:
            self.flags |= imgui.ImGuiTabItemFlags_NoTooltip

    cdef bint draw_item(self) noexcept nogil:
        cdef bint pressed = imgui.TabItemButton(self.imgui_label.c_str(),
                                                self.flags)
        self.update_current_state()
        #SharedBool.set(<SharedBool>self._value, self.state.active) # Unsure. Not in original
        return pressed


cdef class Tab(uiItem):
    def __cinit__(self):
        self._value = <SharedValue>(SharedBool.__new__(SharedBool, self.context))
        self.can_have_widget_child = True
        self.element_child_category = child_type.cat_tab
        self.theme_condition_category = theme_categories.t_tab
        self.state.can_be_clicked = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        self.state.can_be_activated = True
        self.state.can_be_active = True
        self.state.can_be_deactivated = True
        self.state.has_rect_size = True
        self.state.has_content_region = True
        self._closable = False
        self.flags = imgui.ImGuiTabItemFlags_None

    @property
    def closable(self):
        """
        Writable attribute: Can the tab be closed
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._closable 

    @closable.setter
    def closable(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._closable = value

    @property
    def no_reorder(self):
        """
        Writable attribute: Disable reordering this tab or
        having another tab cross over this tab
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabItemFlags_NoReorder) != 0

    @no_reorder.setter
    def no_reorder(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabItemFlags_NoReorder
        if value:
            self.flags |= imgui.ImGuiTabItemFlags_NoReorder

    @property
    def leading(self):
        """
        Writable attribute: Enforce the tab position to the
        left of the tab bar (after the tab list popup button)
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabItemFlags_Leading) != 0

    @leading.setter
    def leading(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabItemFlags_Leading
        if value:
            self.flags &= ~imgui.ImGuiTabItemFlags_Trailing
            self.flags |= imgui.ImGuiTabItemFlags_Leading

    @property
    def trailing(self):
        """
        Writable attribute: Enforce the tab position to the
        right of the tab bar (before the scrolling buttons)
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabItemFlags_Trailing) != 0

    @trailing.setter
    def trailing(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabItemFlags_Trailing
        if value:
            self.flags &= ~imgui.ImGuiTabItemFlags_Leading
            self.flags |= imgui.ImGuiTabItemFlags_Trailing

    @property
    def no_tooltip(self):
        """
        Writable attribute: Disable tooltip for the given tab
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabItemFlags_NoTooltip) != 0

    @no_tooltip.setter
    def no_tooltip(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabItemFlags_NoTooltip
        if value:
            self.flags |= imgui.ImGuiTabItemFlags_NoTooltip

    cdef bint draw_item(self) noexcept nogil:
        cdef imgui.ImGuiTabItemFlags flags = self.flags
        if (<SharedBool>self._value)._last_frame_change == self.context.viewport.frame_count:
            # The value was changed after the last time we drew
            # TODO: will have no effect if we switch from show to no show.
            # maybe have a counter here.
            if SharedBool.get(<SharedBool>self._value):
                flags |= imgui.ImGuiTabItemFlags_SetSelected
        cdef bint menu_open = imgui.BeginTabItem(self.imgui_label.c_str(),
                                                 &self._show if self._closable else NULL,
                                                 flags)
        if not(self._show):
            self.show_update_requested = True
        self.update_current_state()
        if menu_open:
            if self.last_widgets_child is not None:
                self.last_widgets_child.draw()
            imgui.EndTabItem()
        else:
            self.propagate_hidden_state_to_children()
        SharedBool.set(<SharedBool>self._value, menu_open)
        return self.state.activated


cdef class TabBar(uiItem):
    def __cinit__(self):
        #self._value = <SharedValue>(SharedBool.__new__(SharedBool, self.context))
        self.can_have_tab_child = True
        self.theme_condition_category = theme_categories.t_tabbar
        self.state.can_be_clicked = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        self.state.can_be_activated = True
        self.state.can_be_active = True
        self.state.can_be_deactivated = True
        self.state.has_rect_size = True
        self.state.has_content_region = True
        self.flags = imgui.ImGuiTabBarFlags_None

    @property
    def reorderable(self):
        """
        Writable attribute: Allow manually dragging tabs
        to re-order them + New tabs are appended at the end of list
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabBarFlags_Reorderable) != 0

    @reorderable.setter
    def reorderable(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabBarFlags_Reorderable
        if value:
            self.flags |= imgui.ImGuiTabBarFlags_Reorderable

    @property
    def autoselect_new_tabs(self):
        """
        Writable attribute: Automatically select new
        tabs when they appear
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabBarFlags_AutoSelectNewTabs) != 0

    @autoselect_new_tabs.setter
    def autoselect_new_tabs(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabBarFlags_AutoSelectNewTabs
        if value:
            self.flags |= imgui.ImGuiTabBarFlags_AutoSelectNewTabs

    @property
    def no_tab_list_popup_button(self):
        """
        Writable attribute: Disable buttons to open the tab list popup
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabBarFlags_TabListPopupButton) != 0

    @no_tab_list_popup_button.setter
    def no_tab_list_popup_button(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabBarFlags_TabListPopupButton
        if value:
            self.flags |= imgui.ImGuiTabBarFlags_TabListPopupButton

    @property
    def no_close_with_middle_mouse_button(self):
        """
        Writable attribute: Disable behavior of closing tabs with middle mouse button.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) != 0

    @no_close_with_middle_mouse_button.setter
    def no_close_with_middle_mouse_button(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabBarFlags_NoCloseWithMiddleMouseButton
        if value:
            self.flags |= imgui.ImGuiTabBarFlags_NoCloseWithMiddleMouseButton

    @property
    def no_scrolling_button(self):
        """
        Writable attribute: Disable scrolling buttons
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabBarFlags_NoTabListScrollingButtons) != 0

    @no_scrolling_button.setter
    def no_scrolling_button(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabBarFlags_NoTabListScrollingButtons
        if value:
            self.flags |= imgui.ImGuiTabBarFlags_NoTabListScrollingButtons

    @property
    def no_tooltip(self):
        """
        Writable attribute: Disable tooltip for all tabs
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabBarFlags_NoTooltip) != 0

    @no_tooltip.setter
    def no_tooltip(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabBarFlags_NoTooltip
        if value:
            self.flags |= imgui.ImGuiTabBarFlags_NoTooltip

    @property
    def selected_overline(self):
        """
        Writable attribute: Draw selected overline markers over selected tab
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabBarFlags_DrawSelectedOverline) != 0

    @selected_overline.setter
    def selected_overline(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabBarFlags_DrawSelectedOverline
        if value:
            self.flags |= imgui.ImGuiTabBarFlags_DrawSelectedOverline

    @property
    def resize_to_fit(self):
        """
        Writable attribute: Resize tabs when they don't fit
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabBarFlags_FittingPolicyResizeDown) != 0

    @resize_to_fit.setter
    def resize_to_fit(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabBarFlags_FittingPolicyResizeDown
        if value:
            self.flags |= imgui.ImGuiTabBarFlags_FittingPolicyResizeDown

    @property
    def allow_tab_scroll(self):
        """
        Writable attribute: Add scroll buttons when tabs don't fit
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTabBarFlags_FittingPolicyScroll) != 0

    @allow_tab_scroll.setter
    def allow_tab_scroll(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTabBarFlags_FittingPolicyScroll
        if value:
            self.flags |= imgui.ImGuiTabBarFlags_FittingPolicyScroll

    cdef bint draw_item(self) noexcept nogil:
        imgui.PushID(self.uuid)
        imgui.BeginGroup() # from original. Unsure if needed
        cdef bint visible = imgui.BeginTabBar(self.imgui_label.c_str(),
                                              self.flags)
        self.update_current_state()
        if visible:
            if self.last_tab_child is not None:
                self.last_tab_child.draw()
            imgui.EndTabBar()
        else:
            self.propagate_hidden_state_to_children()
        imgui.EndGroup()
        imgui.PopID()
        return self.state.activated


cdef class Group(uiItem):
    """
    A group enables two things:
    . Share the same indentation for the children
    . The group states correspond to an OR of all
      the item states within
    TODO: very incomplete
    """
    def __cinit__(self):
        self.can_have_widget_child = True
        self.state.can_be_active = True
        self.state.can_be_activated = True
        self.state.can_be_clicked = True
        self.state.can_be_deactivated = True
        self.state.can_be_deactivated_after_edited = True
        self.state.can_be_edited = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        self.state.can_be_toggled = True
        self.state.has_rect_min = True
        self.state.has_rect_max = True
        self.state.has_rect_size = True
        self.state.has_content_region = True
        self.theme_condition_category = theme_categories.t_group

    cdef bint draw_item(self) noexcept nogil:
        imgui.PushID(self.uuid)
        imgui.BeginGroup()
        if self.last_widgets_child is not None:
            self.last_widgets_child.draw()
        imgui.EndGroup()
        imgui.PopID()
        self.update_current_state()


cdef class TreeNode(uiItem):
    def __cinit__(self):
        self._value = <SharedValue>(SharedBool.__new__(SharedBool, self.context))
        self.can_have_widget_child = True
        self.state.can_be_active = True
        self.state.can_be_activated = True
        self.state.can_be_clicked = True
        self.state.can_be_deactivated = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        self.state.can_be_toggled = True
        self.state.has_rect_min = True
        self.state.has_rect_max = True
        self.state.has_rect_size = True
        self.state.has_content_region = True
        self._selectable = False
        self.flags = imgui.ImGuiTreeNodeFlags_None
        self.theme_condition_category = theme_categories.t_treenode

    @property
    def selectable(self):
        """
        Writable attribute: Draw the TreeNode as selected when opened
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._selectable

    @selectable.setter
    def selectable(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._selectable = value

    @property
    def default_open(self):
        """
        Writable attribute: Default node to be open
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTreeNodeFlags_DefaultOpen) != 0

    @default_open.setter
    def default_open(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTreeNodeFlags_DefaultOpen
        if value:
            self.flags |= imgui.ImGuiTreeNodeFlags_DefaultOpen

    @property
    def open_on_double_click(self):
        """
        Writable attribute: Need double-click to open node
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTreeNodeFlags_OpenOnDoubleClick) != 0

    @open_on_double_click.setter
    def open_on_double_click(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTreeNodeFlags_OpenOnDoubleClick
        if value:
            self.flags |= imgui.ImGuiTreeNodeFlags_OpenOnDoubleClick

    @property
    def open_on_arrow(self):
        """
        Writable attribute:  Only open when clicking on the arrow part.
        If ImGuiTreeNodeFlags_OpenOnDoubleClick is also set,
        single-click arrow or double-click all box to open.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTreeNodeFlags_OpenOnArrow) != 0

    @open_on_arrow.setter
    def open_on_arrow(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTreeNodeFlags_OpenOnArrow
        if value:
            self.flags |= imgui.ImGuiTreeNodeFlags_OpenOnArrow

    @property
    def leaf(self):
        """
        Writable attribute: No collapsing, no arrow (use as a convenience for leaf nodes).
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTreeNodeFlags_Leaf) != 0

    @leaf.setter
    def leaf(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTreeNodeFlags_Leaf
        if value:
            self.flags |= imgui.ImGuiTreeNodeFlags_Leaf

    @property
    def bullet(self):
        """
        Writable attribute: Display a bullet instead of arrow.
        IMPORTANT: node can still be marked open/close if
        you don't set the _Leaf flag!
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTreeNodeFlags_Bullet) != 0

    @bullet.setter
    def bullet(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTreeNodeFlags_Bullet
        if value:
            self.flags |= imgui.ImGuiTreeNodeFlags_Bullet

    @property
    def span_text_width(self):
        """
        Writable attribute: Narrow hit box + narrow hovering
        highlight, will only cover the label text.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTreeNodeFlags_SpanTextWidth) != 0

    @span_text_width.setter
    def span_text_width(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTreeNodeFlags_SpanTextWidth
        if value:
            self.flags |= imgui.ImGuiTreeNodeFlags_SpanTextWidth

    @property
    def span_full_width(self):
        """
        Writable attribute: Extend hit box to the left-most
        and right-most edges (cover the indent area).
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTreeNodeFlags_SpanFullWidth) != 0

    @span_full_width.setter
    def span_full_width(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTreeNodeFlags_SpanFullWidth
        if value:
            self.flags |= imgui.ImGuiTreeNodeFlags_SpanFullWidth

    cdef bint draw_item(self) noexcept nogil:
        cdef bint was_open = SharedBool.get(<SharedBool>self._value)
        cdef bint closed = False
        cdef imgui.ImGuiTreeNodeFlags flags = self.flags
        imgui.PushID(self.uuid)
        # Unsure group is needed
        imgui.BeginGroup()
        if was_open and self._selectable:
            flags |= imgui.ImGuiTreeNodeFlags_Selected

        imgui.SetNextItemOpen(was_open, imgui.ImGuiCond_Always)
        cdef bint open_and_visible = imgui.TreeNodeEx(self.imgui_label.c_str(),
                                                      flags)
        self.update_current_state()
        if self.state.toggled:
            SharedBool.set(<SharedBool>self._value, open_and_visible)
            if not(open_and_visible):
                self.state.toggled = False
                self.propagate_hidden_state_to_children()
        if open_and_visible:
            if self.last_widgets_child is not None:
                self.last_widgets_child.draw()
            imgui.TreePop()

        imgui.EndGroup()
        imgui.PopID()

cdef class CollapsingHeader(uiItem):
    def __cinit__(self):
        self._value = <SharedValue>(SharedBool.__new__(SharedBool, self.context))
        self.can_have_widget_child = True
        self.state.can_be_active = True
        self.state.can_be_activated = True
        self.state.can_be_clicked = True
        self.state.can_be_deactivated = True
        self.state.can_be_focused = True
        self.state.can_be_hovered = True
        self.state.can_be_toggled = True
        self.state.has_rect_min = True
        self.state.has_rect_max = True
        self.state.has_rect_size = True
        self.state.has_content_region = True
        self._closable = False
        self.flags = imgui.ImGuiTreeNodeFlags_None
        self.theme_condition_category = theme_categories.t_collapsingheader

    @property
    def closable(self):
        """
        Writable attribute: Display a close button
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._closable

    @closable.setter
    def closable(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._closable = value

    @property
    def open_on_double_click(self):
        """
        Writable attribute: Need double-click to open node
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTreeNodeFlags_OpenOnDoubleClick) != 0

    @open_on_double_click.setter
    def open_on_double_click(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTreeNodeFlags_OpenOnDoubleClick
        if value:
            self.flags |= imgui.ImGuiTreeNodeFlags_OpenOnDoubleClick

    @property
    def open_on_arrow(self):
        """
        Writable attribute:  Only open when clicking on the arrow part.
        If ImGuiTreeNodeFlags_OpenOnDoubleClick is also set,
        single-click arrow or double-click all box to open.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTreeNodeFlags_OpenOnArrow) != 0

    @open_on_arrow.setter
    def open_on_arrow(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTreeNodeFlags_OpenOnArrow
        if value:
            self.flags |= imgui.ImGuiTreeNodeFlags_OpenOnArrow

    @property
    def leaf(self):
        """
        Writable attribute: No collapsing, no arrow (use as a convenience for leaf nodes).
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTreeNodeFlags_Leaf) != 0

    @leaf.setter
    def leaf(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTreeNodeFlags_Leaf
        if value:
            self.flags |= imgui.ImGuiTreeNodeFlags_Leaf

    @property
    def bullet(self):
        """
        Writable attribute: Display a bullet instead of arrow.
        IMPORTANT: node can still be marked open/close if
        you don't set the _Leaf flag!
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & imgui.ImGuiTreeNodeFlags_Bullet) != 0

    @bullet.setter
    def bullet(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~imgui.ImGuiTreeNodeFlags_Bullet
        if value:
            self.flags |= imgui.ImGuiTreeNodeFlags_Bullet

    cdef bint draw_item(self) noexcept nogil:
        cdef bint was_open = SharedBool.get(<SharedBool>self._value)
        cdef bint closed = False
        cdef imgui.ImGuiTreeNodeFlags flags = self.flags
        if self._closable:
            flags |= imgui.ImGuiTreeNodeFlags_Selected

        imgui.SetNextItemOpen(was_open, imgui.ImGuiCond_Always)
        cdef bint open_and_visible = \
            imgui.CollapsingHeader(self.imgui_label.c_str(),
                                   &self._show if self._closable else NULL,
                                   flags)
        if not(self._show):
            self.show_update_requested = True
        self.update_current_state()
        if self.state.toggled:
            SharedBool.set(<SharedBool>self._value, open_and_visible)
            if not(open_and_visible):
                self.state.toggled = False
                self.propagate_hidden_state_to_children()
        if open_and_visible:
            if self.last_widgets_child is not None:
                self.last_widgets_child.draw()


"""
Complex ui items
"""

cdef class TimeWatcher(uiItem):
    """
    A placeholder uiItem that doesn't draw
    or have any impact on rendering.
    This item calls the callback with times in ns.
    These times can be compared with the times in the metrics
    that can be obtained from the viewport in order to
    precisely figure out the time spent rendering specific items.

    The first time corresponds to the time when the next sibling
    requested this sibling to render. At this step, no sibling
    of this item (previous or next) have rendered anything.

    The second time corresponds to the time when the previous
    siblings have finished rendering and it is now the turn
    of this item to render. Next items have not rendered yet.

    The third time corresponds to the time when viewport
    started rendering items for this frame. It is a duplicate of
    context.viewport.metrics.last_t_before_rendering. It is
    given to prevent the user from having to keep track of the
    viewport metrics (since the callback might be called
    after or before the viewport updated its metrics for this
    frame or another one).

    The fourth number corresponds to the frame count
    at the the time the callback was issued.

    Note the times relate to CPU time (checking states, preparing
    GPU data, etc), not to GPU rendering time.
    """
    cdef void draw(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef long long time_start = ctime.monotonic_ns()
        if self._prev_sibling is not None:
            (<uiItem>self._prev_sibling).draw()
        cdef long long time_end = ctime.monotonic_ns()
        self.context.queue_callback_arg3long1int(self._callback,
                                                 self,
                                                 time_start,
                                                 time_end,
                                                 self.context.viewport.last_t_before_rendering,
                                                 self.context.viewport.frame_count)
        

cdef class Window(uiItem):
    def __cinit__(self):
        self.window_flags = imgui.ImGuiWindowFlags_None
        self.main_window = False
        self.modal = False
        self.popup = False
        self.has_close_button = True
        self.collapsed = False
        self.collapse_update_requested = False
        self.no_open_over_existing_popup = True
        self.on_close_callback = None
        self.state.rect_min = imgui.ImVec2(100., 100.) # tODO state ?
        self.state.rect_max = imgui.ImVec2(30000., 30000.)
        self.theme_condition_enabled = theme_enablers.t_enabled_any
        self.theme_condition_category = theme_categories.t_window
        self.scroll_x = 0.
        self.scroll_y = 0.
        self.scroll_x_update_requested = False
        self.scroll_y_update_requested = False
        # Read-only states
        self.scroll_max_x = 0.
        self.scroll_max_y = 0.

        # backup states when we set/unset primary
        #self.backup_window_flags = imgui.ImGuiWindowFlags_None
        #self.backup_pos = self.relative_position
        #self.backup_rect_size = self.state.rect_size
        # Type info
        self.can_have_widget_child = True
        self.can_have_drawing_child = True
        self.can_have_menubar_child = True
        self.can_have_payload_child = True
        self.element_child_category = child_type.cat_window
        self.state.can_be_hovered = True
        self.state.can_be_focused = True
        self.state.has_rect_size = True
        self.state.has_rect_min = True
        self.state.has_rect_max = True
        self.state.has_content_region = True

    @property
    def no_title_bar(self):
        """Writable attribute to disable the title-bar"""
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_NoTitleBar) else False

    @no_title_bar.setter
    def no_title_bar(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_NoTitleBar
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_NoTitleBar

    @property
    def no_resize(self):
        """Writable attribute to block resizing"""
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_NoResize) else False

    @no_resize.setter
    def no_resize(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_NoResize
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_NoResize

    @property
    def no_move(self):
        """Writable attribute the window to be move with interactions"""
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_NoMove) else False

    @no_move.setter
    def no_move(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_NoMove
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_NoMove

    @property
    def no_scrollbar(self):
        """Writable attribute to indicate the window should have no scrollbar
           Does not disable scrolling via mouse or keyboard
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_NoScrollbar) else False

    @no_scrollbar.setter
    def no_scrollbar(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_NoScrollbar
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_NoScrollbar
    
    @property
    def no_scroll_with_mouse(self):
        """Writable attribute to indicate the mouse wheel
           should have no effect on scrolling of this window
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_NoScrollWithMouse) else False

    @no_scroll_with_mouse.setter
    def no_scroll_with_mouse(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_NoScrollWithMouse
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_NoScrollWithMouse

    @property
    def no_collapse(self):
        """Writable attribute to disable user collapsing window by double-clicking on it
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_NoCollapse) else False

    @no_collapse.setter
    def no_collapse(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_NoCollapse
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_NoCollapse

    @property
    def autosize(self):
        """Writable attribute to tell the window should
           automatically resize to fit its content
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_AlwaysAutoResize) else False

    @autosize.setter
    def autosize(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_AlwaysAutoResize
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_AlwaysAutoResize

    @property
    def no_background(self):
        """
        Writable attribute to disable drawing background
        color and outside border
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_NoBackground) else False

    @no_background.setter
    def no_background(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_NoBackground
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_NoBackground

    @property
    def no_saved_settings(self):
        """
        Writable attribute to never load/save settings in .ini file
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_NoSavedSettings) else False

    @no_saved_settings.setter
    def no_saved_settings(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_NoSavedSettings
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_NoSavedSettings

    @property
    def no_mouse_inputs(self):
        """
        Writable attribute to disable mouse input event catching of the window.
        Events such as clicked, hovering, etc will be passed to items behind the
        window.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_NoMouseInputs) else False

    @no_mouse_inputs.setter
    def no_mouse_inputs(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_NoMouseInputs
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_NoMouseInputs

    @property
    def no_keyboard_inputs(self):
        """
        Writable attribute to disable keyboard manipulation (scroll).
        The window will not take focus of the keyboard.
        Does not affect items inside the window.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_NoNav) else False

    @no_keyboard_inputs.setter
    def no_keyboard_inputs(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_NoNav
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_NoNav

    @property
    def menubar(self):
        """
        Readable attribute to indicate whether the window has a menu bar.

        There will be menubar if either the user has asked for it,
        or there is a menubar child.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.last_menubar_child is not None) or (self.window_flags & imgui.ImGuiWindowFlags_MenuBar) != 0

    @menubar.setter
    def menubar(self, bint value):
        """
        Readable attribute to indicate whether the window has a menu bar.

        There will be menubar if either the user has asked for it,
        or there is a menubar child.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_MenuBar
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_MenuBar

    @property
    def horizontal_scrollbar(self):
        """
        Writable attribute to enable having an horizontal scrollbar
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_HorizontalScrollbar) else False

    @horizontal_scrollbar.setter
    def horizontal_scrollbar(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_HorizontalScrollbar
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_HorizontalScrollbar

    @property
    def no_focus_on_appearing(self):
        """
        Writable attribute to indicate when the windows moves from
        an un-shown to a shown item shouldn't be made automatically
        focused
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_NoFocusOnAppearing) else False

    @no_focus_on_appearing.setter
    def no_focus_on_appearing(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_NoFocusOnAppearing
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_NoFocusOnAppearing

    @property
    def no_bring_to_front_on_focus(self):
        """
        Writable attribute to indicate when the window takes focus (click on it, etc)
        it shouldn't be shown in front of other windows
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_NoBringToFrontOnFocus) else False

    @no_bring_to_front_on_focus.setter
    def no_bring_to_front_on_focus(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_NoBringToFrontOnFocus
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_NoBringToFrontOnFocus

    @property
    def always_show_vertical_scrollvar(self):
        """
        Writable attribute to tell to always show a vertical scrollbar
        even when the size does not require it
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_AlwaysVerticalScrollbar) else False

    @always_show_vertical_scrollvar.setter
    def always_show_vertical_scrollvar(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_AlwaysVerticalScrollbar
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_AlwaysVerticalScrollbar

    @property
    def always_show_horizontal_scrollvar(self):
        """
        Writable attribute to tell to always show a horizontal scrollbar
        even when the size does not require it (only if horizontal scrollbar
        are enabled)
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_AlwaysHorizontalScrollbar) else False

    @always_show_horizontal_scrollvar.setter
    def always_show_horizontal_scrollvar(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_AlwaysHorizontalScrollbar
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_AlwaysHorizontalScrollbar

    @property
    def unsaved_document(self):
        """
        Writable attribute to display a dot next to the title, as if the window
        contains unsaved changes.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_UnsavedDocument) else False

    @unsaved_document.setter
    def unsaved_document(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_UnsavedDocument
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_UnsavedDocument

    @property
    def disallow_docking(self):
        """
        Writable attribute to disable docking for the window
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if (self.window_flags & imgui.ImGuiWindowFlags_NoDocking) else False

    @disallow_docking.setter
    def disallow_docking(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.window_flags &= ~imgui.ImGuiWindowFlags_NoDocking
        if value:
            self.window_flags |= imgui.ImGuiWindowFlags_NoDocking

    @property
    def no_open_over_existing_popup(self):
        """
        Writable attribute for modal and popup windows to prevent them from
        showing if there is already an existing popup/modal window
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.no_open_over_existing_popup

    @no_open_over_existing_popup.setter
    def no_open_over_existing_popup(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.no_open_over_existing_popup = value

    @property
    def modal(self):
        """
        Writable attribute to indicate the window is a modal window.
        Modal windows are similar to popup windows, but they have a close
        button and are not closed by clicking outside.
        Clicking has no effect of items outside the modal window until it is closed.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.modal

    @modal.setter
    def modal(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.modal = value

    @property
    def popup(self):
        """
        Writable attribute to indicate the window is a popup window.
        Popup windows are centered (unless a pos is set), do not have a
        close button, and are closed when they lose focus (clicking outside the
        window).
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.popup

    @popup.setter
    def popup(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.popup = value

    @property
    def has_close_button(self):
        """
        Writable attribute to indicate the window has a close button.
        Has effect only for normal and modal windows.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.has_close_button and not(self.popup)

    @has_close_button.setter
    def has_close_button(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.has_close_button = value

    @property
    def collapsed(self):
        """
        Writable attribute to collapse (~minimize) or uncollapse the window
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.collapsed 

    @collapsed.setter
    def collapsed(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.collapsed = value
        self.collapse_update_requested = True

    @property
    def on_close(self):
        """
        Callback to call when the window is closed.
        Note closing the window does not destroy or unattach the item.
        Instead it is switched to a show=False state.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.on_close_callback

    @on_close.setter
    def on_close(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.on_close_callback = value if isinstance(value, Callback) or value is None else Callback(value)

    @property
    def primary(self):
        """
        Writable attribute: Indicate if the window is the primary window.
        There is maximum one primary window. The primary window covers the whole
        viewport and can be used to draw on the background.
        It is equivalent to setting:
        no_bring_to_front_on_focus
        no_saved_settings
        no_resize
        no_collapse
        no_title_bar
        and running item.focused = True on all the other windows
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.main_window

    @primary.setter
    def primary(self, bint value):
        cdef unique_lock[recursive_mutex] m
        cdef unique_lock[recursive_mutex] m2
        # If window has a parent, it is the viewport
        lock_gil_friendly(m, self.context.viewport.mutex)
        lock_gil_friendly(m2, self.mutex)

        if self._parent is None:
            raise ValueError("Window must be attached before becoming primary")
        if self.main_window == value:
            return # Nothing to do
        self.main_window = value
        if value:
            # backup previous state
            self.backup_window_flags = self.window_flags
            self.backup_pos = self._relative_position
            self.backup_rect_size = self.state.rect_size
            # Make primary
            self.window_flags = \
                imgui.ImGuiWindowFlags_NoBringToFrontOnFocus | \
                imgui.ImGuiWindowFlags_NoSavedSettings | \
			    imgui.ImGuiWindowFlags_NoResize | \
                imgui.ImGuiWindowFlags_NoCollapse | \
                imgui.ImGuiWindowFlags_NoTitleBar
        else:
            # Restore previous state
            self.window_flags = self.backup_window_flags
            self._relative_position = self.backup_pos
            self.requested_size = self.backup_rect_size
            # Tell imgui to update the window shape
            self.pos_update_requested = True
            self.size_update_requested = True

        # Re-tell imgui the window hierarchy
        cdef Window w = self.context.viewport.last_window_child
        cdef Window next = None
        while w is not None:
            with nogil:
                w.mutex.lock()
            w.state.focused = True
            w.focus_update_requested = True
            next = w._prev_sibling
            w.mutex.unlock()
            # TODO: previous code did restore previous states on each window. Figure out why
            w = next

    cdef void draw(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        if self._prev_sibling is not None:
            (<uiItem>self._prev_sibling).draw()

        if not(self._show):
            if self.show_update_requested:
                self.set_hidden_and_propagate()
                self.show_update_requested = False
            return

        if self.focus_update_requested:
            if self.state.focused:
                imgui.SetNextWindowFocus()
            self.focus_update_requested = False

        if self.pos_update_requested:
            imgui.SetNextWindowPos(self._relative_position, <imgui.ImGuiCond>0)
            self.pos_update_requested = False

        if self.size_update_requested:
            imgui.SetNextWindowSize(self.requested_size,
                                    <imgui.ImGuiCond>0)
            self.size_update_requested = False

        if self.collapse_update_requested:
            imgui.SetNextWindowCollapsed(self.collapsed, <imgui.ImGuiCond>0)
            self.collapse_update_requested = False

        imgui.SetNextWindowSizeConstraints(self.state.rect_min, self.state.rect_max)

        cdef imgui.ImVec2 scroll_requested
        if self.scroll_x_update_requested or self.scroll_y_update_requested:
            scroll_requested = imgui.ImVec2(-1., -1.) # -1 means no effect
            if self.scroll_x_update_requested:
                if self.scroll_x < 0.:
                    scroll_requested.x = 1. # from previous code. Not sure why
                else:
                    scroll_requested.x = self.scroll_x
                self.scroll_x_update_requested = False

            if self.scroll_y_update_requested:
                if self.scroll_y < 0.:
                    scroll_requested.y = 1.
                else:
                    scroll_requested.y = self.scroll_y
                self.scroll_y_update_requested = False
            imgui.SetNextWindowScroll(scroll_requested)

        if self.main_window:
            imgui.SetNextWindowBgAlpha(1.0)
            imgui.PushStyleVar(imgui.ImGuiStyleVar_WindowRounding, 0.0) #to prevent main window corners from showing
            imgui.SetNextWindowPos(imgui.ImVec2(0.0, 0.0), <imgui.ImGuiCond>0)
            imgui.SetNextWindowSize(imgui.ImVec2(<float>self.context.viewport.viewport.clientWidth,
                                           <float>self.context.viewport.viewport.clientHeight),
                                    <imgui.ImGuiCond>0)

        # handle fonts
        """
        if self.font:
            ImFont* fontptr = static_cast<mvFont*>(item.font.get())->getFontPtr();
            ImGui::PushFont(fontptr);
        """

        # themes
        self.context.viewport.push_pending_theme_actions(
            theme_enablers.t_enabled_any,
            theme_categories.t_window
        )
        if self._theme is not None:
            self._theme.push()

        cdef bint visible = True
        # Modal/Popup windows must be manually opened
        if self.modal or self.popup:
            if self.show_update_requested and self._show:
                self.show_update_requested = False
                imgui.OpenPopup(self.imgui_label.c_str(),
                                imgui.ImGuiPopupFlags_NoOpenOverExistingPopup if self.no_open_over_existing_popup else imgui.ImGuiPopupFlags_None)

        # Begin drawing the window
        cdef imgui.ImGuiWindowFlags flags = self.window_flags
        if self.last_menubar_child is not None:
            flags |= imgui.ImGuiWindowFlags_MenuBar

        if self.modal:
            visible = imgui.BeginPopupModal(self.imgui_label.c_str(),
                                            &self._show if self.has_close_button else <bool*>NULL,
                                            flags)
        elif self.popup:
            visible = imgui.BeginPopup(self.imgui_label.c_str(), flags)
        else:
            visible = imgui.Begin(self.imgui_label.c_str(),
                                  &self._show if self.has_close_button else <bool*>NULL,
                                  flags)

        # not(visible) means either closed or clipped
        # if has_close_button, show can be switched from True to False if closed

        cdef imgui.ImDrawList* this_drawlist
        cdef float startx, starty

        if visible:
            # Draw the window content
            this_drawlist = imgui.GetWindowDrawList()
            startx = <float>imgui.GetCursorScreenPos().x
            starty = <float>imgui.GetCursorScreenPos().y

            #if self.last_0_child is not None:
            #    self.last_0_child.draw(this_drawlist, startx, starty)

            if self.last_widgets_child is not None:
                self.last_widgets_child.draw()
            # TODO if self.children_widgets[i].tracked and show:
            #    imgui.SetScrollHereY(self.children_widgets[i].trackOffset)

            # Seems redundant with DrawInWindow
            # DrawInWindow is more powerful
            startx = <float>imgui.GetCursorScreenPos().x
            starty = <float>imgui.GetCursorScreenPos().y
            self.context.viewport.in_plot = False
            self.context.viewport.shift_x = startx
            self.context.viewport.shift_y = starty
            if self.last_drawings_child is not None:
                self.last_drawings_child.draw(this_drawlist)

            if self.last_menubar_child is not None:
                self.last_menubar_child.draw()

        cdef imgui.ImVec2 rect_size
        if visible:
            # Set current states
            self.state.visible = True
            self.state.hovered = imgui.IsWindowHovered(imgui.ImGuiHoveredFlags_None)
            self.state.focused = imgui.IsWindowFocused(imgui.ImGuiFocusedFlags_None)
            rect_size = imgui.GetWindowSize()
            self.state.resized = rect_size.x != self.state.rect_size.x or \
                                 rect_size.y != self.state.rect_size.y
            # TODO: investigate why width and height could be != state.rect_size
            if (rect_size.x != self.requested_size.x or rect_size.y != self.requested_size.y):
                self.requested_size = rect_size
                self.resized = True
            self.state.rect_size = rect_size
            self.last_frame_update = self.context.viewport.frame_count
            self._relative_position = imgui.GetWindowPos()
            self._absolute_position = self._relative_position
        else:
            # Window is hidden or closed
            if not(self.state.visible): # This is not new
                # Propagate the info
                self.set_hidden_and_propagate()

        self.collapsed = imgui.IsWindowCollapsed()
        self.state.toggled = imgui.IsWindowAppearing() # Original code used Collapsed
        self.scroll_x = imgui.GetScrollX()
        self.scroll_y = imgui.GetScrollY()


        # Post draw
        """
        // pop font from stack
        if (item.font)
            ImGui::PopFont();
        """

        """
        cdef float titleBarHeight
        cdef float x, y
        cdef imgui.ImVec2 mousePos
        if focused:
            titleBarHeight = imgui.GetStyle().FramePadding.y * 2 + imgui.GetFontSize()

            # update mouse
            mousePos = imgui.GetMousePos()
            x = mousePos.x - self.pos.x
            y = mousePos.y - self.pos.y - titleBarHeight
            #GContext->input.mousePos.x = (int)x;
            #GContext->input.mousePos.y = (int)y;
            #GContext->activeWindow = item
        """

        if (self.modal or self.popup):
            if visible:
                # End() is called automatically for modal and popup windows if not visible
                imgui.EndPopup()
        else:
            imgui.End()

        if self.main_window:
            imgui.PopStyleVar(1)

        if self._theme is not None:
            self._theme.pop()
        self.context.viewport.pop_applied_pending_theme_actions()

        cdef bint closed = not(self._show) or (not(visible) and (self.modal or self.popup))
        if closed:
            self._show = False
            self.context.queue_callback_noarg(self.on_close_callback,
                                              self)
        self.show_update_requested = False

        if self._handler is not None:
            self._handler.run_handler(self, self.state)


"""
Textures
"""



cdef class Texture(baseItem):
    def __cinit__(self):
        self.hint_dynamic = False
        self.dynamic = False
        self.allocated_texture = NULL
        self._width = 0
        self._height = 0
        self._num_chans = 0
        self.filtering_mode = 0

    def __delalloc__(self):
        # Note: textures might be referenced during imgui rendering.
        # Thus we must wait there is no rendering to free a texture.
        if self.allocated_texture != NULL:
            if not(self.context.imgui_mutex.try_lock()):
                with nogil: # rendering can take some time so avoid holding the gil
                    self.context.imgui_mutex.lock()
            mvMakeRenderingContextCurrent(dereference(self.context.viewport.viewport))
            mvFreeTexture(self.allocated_texture)
            mvReleaseRenderingContext(dereference(self.context.viewport.viewport))
            self.context.imgui_mutex.unlock()

    def configure(self, *args, **kwargs):
        if len(args) == 1:
            self.set_content(np.ascontiguousarray(args[0]))
        elif len(args) != 0:
            raise ValueError("Invalid arguments passed to Texture. Expected content")
        self.filtering_mode = 1 if kwargs.pop("nearest_neighbor_upsampling", False) else 0
        return super().configure(**kwargs)

    @property
    def hint_dynamic(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._hint_dynamic
    @hint_dynamic.setter
    def hint_dynamic(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._hint_dynamic = value
    @property
    def nearest_neighbor_upsampling(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return True if self.filtering_mode == 1 else 0
    @nearest_neighbor_upsampling.setter
    def nearest_neighbor_upsampling(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.filtering_mode = 1 if value else 0
    @property
    def width(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._width
    @property
    def height(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._height
    @property
    def num_chans(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._num_chans

    def set_value(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.set_content(np.ascontiguousarray(value))

    cdef void set_content(self, cnp.ndarray content):
        # The write mutex is to ensure order of processing of set_content
        # as we might release the item mutex to wait for imgui to render
        cdef unique_lock[recursive_mutex] m
        cdef unique_lock[recursive_mutex] m2
        lock_gil_friendly(m, self.write_mutex)
        lock_gil_friendly(m2, self.mutex)
        if content.ndim > 3 or content.ndim == 0:
            raise ValueError("Invalid number of texture dimensions")
        cdef int height = 1
        cdef int width = 1
        cdef int num_chans = 1
        assert(content.flags['C_CONTIGUOUS'])
        if content.ndim >= 1:
            height = content.shape[0]
        if content.ndim >= 2:
            width = content.shape[1]
        if content.ndim >= 3:
            num_chans = content.shape[2]
        if width * height * num_chans == 0:
            raise ValueError("Cannot set empty texture")

        # TODO: there must be a faster test
        if not(content.dtype == np.float32 or content.dtype == np.uint8):
            content = np.ascontiguousarray(content, dtype=np.float32)

        cdef bint reuse = self.allocated_texture != NULL
        reuse = reuse and (self._width != width or self._height != height or self._num_chans != num_chans)
        cdef unsigned buffer_type = 1 if content.dtype == np.uint8 else 0
        with nogil:
            if self.allocated_texture != NULL and not(reuse):
                # We must wait there is no rendering since the current rendering might reference the texture
                # Release current lock to not block rendering
                # Wait we can prevent rendering
                if not(self.context.imgui_mutex.try_lock()):
                    m2.unlock()
                    # rendering can take some time, fortunately we avoid holding the gil
                    self.context.imgui_mutex.lock()
                    m2.lock()
                mvMakeRenderingContextCurrent(dereference(self.context.viewport.viewport))
                mvFreeTexture(self.allocated_texture)
                self.context.imgui_mutex.unlock()
                self.allocated_texture = NULL
            else:
                mvMakeRenderingContextCurrent(dereference(self.context.viewport.viewport))

            # Note we don't need the imgui mutex to create or upload textures.
            # In the case of GL, as only one thread can access GL data at a single
            # time, MakeRenderingContextCurrent and ReleaseRenderingContext enable
            # to upload/create textures from various threads. They hold a mutex.
            # That mutex is held in the relevant parts of frame rendering.

            self._width = width
            self._height = height
            self._num_chans = num_chans

            if not(reuse):
                self.dynamic = self._hint_dynamic
                self.allocated_texture = mvAllocateTexture(width, height, num_chans, self.dynamic, buffer_type, self.filtering_mode)

            if self.dynamic:
                mvUpdateDynamicTexture(self.allocated_texture, width, height, num_chans, buffer_type, <void*>content.data)
            else:
                mvUpdateStaticTexture(self.allocated_texture, width, height, num_chans, buffer_type, <void*>content.data)
            mvReleaseRenderingContext(dereference(self.context.viewport.viewport))

cdef class baseTheme(baseItem):
    """
    Base theme element. Contains a set of theme elements
    to apply for a given category (color, style)/(imgui/implot/imnode)
    """
    def __cinit__(self):
        self.element_child_category = child_type.cat_theme
        self.can_have_sibling = True
        self.enabled = True
    def configure(self, **kwargs):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.enabled = kwargs.pop("enabled", self.enabled)
        self.enabled = kwargs.pop("show", self.enabled)
        return super().configure(**kwargs)
    @property
    def enabled(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.enabled
    @enabled.setter
    def enabled(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.enabled = value
    # should be always defined by subclass
    cdef void push(self) noexcept nogil:
        return
    cdef void pop(self) noexcept nogil:
        return
    cdef void push_to_list(self, vector[theme_action]& v) noexcept nogil:
        return

"""
Plots
"""

# BaseItem that has has no parent/child nor sibling
cdef class PlotAxisConfig(baseItem):
    def __cinit__(self):
        self.state.can_be_hovered = True
        self.state.can_be_clicked = True
        self._enabled = True
        self._scale = AxisScale.linear
        self._tick_format = b""
        self.flags = 0
        self._min = 0
        self._max = 1
        self.last_frame_minmax_update = -1
        self._constraint_min = -INFINITY
        self._constraint_max = INFINITY
        self._zoom_min = 0
        self._zoom_max = INFINITY
        self._handler = None

    @property
    def enabled(self):
        """
        Whether elements using this axis should
        be drawn.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._enabled

    @enabled.setter
    def enabled(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._enabled = value

    @property
    def scale(self):
        """
        Current AxisScale.
        Default is AxisScale.linear
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._scale

    @scale.setter
    def scale(self, AxisScale value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if value == AxisScale.linear or \
           value == AxisScale.time or \
           value == AxisScale.log10 or\
           value == AxisScale.symlog:
            self._scale = value
        else:
            raise ValueError("Invalid scale. Expecting an AxisScale")

    @property
    def min(self):
        """
        Current minimum of the range displayed.
        Do not set max <= min. Set invert to change
        the axis order.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._min

    @min.setter
    def min(self, double value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._min = value
        self.last_frame_minmax_update = self.context.viewport.frame_count

    @property
    def max(self):
        """
        Current maximum of the range displayed.
        Do not set max <= min. Set invert to change
        the axis order.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._max

    @max.setter
    def max(self, double value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._max = value
        self.last_frame_minmax_update = self.context.viewport.frame_count

    @property
    def constraint_min(self):
        """
        Constraint on the minimum value
        of min.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._constraint_min

    @constraint_min.setter
    def constraint_min(self, double value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._constraint_min = value

    @property
    def constraint_max(self):
        """
        Constraint on the maximum value
        of max.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._constraint_max

    @constraint_max.setter
    def constraint_max(self, double value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._constraint_max = value

    @property
    def zoom_min(self):
        """
        Constraint on the minimum value
        of the zoom
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._zoom_min

    @zoom_min.setter
    def zoom_min(self, double value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._zoom_min = value

    @property
    def zoom_max(self):
        """
        Constraint on the maximum value
        of the zoom
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._zoom_max

    @zoom_max.setter
    def zoom_max(self, double value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._zoom_max = value

    @property
    def no_label(self):
        """
        Writable attribute to not render the axis label
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_NoLabel) != 0

    @no_label.setter
    def no_label(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_NoLabel
        if value:
            self.flags |= implot.ImPlotAxisFlags_NoLabel

    @property
    def no_gridlines(self):
        """
        Writable attribute to not render grid lines
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_NoGridLines) != 0

    @no_gridlines.setter
    def no_gridlines(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_NoGridLines
        if value:
            self.flags |= implot.ImPlotAxisFlags_NoGridLines

    @property
    def no_tick_marks(self):
        """
        Writable attribute to not render tick marks
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_NoTickMarks) != 0

    @no_tick_marks.setter
    def no_tick_marks(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_NoTickMarks
        if value:
            self.flags |= implot.ImPlotAxisFlags_NoTickMarks

    @property
    def no_tick_labels(self):
        """
        Writable attribute to not render tick labels
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_NoTickLabels) != 0

    @no_tick_labels.setter
    def no_tick_labels(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_NoTickLabels
        if value:
            self.flags |= implot.ImPlotAxisFlags_NoTickLabels

    @property
    def no_initial_fit(self):
        """
        Writable attribute to disable fitting the extent
        of the axis to the data on the first frame.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_NoInitialFit) != 0

    @no_initial_fit.setter
    def no_initial_fit(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_NoInitialFit
        if value:
            self.flags |= implot.ImPlotAxisFlags_NoInitialFit

    @property
    def no_menus(self):
        """
        Writable attribute to prevent right-click to
        open context menus.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_NoMenus) != 0

    @no_menus.setter
    def no_menus(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_NoMenus
        if value:
            self.flags |= implot.ImPlotAxisFlags_NoMenus

    @property
    def no_side_switch(self):
        """
        Writable attribute to prevent the user from switching
        the axis by dragging it.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_NoSideSwitch) != 0

    @no_side_switch.setter
    def no_side_switch(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_NoSideSwitch
        if value:
            self.flags |= implot.ImPlotAxisFlags_NoSideSwitch

    @property
    def no_highlight(self):
        """
        Writable attribute to not highlight the axis background
        when hovered or held
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_NoHighlight) != 0

    @no_highlight.setter
    def no_highlight(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_NoHighlight
        if value:
            self.flags |= implot.ImPlotAxisFlags_NoHighlight

    @property
    def opposite(self):
        """
        Writable attribute to render ticks and labels on
        the opposite side.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_Opposite) != 0

    @opposite.setter
    def opposite(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_Opposite
        if value:
            self.flags |= implot.ImPlotAxisFlags_Opposite

    @property
    def foreground_grid(self):
        """
        Writable attribute to render gridlines on top of
        the data rather than behind.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_Foreground) != 0

    @foreground_grid.setter
    def foreground_grid(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_Foreground
        if value:
            self.flags |= implot.ImPlotAxisFlags_Foreground

    @property
    def invert(self):
        """
        Writable attribute to invert the values of the axis
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_Invert) != 0

    @invert.setter
    def invert(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_Invert
        if value:
            self.flags |= implot.ImPlotAxisFlags_Invert

    @property
    def auto_fit(self):
        """
        Writable attribute to force the axis to fit its range
        to the data every frame.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_AutoFit) != 0

    @auto_fit.setter
    def auto_fit(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_AutoFit
        if value:
            self.flags |= implot.ImPlotAxisFlags_AutoFit

    @property
    def restrict_fit_to_range(self):
        """
        Writable attribute to ignore points that are outside
        the visible region of the opposite axis when fitting
        this axis.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_RangeFit) != 0

    @restrict_fit_to_range.setter
    def restrict_fit_to_range(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_RangeFit
        if value:
            self.flags |= implot.ImPlotAxisFlags_RangeFit

    @property
    def pan_stretch(self):
        """
        Writable attribute that when set, if panning in a locked or
        constrained state, will cause the axis to stretch
        if possible.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_PanStretch) != 0

    @pan_stretch.setter
    def pan_stretch(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_PanStretch
        if value:
            self.flags |= implot.ImPlotAxisFlags_PanStretch

    @property
    def lock_min(self):
        """
        Writable attribute to lock the axis minimum value
        when panning/zooming
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_LockMin) != 0

    @lock_min.setter
    def lock_min(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_LockMin
        if value:
            self.flags |= implot.ImPlotAxisFlags_LockMin

    @property
    def lock_max(self):
        """
        Writable attribute to lock the axis maximum value
        when panning/zooming
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotAxisFlags_LockMax) != 0

    @lock_max.setter
    def lock_max(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotAxisFlags_LockMax
        if value:
            self.flags |= implot.ImPlotAxisFlags_LockMax

    cdef void setup(self, implot.ImAxis axis) noexcept nogil:
        """
        Apply the config to the target axis during plot
        setup
        """
        self.state.hovered = False
        self.state.visible = False

        if self._enabled == False:
            self.context.viewport.enabled_axes[axis] = False
            return
        self.context.viewport.enabled_axes[axis] = True
        # TODO label
        implot.SetupAxis(axis, NULL, self.flags)
        # we test the frame count to correctly support the
        # same config instance applied to several axes
        if self.last_frame_minmax_update >= self.context.viewport.frame_count-1:
            # enforce min < max
            self._max = max(self._max, self._min + 1e-12)
            implot.SetupAxisLimits(axis,
                                   self._min,
                                   self._max,
                                   implot.ImPlotCond_Always)
        # TODO format, ticks
        implot.SetupAxisScale(axis, self._scale)

        if self._constraint_min != -INFINITY or \
           self._constraint_max != INFINITY:
            self._constraint_max = max(self._constraint_max, self._constraint_min + 1e-12)
            implot.SetupAxisLimitsConstraints(axis,
                                              self._constraint_min,
                                              self._constraint_max)
        if self._zoom_min != 0 or \
           self._zoom_max != INFINITY:
            self._zoom_min = max(0, self._zoom_min)
            self._zoom_max = max(self._zoom_min, self._zoom_max)
            implot.SetupAxisZoomConstraints(axis,
                                            self._zoom_min,
                                            self._zoom_max)

    @property
    def hovered(self):
        """
        Readonly attribute: Is the mouse inside the axis label area
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.hovered

    @property
    def clicked(self):
        """
        Readonly attribute: has the item just been clicked.
        The returned value is a tuple of len 5 containing the individual test
        mouse buttons (up to 5 buttons)
        If True, the attribute is reset the next frame. It's better to rely
        on handlers to catch this event.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return tuple(self.state.clicked)

    @property
    def mouse_coord(self):
        """
        Readonly attribute:
        The last estimated mouse position in plot space
        for this axis.
        Beware not to assign the same instance of
        PlotAxisConfig to several axes if you plan on using
        this.
        The mouse position is updated everytime the plot is
        drawn and the axis is enabled.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._mouse_coord

    @property
    def handler(self):
        """
        Writable attribute: bound handler for the axis.
        Only visible, hovered and clicked handlers are compatible.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._handler

    @handler.setter
    def handler(self, baseHandler value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        # Check the list of handlers can use our states. Else raise error
        value.check_bind(self, self.state)
        # yes: bind
        self._handler = value

    cdef void after_draw(self, implot.ImAxis axis) noexcept nogil:
        """
        Update states, etc. after the elements were drawn
        """
        cdef implot.ImPlotRect rect
        if axis <= implot.ImAxis_X3:
            rect = implot.GetPlotLimits(axis, implot.IMPLOT_AUTO)
            self._min = rect.X.Min
            self._max = rect.X.Max
            self._mouse_coord = implot.GetPlotMousePos(axis, implot.IMPLOT_AUTO).x
        else:
            rect = implot.GetPlotLimits(implot.IMPLOT_AUTO, axis)
            self._min = rect.Y.Min
            self._max = rect.Y.Max
            self._mouse_coord = implot.GetPlotMousePos(implot.IMPLOT_AUTO, axis).y

        # DPG does update flags.. why ?
        cdef bint hovered = implot.IsAxisHovered(axis)
        cdef int i
        for i in range(<int>imgui.ImGuiMouseButton_COUNT):
            self.state.clicked[i] = hovered and imgui.IsMouseClicked(i, False)
            self.state.double_clicked[i] = hovered and imgui.IsMouseDoubleClicked(i)
        cdef bint backup_hovered = self.state.hovered
        self.state.hovered = hovered
        if self._handler is not None:
            self._handler.run_handler(self, self.state)
        if not(backup_hovered) or self.state.hovered:
            return
        # Restore correct states
        # We do it here and not above to trigger the handlers only once
        self.state.hovered |= backup_hovered
        for i in range(<int>imgui.ImGuiMouseButton_COUNT):
            self.state.clicked[i] = self.state.hovered and imgui.IsMouseClicked(i, False)
            self.state.double_clicked[i] = self.state.hovered and imgui.IsMouseDoubleClicked(i)

    cdef void set_hidden(self) noexcept nogil:
        self.state.hovered = False
        cdef int i
        for i in range(<int>imgui.ImGuiMouseButton_COUNT):
            self.state.clicked[i] = False
            self.state.double_clicked[i] = False

cdef class PlotLegendConfig(baseItem):
    def __cinit__(self):
        self._show = True
        self._location = LegendLocation.northwest
        self.flags = 0

    @property
    def show(self):
        """
        Whether the legend is shown or hidden
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._show

    @show.setter
    def show(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._show = value

    @property
    def location(self):
        """
        Position of the legend.
        Default is LegendLocation.northwest
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._location

    @location.setter
    def location(self, LegendLocation value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if value == LegendLocation.center or \
           value == LegendLocation.north or \
           value == LegendLocation.south or \
           value == LegendLocation.west or \
           value == LegendLocation.east or \
           value == LegendLocation.northeast or \
           value == LegendLocation.northwest or \
           value == LegendLocation.southeast or \
           value == LegendLocation.southwest:
            self._location = value
        else:
            raise ValueError("Invalid location. Must be a LegendLocation")

    @property
    def no_buttons(self):
        """
        Writable attribute to prevent legend icons
        tot function as hide/show buttons
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotLegendFlags_NoButtons) != 0

    @no_buttons.setter
    def no_buttons(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotLegendFlags_NoButtons
        if value:
            self.flags |= implot.ImPlotLegendFlags_NoButtons

    @property
    def no_highlight_item(self):
        """
        Writable attribute to disable highlighting plot items
        when their legend entry is hovered
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotLegendFlags_NoHighlightItem) != 0

    @no_highlight_item.setter
    def no_highlight_item(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotLegendFlags_NoHighlightItem
        if value:
            self.flags |= implot.ImPlotLegendFlags_NoHighlightItem

    @property
    def no_highlight_axis(self):
        """
        Writable attribute to disable highlighting axes
        when their legend entry is hovered
        (only relevant if x/y-axis count > 1)
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotLegendFlags_NoHighlightAxis) != 0

    @no_highlight_axis.setter
    def no_highlight_axis(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotLegendFlags_NoHighlightAxis
        if value:
            self.flags |= implot.ImPlotLegendFlags_NoHighlightAxis

    @property
    def no_menus(self):
        """
        Writable attribute to disable right-clicking
        to open context menus.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotLegendFlags_NoMenus) != 0

    @no_menus.setter
    def no_menus(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotLegendFlags_NoMenus
        if value:
            self.flags |= implot.ImPlotLegendFlags_NoMenus

    @property
    def outside(self):
        """
        Writable attribute to render the legend outside
        of the plot area
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotLegendFlags_Outside) != 0

    @outside.setter
    def outside(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotLegendFlags_Outside
        if value:
            self.flags |= implot.ImPlotLegendFlags_Outside

    @property
    def horizontal(self):
        """
        Writable attribute to display the legend entries
        horizontally rather than vertically
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotLegendFlags_Horizontal) != 0

    @horizontal.setter
    def horizontal(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotLegendFlags_Horizontal
        if value:
            self.flags |= implot.ImPlotLegendFlags_Horizontal

    @property
    def sorted(self):
        """
        Writable attribute to display the legend entries
        in alphabetical order
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotLegendFlags_Sort) != 0

    @sorted.setter
    def sorted(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotLegendFlags_Sort
        if value:
            self.flags |= implot.ImPlotLegendFlags_Sort

    cdef void setup(self) noexcept nogil:
        implot.SetupLegend(self._location, self.flags)
        # NOTE: Setup does just fill the location and flags.
        # No item is created at this point,
        # and thus we don't push fonts, check states, etc.

    cdef void after_draw(self) noexcept nogil:
        # DPG does update legend location and flags... why ?
        return


cdef class Plot(uiItem):
    def __cinit__(self, context, *args, **kwargs):
        self.can_have_plot_element_child = True
        self.state.can_be_clicked = True
        self.state.can_be_hovered = True
        self._X1 = PlotAxisConfig(context)
        self._X2 = PlotAxisConfig(context, enabled=False)
        self._X3 = PlotAxisConfig(context, enabled=False)
        self._Y1 = PlotAxisConfig(context)
        self._Y2 = PlotAxisConfig(context, enabled=False)
        self._Y3 = PlotAxisConfig(context, enabled=False)
        self._legend = PlotLegendConfig(context)
        self._pan_button = imgui.ImGuiMouseButton_Left
        self._pan_modifier = 0
        self._fit_button = imgui.ImGuiMouseButton_Left
        self._menu_button = imgui.ImGuiMouseButton_Right
        self._select_button = imgui.ImGuiMouseButton_Right
        self._select_mod = 0
        self._select_cancel_button = imgui.ImGuiMouseButton_Left
        self._override_mod = imgui.ImGuiMod_Ctrl
        self._query_toggle_mod = imgui.ImGuiMod_Ctrl
        self._select_horz_mod = imgui.ImGuiMod_Alt
        self._select_vert_mod = imgui.ImGuiMod_Shift
        self._zoom_mod = 0
        self._zoom_rate = 0.1
        self._query_enabled = True
        self._query_color = 255*256*256
        self._min_query_rects = 1
        self._max_query_rects = 1
        self._use_local_time = False
        self._use_ISO8601 = False
        self._use_24hour_clock = False

    @property
    def X1(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._X1

    @X1.setter
    def X1(self, PlotAxisConfig value not None):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._X1 = value

    @property
    def X2(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._X2

    @X2.setter
    def X2(self, PlotAxisConfig value not None):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._X2 = value

    @property
    def X3(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._X3

    @X3.setter
    def X3(self, PlotAxisConfig value not None):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._X3 = value

    @property
    def Y1(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._Y1

    @Y1.setter
    def Y1(self, PlotAxisConfig value not None):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._Y1 = value

    @property
    def Y2(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._Y2

    @Y2.setter
    def Y2(self, PlotAxisConfig value not None):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._Y2 = value

    @property
    def Y3(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._Y3

    @Y3.setter
    def Y3(self, PlotAxisConfig value not None):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._Y3 = value

    @property
    def legend_config(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._legend

    @legend_config.setter
    def legend_config(self, PlotLegendConfig value not None):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._legend = value

    @property
    def pan_button(self):
        """
        Button that when held enables to navigate inside the plot
        Default is the left mouse button.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._pan_button

    @pan_button.setter
    def pan_button(self, int button):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if button < 0 or button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        self._pan_button = button

    @property
    def pan_mod(self):
        """
        Modifier combination (shift/ctrl/alt/super) that must be
        pressed for pan_button to have effect.
        Default is no modifier.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._pan_modifier

    @pan_mod.setter
    def pan_mod(self, int modifier):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if (modifier & ~imgui.ImGuiMod_Mask_) != 0:
            raise ValueError("pan_mod must be a combinaison of modifiers")
        self._pan_modifier = modifier

    @property
    def fit_button(self):
        """
        Button that must be double-clicked to initiate
        a fit of the axes to the displayed data.
        Default is the left mouse button.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._fit_button

    @fit_button.setter
    def fit_button(self, int button):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if button < 0 or button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        self._fit_button = button

    @property
    def menu_button(self):
        """
        Button that opens context menus
        (if enabled) when clicked.
        Default is the right mouse button.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._menu_button

    @menu_button.setter
    def menu_button(self, int button):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if button < 0 or button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        self._menu_button = button

    @property
    def select_button(self):
        """
        Button that begins box selection when
        pressed and confirms selection when released
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._select_button

    @select_button.setter
    def select_button(self, int button):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if button < 0 or button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        self._select_button = button

    @property
    def select_mod(self):
        """
        Modifier combination (shift/ctrl/alt/super) that must be
        pressed for select_button to have effect.
        Default is no modifier.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._select_mod

    @select_mod.setter
    def select_mod(self, int modifier):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if (modifier & ~imgui.ImGuiMod_Mask_) != 0:
            raise ValueError("select_mod must be a combinaison of modifiers")
        self._select_mod = modifier

    @property
    def select_cancel_button(self):
        """
        Button that cancels active box selection
        when pressed; cannot be same as Select
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._select_cancel_button

    @select_cancel_button.setter
    def select_cancel_button(self, int button):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if button < 0 or button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        self._select_cancel_button = button

    @property
    def override_mod(self):
        """
        Modifier combination (shift/ctrl/alt/super) that
        when held, all input is ignored; used to enable
        axis/plots as DND sources.
        Default is the Ctrl button
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._override_mod

    @override_mod.setter
    def override_mod(self, int modifier):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if (modifier & ~imgui.ImGuiMod_Mask_) != 0:
            raise ValueError("override_mod must be a combinaison of modifiers")
        self._override_mod = modifier

    @property
    def query_toggle_mod(self):
        """
        Modifier combination (shift/ctrl/alt/super) that
        when held during selection, adds a query rect;
        has higher priority than override_mod.
        Default is the Ctrl button.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._query_toggle_mod

    @query_toggle_mod.setter
    def query_toggle_mod(self, int modifier):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if (modifier & ~imgui.ImGuiMod_Mask_) != 0:
            raise ValueError("query_toggle_mod must be a combinaison of modifiers")
        self._query_toggle_mod = modifier

    @property
    def select_horz_mod(self):
        """
        Modifier combination (shift/ctrl/alt/super) that
        expands active box selection horizontally to plot
        edge when held.
        Default is the Alt button.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._select_horz_mod

    @select_horz_mod.setter
    def select_horz_mod(self, int modifier):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if (modifier & ~imgui.ImGuiMod_Mask_) != 0:
            raise ValueError("select_horz_mod must be a combinaison of modifiers")
        self._select_horz_mod = modifier

    @property
    def select_vert_mod(self):
        """
        Modifier combination (shift/ctrl/alt/super) that
        expands active box selection vertically to plot
        edge when held.
        Default is the Shift button.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._select_vert_mod

    @select_vert_mod.setter
    def select_vert_mod(self, int modifier):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if (modifier & ~imgui.ImGuiMod_Mask_) != 0:
            raise ValueError("select_vert_mod must be a combinaison of modifiers")
        self._select_vert_mod = modifier

    @property
    def zoom_mod(self):
        """
        Modifier combination (shift/ctrl/alt/super) that
        must be hold for the mouse wheel to trigger a zoom
        of the plot.
        Default is no modifier.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._zoom_mod

    @zoom_mod.setter
    def zoom_mod(self, int modifier):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if (modifier & ~imgui.ImGuiMod_Mask_) != 0:
            raise ValueError("zoom_mod must be a combinaison of modifiers")
        self._zoom_mod = modifier

    @property
    def zoom_rate(self):
        """
        Zoom rate for scroll (e.g. 0.1 = 10% plot range every
        scroll click);
        make negative to invert.
        Default is 0.1
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._zoom_rate

    @zoom_rate.setter
    def zoom_rate(self, float value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._zoom_rate = value

    @property
    def query_enabled(self):
        """
        Enables query rects when Select is held
        Default is True
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._query_enabled

    @query_enabled.setter
    def query_enabled(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._query_enabled = value

    @property
    def query_color(self):
        """
        Color of the query rects.
        Default is green.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef float[4] color
        unparse_color(color, self._query_color)
        return tuple(color)

    @query_color.setter
    def query_color(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._query_color = parse_color(value)

    @property
    def min_query_rects(self):
        """
        Minimum number of query rects that
        can be active at once.
        Default is 1.
        """
        return self._min_query_rects

    @min_query_rects.setter
    def min_query_rects(self, int value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._min_query_rects = value

    @property
    def max_query_rects(self):
        """
        Maximum number of query rects that
        can be active at once.
        Default is 1.
        """
        return self._max_query_rects

    @max_query_rects.setter
    def max_query_rects(self, int value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._max_query_rects = value

    @property
    def use_local_time(self):
        """
        If set, axis labels will be formatted for the system
        timezone when ImPlotAxisFlag_Time is enabled.
        Default is False.
        """
        return self._use_local_time

    @use_local_time.setter
    def use_local_time(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._use_local_time = value

    @property
    def use_ISO8601(self):
        """
        If set, dates will be formatted according to ISO 8601
        where applicable (e.g. YYYY-MM-DD, YYYY-MM,
        --MM-DD, etc.)
        Default is False.
        """
        return self._use_ISO8601

    @use_ISO8601.setter
    def use_ISO8601(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._use_ISO8601 = value

    @property
    def use_24hour_clock(self):
        """
        If set, times will be formatted using a 24 hour clock.
        Default is False
        """
        return self._use_24hour_clock

    @use_24hour_clock.setter
    def use_24hour_clock(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._use_24hour_clock = value

    @property
    def no_title(self):
        """
        Writable attribute to disable the display of the
        plot title
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotFlags_NoTitle) != 0

    @no_title.setter
    def no_title(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotFlags_NoTitle
        if value:
            self.flags |= implot.ImPlotFlags_NoTitle

    @property
    def no_menus(self):
        """
        Writable attribute to disable the user interactions
        to open the context menus
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotFlags_NoMenus) != 0

    @no_menus.setter
    def no_menus(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotFlags_NoMenus
        if value:
            self.flags |= implot.ImPlotFlags_NoMenus

    @property
    def no_box_select(self):
        """
        Writable attribute to disable the user interactions
        to box-select
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotFlags_NoBoxSelect) != 0

    @no_box_select.setter
    def no_box_select(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotFlags_NoBoxSelect
        if value:
            self.flags |= implot.ImPlotFlags_NoBoxSelect

    @property
    def no_mouse_pos(self):
        """
        Writable attribute to disable the display of the
        mouse position
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotFlags_NoMouseText) != 0

    @no_mouse_pos.setter
    def no_mouse_pos(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotFlags_NoMouseText
        if value:
            self.flags |= implot.ImPlotFlags_NoMouseText

    @property
    def crosshairs(self):
        """
        Writable attribute to replace the default mouse
        cursor by a crosshair when hovered
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotFlags_Crosshairs) != 0

    @crosshairs.setter
    def crosshairs(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotFlags_Crosshairs
        if value:
            self.flags |= implot.ImPlotFlags_Crosshairs

    @property
    def equal_aspects(self):
        """
        Writable attribute to constrain x/y axes
        pairs to have the same units/pixels
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotFlags_Equal) != 0

    @equal_aspects.setter
    def equal_aspects(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotFlags_Equal
        if value:
            self.flags |= implot.ImPlotFlags_Equal

    @property
    def no_inputs(self):
        """
        Writable attribute to disable user interactions with
        the plot.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotFlags_NoInputs) != 0

    @no_inputs.setter
    def no_inputs(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotFlags_NoInputs
        if value:
            self.flags |= implot.ImPlotFlags_NoInputs

    @property
    def no_frame(self):
        """
        Writable attribute to disable the drawing of the
        imgui frame.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotFlags_NoFrame) != 0

    @no_frame.setter
    def no_frame(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotFlags_NoFrame
        if value:
            self.flags |= implot.ImPlotFlags_NoFrame

    @property
    def no_legend(self):
        """
        Writable attribute to disable the display of the
        legend
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotFlags_NoLegend) != 0

    @no_legend.setter
    def no_legend(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotFlags_NoLegend
        if value:
            self.flags |= implot.ImPlotFlags_NoLegend

    cdef bint draw_item(self) noexcept nogil:
        cdef int i
        implot.GetStyle().UseLocalTime = self._use_local_time
        implot.GetStyle().UseISO8601 = self._use_ISO8601
        implot.GetStyle().Use24HourClock = self._use_24hour_clock
        implot.GetInputMap().Pan = self._pan_button
        implot.GetInputMap().Fit = self._fit_button
        implot.GetInputMap().Select = self._select_button
        implot.GetInputMap().SelectCancel = self._select_cancel_button
        implot.GetInputMap().Menu = self._menu_button
        implot.GetInputMap().ZoomRate = self._zoom_rate
        implot.GetInputMap().PanMod = self._pan_modifier
        implot.GetInputMap().SelectMod = self._select_mod
        implot.GetInputMap().ZoomMod = self._zoom_mod
        implot.GetInputMap().OverrideMod = self._override_mod
        implot.GetInputMap().SelectHorzMod = self._select_horz_mod
        implot.GetInputMap().SelectVertMod = self._select_vert_mod

        self._X1.mutex.lock()
        self._X2.mutex.lock()
        self._X3.mutex.lock()
        self._Y1.mutex.lock()
        self._Y2.mutex.lock()
        self._Y3.mutex.lock()
        self._legend.mutex.lock()

        # Check at least one axis of each is enabled ?

        if implot.BeginPlot(self.imgui_label.c_str(),
                            self.requested_size,
                            self.flags):
            # Setup axes
            self._X1.setup(implot.ImAxis_X1)
            self._X2.setup(implot.ImAxis_X2)
            self._X3.setup(implot.ImAxis_X3)
            self._Y1.setup(implot.ImAxis_Y1)
            self._Y2.setup(implot.ImAxis_Y2)
            self._Y3.setup(implot.ImAxis_Y3)

            # From DPG: workaround for stuck selection
            # Unsure why it should be done here and not above
            if (imgui.GetIO().KeyMods & self._query_toggle_mod) == imgui.GetIO().KeyMods and \
                (imgui.IsMouseDown(self._select_button) or imgui.IsMouseReleased(self._select_button)):
                implot.GetInputMap().OverrideMod = imgui.ImGuiMod_None

            # TODO: querying
            self._legend.setup()

            if self.last_plot_element_child is not None:
                self.last_plot_element_child.draw()
            self._X1.after_draw(implot.ImAxis_X1)
            self._X2.after_draw(implot.ImAxis_X2)
            self._X3.after_draw(implot.ImAxis_X3)
            self._Y1.after_draw(implot.ImAxis_Y1)
            self._Y2.after_draw(implot.ImAxis_Y2)
            self._Y3.after_draw(implot.ImAxis_Y3)
            self._legend.after_draw()
            self.state.hovered = implot.IsPlotHovered()
            #self.state.selected = implot.IsPlotSelected()
            #GetPlotSize
            #GetPlotPos
            for i in range(<int>imgui.ImGuiMouseButton_COUNT):
                self.state.clicked[i] = self.state.hovered and imgui.IsMouseClicked(i, False)
                self.state.double_clicked[i] = self.state.hovered and imgui.IsMouseDoubleClicked(i)
            implot.EndPlot()
        else:
            self.set_hidden_and_propagate()
            self._X1.set_hidden()
            self._X2.set_hidden()
            self._X3.set_hidden()
            self._Y1.set_hidden()
            self._Y2.set_hidden()
            self._Y3.set_hidden()
        self._X1.mutex.unlock()
        self._X2.mutex.unlock()
        self._X3.mutex.unlock()
        self._Y1.mutex.unlock()
        self._Y2.mutex.unlock()
        self._Y3.mutex.unlock()
        self._legend.mutex.unlock()
    # We don't need to restore the plot config as we
    # always overwrite it.


cdef class plotElement(baseItem):
    """
    Base class for plot children.

    Children of plot elements are rendered on a legend
    popup entry that gets shown an a right click (TODO configure)
    """
    def __cinit__(self):
        self.imgui_label = b'###%ld'% self.uuid
        self.user_label = ""
        self.state.can_be_hovered = True
        self.flags = implot.ImPlotItemFlags_None
        self.can_have_sibling = True
        self.can_have_widget_child = True
        self.element_child_category = child_type.cat_plot_element
        self._show = True
        self._axes = [implot.ImAxis_X1, implot.ImAxis_Y1]
        self._legend_button = imgui.ImGuiMouseButton_Right
        self._legend = True
        self._theme = None

    @property
    def show(self):
        """
        Writable attribute: Should the object be drawn/shown ?
        In case show is set to False, this disables any
        callback (for example the close callback won't be called
        if a window is hidden with show = False).
        In the case of items that can be closed,
        show is set to False automatically on close.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._show

    @show.setter
    def show(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._show = value

    @property
    def axes(self):
        """
        Writable attribute: (X axis, Y axis)
        used for this plot element.
        Default is (X1, Y1)
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return tuple(self._axes[0], self._axes[1])

    @axes.setter
    def axes(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef int axis_x, axis_y
        try:
            (axis_x, axis_y) = value
            assert(axis_x in [implot.ImAxis_X1,
                              implot.ImAxis_X2,
                              implot.ImAxis_X3])
            assert(axis_y in [implot.ImAxis_Y1,
                              implot.ImAxis_Y2,
                              implot.ImAxis_Y3])
        except Exception as e:
            raise ValueError("Axes must be a tuple of valid X/Y axes")
        self._axes[0] = axis_x
        self._axes[1] = axis_y

    @property
    def label(self):
        """
        Writable attribute: label assigned to the element
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.user_label

    @label.setter
    def label(self, str value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if value is None:
            self.user_label = ""
        else:
            self.user_label = value
        # Using ### means that imgui will ignore the user_label for
        # its internal ID of the object. Indeed else the ID would change
        # when the user label would change
        self.imgui_label = bytes(self.user_label, 'utf-8') + b'###%ld'% self.uuid

    @property
    def no_legend(self):
        """
        Writable attribute to disable the legend for this plot
        element
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return not(self._legend)

    @no_legend.setter
    def no_legend(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._legend = not(value)
        # unsure if needed
        self.flags &= ~implot.ImPlotItemFlags_NoLegend
        if value:
            self.flags |= implot.ImPlotItemFlags_NoLegend

    @property
    def ignore_fit(self):
        """
        Writable attribute to make this element
        be ignored during plot fits
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotItemFlags_NoFit) != 0

    @ignore_fit.setter
    def ignore_fit(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotItemFlags_NoFit
        if value:
            self.flags |= implot.ImPlotItemFlags_NoFit

    @property
    def legend_button(self):
        """
        Button that opens the legend entry for
        this element.
        Default is the right mouse button.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._legend_button

    @legend_button.setter
    def legend_button(self, int button):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if button < 0 or button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        self._legend_button = button

    @property
    def legend_handler(self):
        """
        Writable attribute: bound handler for the legend.
        Only visible and hovered handlers are compatible.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._handler

    @legend_handler.setter
    def legend_handler(self, baseHandler value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        # Check the list of handlers can use our states. Else raise error
        value.check_bind(self, self.state)
        # yes: bind
        self._handler = value

    @property
    def theme(self):
        """
        Writable attribute: theme for the legend and plot
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._theme

    @theme.setter
    def theme(self, baseTheme value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._theme = value

    cdef void draw(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)

        # Render siblings first
        if self._prev_sibling is not None:
            (<plotElement>self._prev_sibling).draw()

        # Check the axes are enabled
        if not(self.context.viewport.enabled_axes[self._axes[0]]) or \
           not(self.context.viewport.enabled_axes[self._axes[1]]):
            if self.last_widgets_child is not None:
                self.last_widgets_child.set_hidden_and_propagate()
            return

        # push theme, font
        self.context.viewport.push_pending_theme_actions(
            theme_enablers.t_enabled_any,
            theme_categories.t_plot
        )

        if self._theme is not None:
            self._theme.push()

        implot.SetAxes(self._axes[0], self._axes[1])
        self.draw_element()

        self.state.visible = False
        self.state.hovered = False
        if self._legend:
            if implot.BeginLegendPopup(self.imgui_label.c_str(),
                                       self._legend_button):
                if self.last_widgets_child is not None:
                    self.last_widgets_child.draw()
                self.state.visible = True
                implot.EndLegendPopup()
            self.state.hovered = implot.IsLegendEntryHovered(self.imgui_label.c_str())


        # pop theme, font
        if self._theme is not None:
            self._theme.pop()

        self.context.viewport.pop_applied_pending_theme_actions()

        if self._handler is not None:
            self._handler.run_handler(self, self.state)

    cdef void draw_element(self) noexcept nogil:
        return

cdef class plotElementXY(plotElement):
    def __cinit__(self):
        self._X = np.zeros(shape=(1,), dtype=np.float64)
        self._Y = np.zeros(shape=(1,), dtype=np.float64)

    @property
    def X(self):
        """Values on the X axis.

        By default, will try to use the passed array
        directly for its internal backing (no copy).
        Supported types for no copy are np.int32,
        np.float32, np.float64.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._X

    @X.setter
    def X(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef cnp.ndarray array = np.asarray(value).reshape([-1])
        # We don't support array of pointers. Must be data,
        # with eventually a non-standard stride
        # type must also be one of the supported types
        if cnp.PyArray_CHKFLAGS(array, cnp.NPY_ARRAY_ELEMENTSTRIDES) and \
           (cnp.PyArray_TYPE(array) == cnp.NPY_INT or \
            cnp.PyArray_TYPE(array) == cnp.NPY_FLOAT or \
            cnp.PyArray_TYPE(array) == cnp.NPY_DOUBLE):
            self._X = array
        else:
            self._X = np.ascontiguousarray(array, dtype=np.float64)

    @property
    def Y(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._Y

    @Y.setter
    def Y(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef cnp.ndarray array = np.asarray(value).reshape([-1])
        # We don't support array of pointers. Must be data,
        # with eventually a non-standard stride
        # type must also be one of the supported types
        if cnp.PyArray_CHKFLAGS(array, cnp.NPY_ARRAY_ELEMENTSTRIDES) and \
           (cnp.PyArray_TYPE(array) == cnp.NPY_INT or \
            cnp.PyArray_TYPE(array) == cnp.NPY_FLOAT or \
            cnp.PyArray_TYPE(array) == cnp.NPY_DOUBLE):
            self._Y = array
        else:
            self._Y = np.ascontiguousarray(array, dtype=np.float64)

    cdef void check_arrays(self) noexcept nogil:
        # X and Y must be same type and same stride
        if cnp.PyArray_TYPE(self._X) != cnp.PyArray_TYPE(self._Y):
            with gil:
                self._X = np.ascontiguousarray(self._X, dtype=np.float64)
                self._Y = np.ascontiguousarray(self._Y, dtype=np.float64)
        if cnp.PyArray_STRIDE(self._X, 0) != cnp.PyArray_STRIDE(self._Y, 0):
            with gil:
                self._X = np.ascontiguousarray(self._X, dtype=np.float64)
                self._Y = np.ascontiguousarray(self._Y, dtype=np.float64)

cdef class PlotLine(plotElementXY):
    @property
    def segments(self):
        """
        Plot segments rather than a full line
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotLineFlags_Segments) != 0

    @segments.setter
    def segments(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotLineFlags_Segments
        if value:
            self.flags |= implot.ImPlotLineFlags_Segments

    @property
    def loop(self):
        """
        Connect the first and last points
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotLineFlags_Loop) != 0

    @loop.setter
    def loop(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotLineFlags_Loop
        if value:
            self.flags |= implot.ImPlotLineFlags_Loop

    @property
    def skip_nan(self):
        """
        A NaN data point will be ignored instead of
        being rendered as missing data.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotLineFlags_SkipNaN) != 0

    @skip_nan.setter
    def skip_nan(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotLineFlags_SkipNaN
        if value:
            self.flags |= implot.ImPlotLineFlags_SkipNaN

    @property
    def no_clip(self):
        """
        Markers (if displayed) on the edge of a plot will not be clipped.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotLineFlags_NoClip) != 0

    @no_clip.setter
    def no_clip(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotLineFlags_NoClip
        if value:
            self.flags |= implot.ImPlotLineFlags_NoClip

    @property
    def shaded(self):
        """
        A filled region between the line and horizontal
        origin will be rendered.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotLineFlags_Shaded) != 0

    @shaded.setter
    def shaded(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotLineFlags_Shaded
        if value:
            self.flags |= implot.ImPlotLineFlags_Shaded

    cdef void draw_element(self) noexcept nogil:
        self.check_arrays()
        cdef int size = min(self._X.shape[0], self._Y.shape[0])
        if size == 0:
            return

        if cnp.PyArray_TYPE(self._X) == cnp.NPY_INT:
            implot.PlotLine[int](self.imgui_label.c_str(),
                                 <const int*>cnp.PyArray_DATA(self._X),
                                 <const int*>cnp.PyArray_DATA(self._Y),
                                 size,
                                 self.flags,
                                 0,
                                 cnp.PyArray_STRIDE(self._X, 0))
        elif cnp.PyArray_TYPE(self._X) == cnp.NPY_FLOAT:
            implot.PlotLine[float](self.imgui_label.c_str(),
                                   <const float*>cnp.PyArray_DATA(self._X),
                                   <const float*>cnp.PyArray_DATA(self._Y),
                                   size,
                                   self.flags,
                                   0,
                                   cnp.PyArray_STRIDE(self._X, 0))
        else:
            implot.PlotLine[double](self.imgui_label.c_str(),
                                    <const double*>cnp.PyArray_DATA(self._X),
                                    <const double*>cnp.PyArray_DATA(self._Y),
                                    size,
                                    self.flags,
                                    0,
                                    cnp.PyArray_STRIDE(self._X, 0))

cdef class plotElementXYY(plotElement):
    def __cinit__(self):
        self._X = np.zeros(shape=(1,), dtype=np.float64)
        self._Y1 = np.zeros(shape=(1,), dtype=np.float64)
        self._Y2 = np.zeros(shape=(1,), dtype=np.float64)

    @property
    def X(self):
        """Values on the X axis.

        By default, will try to use the passed array
        directly for its internal backing (no copy).
        Supported types for no copy are np.int32,
        np.float32, np.float64.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._X

    @X.setter
    def X(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef cnp.ndarray array = np.asarray(value).reshape([-1])
        # We don't support array of pointers. Must be data,
        # with eventually a non-standard stride
        # type must also be one of the supported types
        if cnp.PyArray_CHKFLAGS(array, cnp.NPY_ARRAY_ELEMENTSTRIDES) and \
           (cnp.PyArray_TYPE(array) == cnp.NPY_INT or \
            cnp.PyArray_TYPE(array) == cnp.NPY_FLOAT or \
            cnp.PyArray_TYPE(array) == cnp.NPY_DOUBLE):
            self._X = array
        else:
            self._X = np.ascontiguousarray(array, dtype=np.float64)

    @property
    def Y1(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._Y1

    @Y1.setter
    def Y1(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef cnp.ndarray array = np.asarray(value).reshape([-1])
        # We don't support array of pointers. Must be data,
        # with eventually a non-standard stride
        # type must also be one of the supported types
        if cnp.PyArray_CHKFLAGS(array, cnp.NPY_ARRAY_ELEMENTSTRIDES) and \
           (cnp.PyArray_TYPE(array) == cnp.NPY_INT or \
            cnp.PyArray_TYPE(array) == cnp.NPY_FLOAT or \
            cnp.PyArray_TYPE(array) == cnp.NPY_DOUBLE):
            self._Y1 = array
        else:
            self._Y1 = np.ascontiguousarray(array, dtype=np.float64)

    @property
    def Y2(self):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._Y2

    @Y2.setter
    def Y2(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef cnp.ndarray array = np.asarray(value).reshape([-1])
        # We don't support array of pointers. Must be data,
        # with eventually a non-standard stride
        # type must also be one of the supported types
        if cnp.PyArray_CHKFLAGS(array, cnp.NPY_ARRAY_ELEMENTSTRIDES) and \
           (cnp.PyArray_TYPE(array) == cnp.NPY_INT or \
            cnp.PyArray_TYPE(array) == cnp.NPY_FLOAT or \
            cnp.PyArray_TYPE(array) == cnp.NPY_DOUBLE):
            self._Y2 = array
        else:
            self._Y2 = np.ascontiguousarray(array, dtype=np.float64)

    cdef void check_arrays(self) noexcept nogil:
        # X, Y1 and Y2 must be same type and same stride
        if cnp.PyArray_TYPE(self._X) != cnp.PyArray_TYPE(self._Y1) or \
           cnp.PyArray_TYPE(self._X) != cnp.PyArray_TYPE(self._Y2):
            with gil:
                self._X = np.ascontiguousarray(self._X, dtype=np.float64)
                self._Y1 = np.ascontiguousarray(self._Y1, dtype=np.float64)
                self._Y2 = np.ascontiguousarray(self._Y2, dtype=np.float64)
        if cnp.PyArray_STRIDE(self._X, 0) != cnp.PyArray_STRIDE(self._Y1, 0) or \
           cnp.PyArray_STRIDE(self._X, 0) != cnp.PyArray_STRIDE(self._Y2, 0):
            with gil:
                self._X = np.ascontiguousarray(self._X, dtype=np.float64)
                self._Y1 = np.ascontiguousarray(self._Y1, dtype=np.float64)
                self._Y2 = np.ascontiguousarray(self._Y2, dtype=np.float64)

cdef class PlotShadedLine(plotElementXYY):
    cdef void draw_element(self) noexcept nogil:
        self.check_arrays()
        cdef int size = min(min(self._X.shape[0], self._Y1.shape[0]), self._Y2.shape[0])
        if size == 0:
            return

        if cnp.PyArray_TYPE(self._X) == cnp.NPY_INT:
            implot.PlotShaded[int](self.imgui_label.c_str(),
                                   <const int*>cnp.PyArray_DATA(self._X),
                                   <const int*>cnp.PyArray_DATA(self._Y1),
                                   <const int*>cnp.PyArray_DATA(self._Y2),
                                   size,
                                   self.flags,
                                   0,
                                   cnp.PyArray_STRIDE(self._X, 0))
        elif cnp.PyArray_TYPE(self._X) == cnp.NPY_FLOAT:
            implot.PlotShaded[float](self.imgui_label.c_str(),
                                     <const float*>cnp.PyArray_DATA(self._X),
                                     <const float*>cnp.PyArray_DATA(self._Y1),
                                     <const float*>cnp.PyArray_DATA(self._Y2),
                                     size,
                                     self.flags,
                                     0,
                                     cnp.PyArray_STRIDE(self._X, 0))
        else:
            implot.PlotShaded[double](self.imgui_label.c_str(),
                                      <const double*>cnp.PyArray_DATA(self._X),
                                      <const double*>cnp.PyArray_DATA(self._Y1),
                                      <const double*>cnp.PyArray_DATA(self._Y2),
                                      size,
                                      self.flags,
                                      0,
                                      cnp.PyArray_STRIDE(self._X, 0))

"""
To avoid linking to imgui in the other .so
"""

cdef imgui.ImU32 imgui_ColorConvertFloat4ToU32(imgui.ImVec4 color_float4) noexcept nogil:
    return imgui.ColorConvertFloat4ToU32(color_float4)

cdef imgui.ImVec4 imgui_ColorConvertU32ToFloat4(imgui.ImU32 color_uint) noexcept nogil:
    return imgui.ColorConvertU32ToFloat4(color_uint)

cdef const char* imgui_GetStyleColorName(int i) noexcept nogil:
    return imgui.GetStyleColorName(<imgui.ImGuiCol>i)

cdef void imgui_PushStyleColor(int i, imgui.ImU32 val) noexcept nogil:
    imgui.PushStyleColor(<imgui.ImGuiCol>i, val)

cdef void imgui_PopStyleColor(int count) noexcept nogil:
    imgui.PopStyleColor(count)

cdef void imnodes_PushStyleColor(int i, imgui.ImU32 val) noexcept nogil:
    imnodes.PushColorStyle(<imnodes.ImNodesCol>i, val)

cdef void imnodes_PopStyleColor(int count) noexcept nogil:
    cdef int i
    for i in range(count):
        imnodes.PopColorStyle()

cdef const char* implot_GetStyleColorName(int i) noexcept nogil:
    return implot.GetStyleColorName(<implot.ImPlotCol>i)

cdef void implot_PushStyleColor(int i, imgui.ImU32 val) noexcept nogil:
    implot.PushStyleColor(<implot.ImPlotCol>i, val)

cdef void implot_PopStyleColor(int count) noexcept nogil:
    implot.PopStyleColor(count)

cdef void imgui_PushStyleVar1(int i, float val) noexcept nogil:
    imgui.PushStyleVar(<imgui.ImGuiStyleVar>i, val)

cdef void imgui_PushStyleVar2(int i, imgui.ImVec2 val) noexcept nogil:
    imgui.PushStyleVar(<imgui.ImGuiStyleVar>i, val)

cdef void imgui_PopStyleVar(int count) noexcept nogil:
    imgui.PopStyleVar(count)

cdef void implot_PushStyleVar0(int i, int val) noexcept nogil:
    implot.PushStyleVar(<implot.ImPlotStyleVar>i, val)

cdef void implot_PushStyleVar1(int i, float val) noexcept nogil:
    implot.PushStyleVar(<implot.ImPlotStyleVar>i, val)

cdef void implot_PushStyleVar2(int i, imgui.ImVec2 val) noexcept nogil:
    implot.PushStyleVar(<implot.ImPlotStyleVar>i, val)

cdef void implot_PopStyleVar(int count) noexcept nogil:
    implot.PopStyleVar(count)

cdef void imnodes_PushStyleVar1(int i, float val) noexcept nogil:
    imnodes.PushStyleVar(<imnodes.ImNodesStyleVar>i, val)

cdef void imnodes_PushStyleVar2(int i, imgui.ImVec2 val) noexcept nogil:
    imnodes.PushStyleVar(<imnodes.ImNodesStyleVar>i, val)

cdef void imnodes_PopStyleVar(int count) noexcept nogil:
    imnodes.PopStyleVar(count)

def color_as_int(val):
    cdef imgui.ImU32 color = parse_color(val)
    return int(color)

def color_as_ints(val):
    cdef imgui.ImU32 color = parse_color(val)
    cdef imgui.ImVec4 color_vec = imgui.ColorConvertU32ToFloat4(color)
    return (int(255. * color_vec.x),
            int(255. * color_vec.y),
            int(255. * color_vec.z),
            int(255. * color_vec.w))

def color_as_floats(val):
    cdef imgui.ImU32 color = parse_color(val)
    cdef imgui.ImVec4 color_vec = imgui.ColorConvertU32ToFloat4(color)
    return (color_vec.x, color_vec.y, color_vec.z, color_vec.w)
