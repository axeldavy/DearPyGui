"""
This type stub file was generated by cyright.
"""

from .core import *
from enum import IntEnum

class CustomHandler(baseHandler):
    """
    A base class to be subclassed in python
    for custom state checking.
    As this is called every frame rendered,
    and locks the GIL, be careful not do perform
    anything heavy.

    The functions that need to be implemented by
    subclasses are:
    -> check_can_bind(self, item)
    = Must return a boolean to indicate
    if this handler can be bound to
    the target item. Use isinstance to check
    the target class of the item.
    Note isinstance can recognize parent classes as
    well as subclasses. You can raise an exception.

    -> check_status(self, item)
    = Must return a boolean to indicate if the
    condition this handler looks at is met.
    Should not perform any action.

    -> run(self, item)
    Optional. If implemented, must perform
    the check this handler is meant to do,
    and take the appropriate actions in response
    (callbacks, etc). returns None.
    Note even if you implement run, check_status
    is still required. But it will not trigger calls
    to the callback. If you don't implement run(),
    returning True in check_status will trigger
    the callback.
    As a good practice try to not perform anything
    heavy to not block rendering.

    Warning: DO NOT change any item's parent, sibling
    or child. Rendering might rely on the tree being
    unchanged.
    You can change item values or status (show, theme, etc),
    except for parents of the target item.
    If you want to do that, delay the changes to when
    you are outside render_frame() or queue the change
    to be executed in another thread (mutexes protect
    states that need to not change during rendering,
    when accessed from a different thread). 

    If you need to access specific DCG internal item states,
    you must use Cython and subclass baseHandler instead.
    """
    ...


class HandlerList(baseHandler):
    """
    A list of handlers in order to attach several
    handlers to an item.
    In addition if you attach a callback to this handler,
    it will be issued if ALL or ANY of the children handler
    states are met. NONE is also possible.
    Note however that the handlers are not checked if an item
    is not rendered. This corresponds to the visible state.
    """
    @property
    def op(self): # -> handlerListOP:
        """
        handlerListOP that defines which condition
        is required to trigger the callback of this
        handler.
        Default is ALL
        """
        ...
    
    @op.setter
    def op(self, value: handlerListOP):
        ...
    


class ConditionalHandler(baseHandler):
    """
    A handler that runs the handler of his FIRST handler
    child if the other ones have their condition checked.

    For example this is useful to combine conditions. For example
    detecting clicks when a key is pressed. The interest
    of using this handler, rather than handling it yourself, is
    that if the callback queue is laggy the condition might not
    hold true anymore by the time you process the handler.
    In this case this handler enables to test right away
    the intended conditions.

    Note that handlers that get their condition checked do
    not call their callbacks.
    """
    ...


class OtherItemHandler(HandlerList):
    """
    Handler that imports the states from a different
    item than the one is attached to, and runs the
    children handlers using the states of the other
    item. The 'target' field in the callbacks will
    still be the current item and not the other item.

    This is useful when you need to do a AND/OR combination
    of the current item state with another item state, or
    when you need to check the state of an item that might be
    not be rendered.
    """
    @property
    def target(self): # -> baseItem:
        """
        Target item which state will be used
        for children handlers.
        """
        ...
    
    @target.setter
    def target(self, target: baseItem): # -> None:
        ...
    


class ActivatedHandler(baseHandler):
    """
    Handler for when the target item turns from
    the non-active to the active state. For instance
    buttons turn active when the mouse is pressed on them.
    """
    ...


class ActiveHandler(baseHandler):
    """
    Handler for when the target item is active.
    For instance buttons turn active when the mouse
    is pressed on them, and stop being active when
    the mouse is released.
    """
    ...


class ClickedHandler(baseHandler):
    """
    Handler for when a hovered item is clicked on.
    The item doesn't have to be interactable,
    it can be Text for example.
    """
    @property
    def button(self): # -> int:
        """
        Target mouse button
        0: left click
        1: right click
        2: middle click
        3, 4: other buttons
        """
        ...
    
    @button.setter
    def button(self, value: int): # -> None:
        ...
    


class DoubleClickedHandler(baseHandler):
    """
    Handler for when a hovered item is double clicked on.
    """
    @property
    def button(self): # -> int:
        ...
    
    @button.setter
    def button(self, value: int): # -> None:
        ...
    


class DeactivatedHandler(baseHandler):
    """
    Handler for when an active item loses activation.
    """
    ...


class DeactivatedAfterEditHandler(baseHandler):
    """
    However for editable items when the item loses
    activation after having been edited.
    """
    ...


class DraggedHandler(baseHandler):
    """
    Same as DraggingHandler, but only
    triggers the callback when the dragging
    has ended, instead of every frame during
    the dragging.
    """
    @property
    def button(self): # -> int:
        ...
    
    @button.setter
    def button(self, value: int): # -> None:
        ...
    


class DraggingHandler(baseHandler):
    """
    Handler to catch when the item is hovered
    and the mouse is dragging (click + motion) ?
    Note that if the item is not a button configured
    to catch the target button, it will not be
    considered being dragged as soon as it is not
    hovered anymore.
    """
    @property
    def button(self): # -> int:
        ...
    
    @button.setter
    def button(self, value: int): # -> None:
        ...
    


class EditedHandler(baseHandler):
    """
    Handler to catch when a field is edited.
    Only the frames when a field is changed
    triggers the callback.
    """
    ...


class FocusHandler(baseHandler):
    """
    Handler for windows or sub-windows that is called
    when they have focus, or for items when they
    have focus (for instance keyboard navigation,
    or editing a field).
    """
    ...


class GotFocusHandler(baseHandler):
    """
    Handler for when windows or sub-windows get
    focus.
    """
    ...


class LostFocusHandler(baseHandler):
    """
    Handler for when windows or sub-windows lose
    focus.
    """
    ...


class HoverHandler(baseHandler):
    """
    Handler that calls the callback when
    the target item is hovered.
    """
    ...


class GotHoverHandler(baseHandler):
    """
    Handler that calls the callback when
    the target item has just been hovered.
    """
    ...


class LostHoverHandler(baseHandler):
    """
    Handler that calls the callback the first
    frame when the target item was hovered, but
    is not anymore.
    """
    ...


class ResizeHandler(baseHandler):
    """
    Handler that triggers the callback
    whenever the item's bounding box changes size.
    """
    ...


class ToggledOpenHandler(baseHandler):
    """
    Handler that triggers the callback when the
    item switches from an closed state to a opened
    state. Here Close/Open refers to being in a
    reduced state when the full content is not
    shown, but could be if the user clicked on
    a specific button. The doesn't mean that
    the object is show or not shown.
    """
    ...


class ToggledCloseHandler(baseHandler):
    """
    Handler that triggers the callback when the
    item switches from an opened state to a closed
    state.
    *Warning*: Does not mean an item is un-shown
    by a user interaction (what we usually mean
    by closing a window).
    Here Close/Open refers to being in a
    reduced state when the full content is not
    shown, but could be if the user clicked on
    a specific button. The doesn't mean that
    the object is show or not shown.
    """
    ...


class OpenHandler(baseHandler):
    """
    Handler that triggers the callback when the
    item is in an opened state.
    Here Close/Open refers to being in a
    reduced state when the full content is not
    shown, but could be if the user clicked on
    a specific button. The doesn't mean that
    the object is show or not shown.
    """
    ...


class CloseHandler(baseHandler):
    """
    Handler that triggers the callback when the
    item is in an closed state.
    *Warning*: Does not mean an item is un-shown
    by a user interaction (what we usually mean
    by closing a window).
    Here Close/Open refers to being in a
    reduced state when the full content is not
    shown, but could be if the user clicked on
    a specific button. The doesn't mean that
    the object is show or not shown.
    """
    ...


class RenderHandler(baseHandler):
    """
    Handler that calls the callback
    whenever the item is rendered during
    frame rendering. This doesn't mean
    that the item is visible as it can be
    occluded by an item in front of it.
    Usually rendering skips items that
    are outside the window's clipping region,
    or items that are inside a menu that is
    currently closed.
    """
    ...


class GotRenderHandler(baseHandler):
    """
    Same as RenderHandler, but only calls the
    callback when the item switches from a
    non-rendered to a rendered state.
    """
    ...


class LostRenderHandler(baseHandler):
    """
    Handler that only calls the
    callback when the item switches from a
    rendered to non-rendered state. Note
    that when an item is not rendered, subsequent
    frames will not run handlers. Only the first time
    an item is non-rendered will trigger the handlers.
    """
    ...


class MouseCursorHandler(baseHandler):
    """
    Since the mouse cursor is reset every frame,
    this handler is used to set the cursor automatically
    the frames where this handler is run.
    Typical usage would be in a ConditionalHandler,
    combined with a HoverHandler.
    """
    @property
    def cursor(self): # -> mouse_cursor:
        """
        Change the mouse cursor to one of mouse_cursor,
        but only for the frames where this handler
        is run.
        """
        ...
    
    @cursor.setter
    def cursor(self, value: int): # -> None:
        ...
    


class KeyDownHandler(KeyDownHandler_):
    @property
    def key(self): # -> int:
        ...
    
    @key.setter
    def key(self, value: int): # -> None:
        ...
    


class KeyPressHandler(KeyPressHandler_):
    @property
    def key(self): # -> int:
        ...
    
    @key.setter
    def key(self, value: int): # -> None:
        ...
    
    @property
    def repeat(self): # -> bint:
        ...
    
    @repeat.setter
    def repeat(self, value: bool): # -> None:
        ...
    


class KeyReleaseHandler(KeyReleaseHandler_):
    @property
    def key(self): # -> int:
        ...
    
    @key.setter
    def key(self, value: int): # -> None:
        ...
    


class MouseClickHandler(MouseClickHandler_):
    @property
    def button(self): # -> int:
        ...
    
    @button.setter
    def button(self, value: int): # -> None:
        ...
    
    @property
    def repeat(self): # -> bint:
        ...
    
    @repeat.setter
    def repeat(self, value: bool): # -> None:
        ...
    


class MouseDoubleClickHandler(MouseDoubleClickHandler_):
    @property
    def button(self): # -> int:
        ...
    
    @button.setter
    def button(self, value: int): # -> None:
        ...
    


class MouseDownHandler(MouseDownHandler_):
    @property
    def button(self): # -> int:
        ...
    
    @button.setter
    def button(self, value: int): # -> None:
        ...
    


class MouseDragHandler(MouseDragHandler_):
    @property
    def button(self): # -> int:
        ...
    
    @button.setter
    def button(self, value: int): # -> None:
        ...
    
    @property
    def threshold(self): # -> float:
        ...
    
    @threshold.setter
    def threshold(self, value: float): # -> None:
        ...
    


class MouseReleaseHandler(MouseReleaseHandler_):
    @property
    def button(self): # -> int:
        ...
    
    @button.setter
    def button(self, value: int): # -> None:
        ...
    


class handlerListOP(IntEnum):
    ALL = ...
    ANY = ...
    NONE = ...


ALL: handlerListOP = ...
ANY: handlerListOP = ...
NONE: handlerListOP = ...
