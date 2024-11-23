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
#cython: auto_pickle=False
#distutils: language=c++

from libcpp cimport bool

from dearcygui.wrapper cimport imgui, implot
from dearcygui.wrapper.mutex cimport recursive_mutex, unique_lock
from libcpp.algorithm cimport swap
from libc.math cimport INFINITY

from .core cimport baseHandler, baseItem, uiItem, \
    lock_gil_friendly, clear_obj_vector, append_obj_vector, \
    IntPairFromVec2, draw_drawing_children, \
    draw_ui_children, Font, plotElement, \
    update_current_mouse_states, \
    draw_plot_element_children, itemState
from .types cimport *

import numpy as np
cimport numpy as cnp
cnp.import_array()


cdef extern from * nogil:
    """
    ImPlotAxisFlags GetAxisConfig(int axis)
    {
        return ImPlot::GetCurrentContext()->CurrentPlot->Axes[axis].Flags;
    }
    ImPlotLocation GetLegendConfig(ImPlotLegendFlags &flags)
    {
        flags = ImPlot::GetCurrentContext()->CurrentPlot->Items.Legend.Flags;
        return ImPlot::GetCurrentContext()->CurrentPlot->Items.Legend.Location;
    }
    ImPlotFlags GetPlotConfig()
    {
        return ImPlot::GetCurrentContext()->CurrentPlot->Flags;
    }
    bool IsItemHidden(const char* label_id)
    {
        ImPlotItem* item = ImPlot::GetItem(label_id);
        return item != nullptr && !item->Show;
    }
    """
    implot.ImPlotAxisFlags GetAxisConfig(int)
    implot.ImPlotLocation GetLegendConfig(implot.ImPlotLegendFlags&)
    implot.ImPlotFlags GetPlotConfig()
    bint IsItemHidden(const char*)

cdef class AxesResizeHandler(baseHandler):
    """
    Handler that can only be bound to a plot,
    and that triggers the callback whenever the
    axes min/max OR the plot region box changes.
    Basically whenever the size
    of a pixel within plot coordinate has likely changed.

    The data field passed to the callback contains
    ((min, max, scale), (min, max, scale)) where
    scale = (max-min) / num_real_pixels
    and the first tuple is for the target X axis (default X1),
    and the second tuple for the target Y axis (default Y1)
    """
    def __cinit__(self):
        self._axes = [implot.ImAxis_X1, implot.ImAxis_Y1]
    @property
    def axes(self):
        """
        Writable attribute: (X axis, Y axis)
        used for this handler.
        Default is (X1, Y1)
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self._axes[0], self._axes[1])

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

    cdef void check_bind(self, baseItem item):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if not(isinstance(item, Plot)):
            raise TypeError(f"Cannot only bind handler {self} to a plot, not {item}")

    cdef bint check_state(self, baseItem item) noexcept nogil:
        cdef itemState *state = item.p_state
        cdef bint changed = \
               state.cur.content_region_size.x != state.prev.content_region_size.x or \
               state.cur.content_region_size.y != state.prev.content_region_size.y
        if changed:
            return True
        if self._axes[0] == implot.ImAxis_X1:
            changed = (<Plot>item)._X1._min != (<Plot>item)._X1.prev_min or \
                      (<Plot>item)._X1._max != (<Plot>item)._X1.prev_max
        elif self._axes[0] == implot.ImAxis_X2:
            changed = (<Plot>item)._X2._min != (<Plot>item)._X2.prev_min or \
                      (<Plot>item)._X2._max != (<Plot>item)._X2.prev_max
        elif self._axes[0] == implot.ImAxis_X3:
            changed = (<Plot>item)._X3._min != (<Plot>item)._X3.prev_min or \
                      (<Plot>item)._X3._max != (<Plot>item)._X3.prev_max
        if changed:
            return True
        if self._axes[1] == implot.ImAxis_Y1:
            changed = (<Plot>item)._Y1._min != (<Plot>item)._Y1.prev_min or \
                      (<Plot>item)._Y1._max != (<Plot>item)._Y1.prev_max
        elif self._axes[1] == implot.ImAxis_Y2:
            changed = (<Plot>item)._Y2._min != (<Plot>item)._Y2.prev_min or \
                      (<Plot>item)._Y2._max != (<Plot>item)._Y2.prev_max
        elif self._axes[1] == implot.ImAxis_Y3:
            changed = (<Plot>item)._Y3._min != (<Plot>item)._Y3.prev_min or \
                      (<Plot>item)._Y3._max != (<Plot>item)._Y3.prev_max

        return changed

    cdef void run_handler(self, baseItem item) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)
        cdef itemState *state = item.p_state
        if not(self._enabled):
            return
        if self._callback is None or not(self.check_state(item)):
            return
        cdef double x_min = 0., x_max = 0., x_scale = 0.
        cdef double y_min = 0., y_max = 0., y_scale = 0.
        if self._axes[0] == implot.ImAxis_X1:
            x_min = (<Plot>item)._X1._min
            x_max = (<Plot>item)._X1._max
        elif self._axes[0] == implot.ImAxis_X2:
            x_min = (<Plot>item)._X2._min
            x_max = (<Plot>item)._X2._max
        elif self._axes[0] == implot.ImAxis_X3:
            x_min = (<Plot>item)._X3._min
            x_max = (<Plot>item)._X3._max
        if self._axes[1] == implot.ImAxis_Y1:
            y_min = (<Plot>item)._Y1._min
            y_max = (<Plot>item)._Y1._max
        elif self._axes[1] == implot.ImAxis_Y2:
            y_min = (<Plot>item)._Y2._min
            y_max = (<Plot>item)._Y2._max
        elif self._axes[1] == implot.ImAxis_Y3:
            y_min = (<Plot>item)._Y3._min
            y_max = (<Plot>item)._Y3._max
        x_scale = (x_max - x_min) / <double>state.cur.content_region_size.x
        y_scale = (y_max - y_min) / <double>state.cur.content_region_size.y
        self.context.queue_callback_argdoubletriplet(self._callback,
                                                     self,
                                                     item,
                                                     x_min,
                                                     x_max,
                                                     x_scale,
                                                     y_min,
                                                     y_max,
                                                     y_scale)

# BaseItem that has has no parent/child nor sibling
cdef class PlotAxisConfig(baseItem):
    def __cinit__(self):
        self.state.cap.can_be_hovered = True
        self.state.cap.can_be_clicked = True
        self.p_state = &self.state
        self._enabled = True
        self._scale = AxisScale.LINEAR
        self._tick_format = b""
        self.flags = 0
        self._min = 0
        self._max = 1
        self.to_fit = True
        self.dirty_minmax = False
        self._constraint_min = -INFINITY
        self._constraint_max = INFINITY
        self._zoom_min = 0
        self._zoom_max = INFINITY

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
        if value == AxisScale.LINEAR or \
           value == AxisScale.TIME or \
           value == AxisScale.LOG10 or\
           value == AxisScale.SYMLOG:
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
        self.dirty_minmax = True

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
        self.dirty_minmax = True

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
            self.to_fit = False

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

    @property
    def hovered(self):
        """
        Readonly attribute: Is the mouse inside the axis label area
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.cur.hovered

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
        return tuple(self.state.cur.clicked)

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
    def handlers(self):
        """
        Writable attribute: bound handlers for the axis.
        Only visible, hovered and clicked handlers are compatible.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        result = []
        cdef int i
        cdef baseHandler handler
        for i in range(<int>self._handlers.size()):
            handler = <baseHandler>self._handlers[i]
            result.append(handler)
        return result

    @handlers.setter
    def handlers(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef list items = []
        cdef int i
        if value is None:
            clear_obj_vector(self._handlers)
            return
        if not hasattr(value, "__len__"):
            value = [value]
        for i in range(len(value)):
            if not(isinstance(value[i], baseHandler)):
                raise TypeError(f"{value[i]} is not a handler")
            # Check the handlers can use our states. Else raise error
            (<baseHandler>value[i]).check_bind(self)
            items.append(value[i])
        # Success: bind
        clear_obj_vector(self._handlers)
        append_obj_vector(self._handlers, items)

    def fit(self):
        """
        Request for a fit of min/max to the data the next time the plot is drawn
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.to_fit = True

    @property
    def label(self):
        """
        Writable attribute: axis name
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return str(self._label, encoding='utf-8')

    @label.setter
    def label(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._label = bytes(value, 'utf-8')

    @property
    def format(self):
        """
        Writable attribute: format string to display axis values
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return str(self._format, encoding='utf-8')

    @format.setter
    def format(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._format = bytes(value, 'utf-8')

    @property
    def labels(self):
        """
        Writable attribute: array of strings to display as labels
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return [str(v, encoding='utf-8') for v in self._labels]

    @labels.setter
    def labels(self, value):
        cdef unique_lock[recursive_mutex] m
        cdef int i
        lock_gil_friendly(m, self.mutex)
        self._labels.clear()
        self._labels_cstr.clear()
        if value is None:
            return
        if hasattr(value, '__len__'):
            for v in value:
                self._labels.push_back(bytes(v, 'utf-8'))
            for i in range(<int>self._labels.size()):
                self._labels_cstr.push_back(self._labels[i].c_str())
        else:
            raise ValueError(f"Invalid type {type(value)} passed as labels. Expected array of strings")

    @property
    def labels_coord(self):
        """
        Writable attribute: coordinate for each label in labels at
        which to display the labels
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return [v for v in self._labels_coord]

    @labels_coord.setter
    def labels_coord(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._labels_coord.clear()
        if value is None:
            return
        if hasattr(value, '__len__'):
            for v in value:
                self._labels_coord.push_back(v)
        else:
            raise ValueError(f"Invalid type {type(value)} passed as labels_coord. Expected array of strings")

    cdef void setup(self, implot.ImAxis axis) noexcept nogil:
        """
        Apply the config to the target axis during plot
        setup
        """
        self.set_previous_states()
        self.state.cur.hovered = False
        self.state.cur.rendered = False

        if self._enabled == False:
            self.context._viewport.enabled_axes[axis] = False
            return
        self.context._viewport.enabled_axes[axis] = True
        self.state.cur.rendered = True

        cdef implot.ImPlotAxisFlags flags = self.flags
        if self.to_fit:
            flags |= implot.ImPlotAxisFlags_AutoFit
        if <int>self._label.size() > 0:
            implot.SetupAxis(axis, self._label.c_str(), flags)
        else:
            implot.SetupAxis(axis, NULL, flags)
        """
        if self.dirty_minmax:
            # enforce min < max
            self._max = max(self._max, self._min + 1e-12)
            implot.SetupAxisLimits(axis,
                                   self._min,
                                   self._max,
                                   implot.ImPlotCond_Always)
        """
        self.prev_min = self._min
        self.prev_max = self._max
        # We use SetupAxisLinks to get the min/max update
        # right away during EndPlot(), rather than the
        # next frame
        implot.SetupAxisLinks(axis, &self._min, &self._max)

        implot.SetupAxisScale(axis, <int>self._scale)

        if <int>self._format.size() > 0:
            implot.SetupAxisFormat(axis, self._format.c_str())

        if self._constraint_min != -INFINITY or \
           self._constraint_max != INFINITY:
            self._constraint_max = max(self._constraint_max, self._constraint_min + 1e-12)
            implot.SetupAxisLimitsConstraints(axis,
                                              self._constraint_min,
                                              self._constraint_max)
        if self._zoom_min > 0 or \
           self._zoom_max != INFINITY:
            self._zoom_min = max(0, self._zoom_min)
            self._zoom_max = max(self._zoom_min, self._zoom_max)
            implot.SetupAxisZoomConstraints(axis,
                                            self._zoom_min,
                                            self._zoom_max)
        cdef int label_count = min(<int>self._labels_coord.size(), <int>self._labels_cstr.size())
        if label_count > 0:
            implot.SetupAxisTicks(axis,
                                  self._labels_coord.data(),
                                  label_count,
                                  self._labels_cstr.data())

    cdef void after_setup(self, implot.ImAxis axis) noexcept nogil:
        """
        Update states, etc. after the elements were setup
        """
        if not(self.context._viewport.enabled_axes[axis]):
            if self.state.cur.rendered:
                self.set_hidden()
            return
        cdef implot.ImPlotRect rect
        #self.prev_min = self._min
        #self.prev_max = self._max
        self.dirty_minmax = False
        if axis <= implot.ImAxis_X3:
            rect = implot.GetPlotLimits(axis, implot.IMPLOT_AUTO)
            #self._min = rect.X.Min
            #self._max = rect.X.Max
            self._mouse_coord = implot.GetPlotMousePos(axis, implot.IMPLOT_AUTO).x
        else:
            rect = implot.GetPlotLimits(implot.IMPLOT_AUTO, axis)
            #self._min = rect.Y.Min
            #self._max = rect.Y.Max
            self._mouse_coord = implot.GetPlotMousePos(implot.IMPLOT_AUTO, axis).y

        # Take into accounts flags changed by user interactions
        cdef implot.ImPlotAxisFlags flags = GetAxisConfig(<int>axis)
        if self.to_fit and (self.flags & implot.ImPlotAxisFlags_AutoFit) == 0:
            # Remove Autofit flag introduced for to_fit
            flags &= ~implot.ImPlotAxisFlags_AutoFit
            self.to_fit = False
        self.flags = flags

        cdef bint hovered = implot.IsAxisHovered(axis)
        cdef int i
        for i in range(<int>imgui.ImGuiMouseButton_COUNT):
            self.state.cur.clicked[i] = hovered and imgui.IsMouseClicked(i, False)
            self.state.cur.double_clicked[i] = hovered and imgui.IsMouseDoubleClicked(i)
        cdef bint backup_hovered = self.state.cur.hovered
        self.state.cur.hovered = hovered
        self.run_handlers() # TODO FIX multiple configs tied. Maybe just not support ?
        if not(backup_hovered) or self.state.cur.hovered:
            return
        # Restore correct states
        # We do it here and not above to trigger the handlers only once
        self.state.cur.hovered |= backup_hovered
        for i in range(<int>imgui.ImGuiMouseButton_COUNT):
            self.state.cur.clicked[i] = self.state.cur.hovered and imgui.IsMouseClicked(i, False)
            self.state.cur.double_clicked[i] = self.state.cur.hovered and imgui.IsMouseDoubleClicked(i)

    cdef void after_plot(self, implot.ImAxis axis) noexcept nogil:
        # The fit only impacts the next frame
        if self._min != self.prev_min or self._max != self.prev_max:
            self.context._viewport.redraw_needed = True

    cdef void set_hidden(self) noexcept nogil:
        self.set_previous_states()
        self.state.cur.hovered = False
        self.state.cur.rendered = False
        cdef int i
        for i in range(<int>imgui.ImGuiMouseButton_COUNT):
            self.state.cur.clicked[i] = False
            self.state.cur.double_clicked[i] = False
        self.run_handlers()


cdef class PlotLegendConfig(baseItem):
    def __cinit__(self):
        self._show = True
        self._location = LegendLocation.NORTHWEST
        self.flags = 0

    '''
    # Probable doesn't work. Use instead plot no_legend
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
        if not(value) and self._show:
            self.set_hidden_and_propagate_to_siblings_no_handlers()
        self._show = value
    '''

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
        if value == LegendLocation.CENTER or \
           value == LegendLocation.NORTH or \
           value == LegendLocation.SOUTH or \
           value == LegendLocation.WEST or \
           value == LegendLocation.EAST or \
           value == LegendLocation.NORTHEAST or \
           value == LegendLocation.NORTHWEST or \
           value == LegendLocation.SOUTHEAST or \
           value == LegendLocation.SOUTHWEST:
            self._location = value
        else:
            raise ValueError("Invalid location. Must be a LegendLocation")

    @property
    def no_buttons(self):
        """
        Writable attribute to prevent legend icons
        to function as hide/show buttons
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
        implot.SetupLegend(<int>self._location, self.flags)
        # NOTE: Setup does just fill the location and flags.
        # No item is created at this point,
        # and thus we don't push fonts, check states, etc.

    cdef void after_setup(self) noexcept nogil:
        # The user can interact with legend configuration
        # with the mouse
        self._location = <LegendLocation>GetLegendConfig(self.flags)


cdef class Plot(uiItem):
    """
    Plot. Can have Plot elements as child.

    By default the axes X1 and Y1 are enabled,
    but other can be enabled, up to X3 and Y3.
    For instance:
    my_plot.X2.enabled = True

    By default, the legend and axes have reserved space.
    They can have their own handlers that can react to
    when they are hovered by the mouse or clicked.

    The states of the plot relate to the rendering area (excluding
    the legend, padding and axes). Thus if you want to react
    to mouse event inside the plot area (for example implementing
    clicking an curve), you can do it with using handlers bound
    to the plot (+ some logic in your callbacks). 
    """
    def __cinit__(self, context, *args, **kwargs):
        self.can_have_plot_element_child = True
        self.state.cap.can_be_clicked = True
        self.state.cap.can_be_dragged = True
        self.state.cap.can_be_hovered = True
        self.state.cap.has_content_region = True
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
        self._override_mod = imgui.ImGuiMod_Ctrl
        self._zoom_mod = 0
        self._zoom_rate = 0.1
        self._use_local_time = False
        self._use_ISO8601 = False
        self._use_24hour_clock = False
        # Box select/Query rects. To remove
        # Disabling implot query rects. This is better
        # to have it implemented outside implot.
        self.flags = implot.ImPlotFlags_NoBoxSelect

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
    def axes(self):
        """
        Helper read-only property to retrieve the 6 axes
        in an array [X1, X2, X3, Y1, Y2, Y3]
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return [self._X1, self._X2, self._X3, \
                self._Y1, self._Y2, self._Y3]

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
    def content_pos(self):
        """
        Readable attribute indicating the top left starting
        position of the plot content in viewport coordinates.

        The size of the plot content area is available with
        content_size_avail.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return IntPairFromVec2(self._content_pos)

    @property
    def pan_button(self):
        """
        Button that when held enables to navigate inside the plot
        Default is the left mouse button.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return <MouseButton>self._pan_button

    @pan_button.setter
    def pan_button(self, MouseButton button):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if <int>button < 0 or <int>button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        self._pan_button = <int>button

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
        return <MouseButton>self._fit_button

    @fit_button.setter
    def fit_button(self, MouseButton button):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if <int>button < 0 or <int>button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        self._fit_button = <int>button

    @property
    def menu_button(self):
        """
        Button that opens context menus
        (if enabled) when clicked.
        Default is the right mouse button.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return <MouseButton>self._menu_button

    @menu_button.setter
    def menu_button(self, MouseButton button):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if <int>button < 0 or <int>button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        self._menu_button = <int>button

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
        cdef imgui.ImVec2 rect_size
        cdef bint visible
        implot.GetStyle().UseLocalTime = self._use_local_time
        implot.GetStyle().UseISO8601 = self._use_ISO8601
        implot.GetStyle().Use24HourClock = self._use_24hour_clock
        implot.GetInputMap().Pan = self._pan_button
        implot.GetInputMap().Fit = self._fit_button
        implot.GetInputMap().Menu = self._menu_button
        implot.GetInputMap().ZoomRate = self._zoom_rate
        implot.GetInputMap().PanMod = self._pan_modifier
        implot.GetInputMap().ZoomMod = self._zoom_mod
        implot.GetInputMap().OverrideMod = self._override_mod

        self._X1.mutex.lock()
        self._X2.mutex.lock()
        self._X3.mutex.lock()
        self._Y1.mutex.lock()
        self._Y2.mutex.lock()
        self._Y3.mutex.lock()
        self._legend.mutex.lock()

        # Check at least one axis of each is enabled ?

        visible = implot.BeginPlot(self.imgui_label.c_str(),
                                   self.scaled_requested_size(),
                                   self.flags)
        # BeginPlot created the imgui Item
        self.state.cur.rect_size = imgui.GetItemRectSize()
        if visible:
            self.state.cur.rendered = True
            
            # Setup axes
            self._X1.setup(implot.ImAxis_X1)
            self._X2.setup(implot.ImAxis_X2)
            self._X3.setup(implot.ImAxis_X3)
            self._Y1.setup(implot.ImAxis_Y1)
            self._Y2.setup(implot.ImAxis_Y2)
            self._Y3.setup(implot.ImAxis_Y3)

            # From DPG: workaround for stuck selection
            # Unsure why it should be done here and not above
            # -> Not needed because query rects are not implemented with implot
            #if (imgui.GetIO().KeyMods & self._query_toggle_mod) == imgui.GetIO().KeyMods and \
            #    (imgui.IsMouseDown(self._select_button) or imgui.IsMouseReleased(self._select_button)):
            #    implot.GetInputMap().OverrideMod = imgui.ImGuiMod_None

            self._legend.setup()

            implot.SetupFinish()

            # These states are valid after SetupFinish
            # Update now to have up to date data for handlers of children.
            self.state.cur.hovered = implot.IsPlotHovered()
            update_current_mouse_states(self.state)
            self.state.cur.content_region_size = implot.GetPlotSize()
            self._content_pos = implot.GetPlotPos()

            self._X1.after_setup(implot.ImAxis_X1)
            self._X2.after_setup(implot.ImAxis_X2)
            self._X3.after_setup(implot.ImAxis_X3)
            self._Y1.after_setup(implot.ImAxis_Y1)
            self._Y2.after_setup(implot.ImAxis_Y2)
            self._Y3.after_setup(implot.ImAxis_Y3)
            self._legend.after_setup()

            implot.PushPlotClipRect(0.)

            draw_plot_element_children(self)

            implot.PopPlotClipRect()
            # The user can interact with the plot
            # configuration with the mouse
            self.flags = GetPlotConfig()
            implot.EndPlot()
            self._X1.after_plot(implot.ImAxis_X1)
            self._X2.after_plot(implot.ImAxis_X2)
            self._X3.after_plot(implot.ImAxis_X3)
            self._Y1.after_plot(implot.ImAxis_Y1)
            self._Y2.after_plot(implot.ImAxis_Y2)
            self._Y3.after_plot(implot.ImAxis_Y3)
        elif self.state.cur.rendered:
            self.set_hidden_no_handler_and_propagate_to_children_with_handlers()
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
        return False
        # We don't need to restore the plot config as we
        # always overwrite it.


cdef class plotElementWithLegend(plotElement):
    """
    Base class for plot children with a legend.

    Children of plot elements are rendered on a legend
    popup entry that gets shown on a right click (by default).
    """
    def __cinit__(self):
        self.state.cap.can_be_hovered = True # The legend only
        self.p_state = &self.state
        self._enabled = True
        self.enabled_dirty = True
        self._legend_button = imgui.ImGuiMouseButton_Right
        self._legend = True
        self.state.cap.can_be_hovered = True
        self.can_have_widget_child = True

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
    def enabled(self):
        """
        Writable attribute: show/hide
        the item while still having a toggable
        entry in the menu.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._enabled

    @enabled.setter
    def enabled(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if value != self._enabled:
            self.enabled_dirty = True
        self._enabled = value

    @property
    def font(self):
        """
        Writable attribute: font used for the text rendered
        of this item and its subitems
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._font

    @font.setter
    def font(self, Font value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._font = value

    @property
    def legend_button(self):
        """
        Button that opens the legend entry for
        this element.
        Default is the right mouse button.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return <MouseButton>self._legend_button

    @legend_button.setter
    def legend_button(self, MouseButton button):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        if <int>button < 0 or <int>button >= imgui.ImGuiMouseButton_COUNT:
            raise ValueError("Invalid button")
        self._legend_button = <int>button

    @property
    def legend_handlers(self):
        """
        Writable attribute: bound handlers for the legend.
        Only visible (set for the plot) and hovered (set 
        for the legend) handlers are compatible.
        To detect if the plot element is hovered, check
        the hovered state of the plot.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        result = []
        cdef int i
        cdef baseHandler handler
        for i in range(<int>self._handlers.size()):
            handler = <baseHandler>self._handlers[i]
            result.append(handler)
        return result

    @legend_handlers.setter
    def legend_handlers(self, value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        cdef list items = []
        cdef int i
        if value is None:
            clear_obj_vector(self._handlers)
            return
        if not hasattr(value, "__len__"):
            value = [value]
        for i in range(len(value)):
            if not(isinstance(value[i], baseHandler)):
                raise TypeError(f"{value[i]} is not a handler")
            # Check the handlers can use our states. Else raise error
            (<baseHandler>value[i]).check_bind(self)
            items.append(value[i])
        # Success: bind
        clear_obj_vector(self._handlers)
        append_obj_vector(self._handlers, items)

    @property
    def legend_hovered(self):
        """
        Readonly attribute: Is the legend of this
        item hovered.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.cur.hovered

    cdef void draw(self) noexcept nogil:
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)

        # Check the axes are enabled
        if not(self._show) or \
           not(self.context._viewport.enabled_axes[self._axes[0]]) or \
           not(self.context._viewport.enabled_axes[self._axes[1]]):
            self.set_previous_states()
            self.state.cur.rendered = False
            self.state.cur.hovered = False
            self.propagate_hidden_state_to_children_with_handlers()
            self.run_handlers()
            return

        self.set_previous_states()

        # push theme, font
        if self._font is not None:
            self._font.push()

        self.context._viewport.push_pending_theme_actions(
            ThemeEnablers.ANY,
            ThemeCategories.t_plot
        )

        if self._theme is not None:
            self._theme.push()

        implot.SetAxes(self._axes[0], self._axes[1])

        if self.enabled_dirty:
            implot.HideNextItem(not(self._enabled), implot.ImPlotCond_Always)
            self.enabled_dirty = False
        else:
            self._enabled = IsItemHidden(self.imgui_label.c_str())
        self.draw_element()

        self.state.cur.rendered = True
        self.state.cur.hovered = False
        cdef imgui.ImVec2 pos_w, pos_p
        if self._legend:
            # Popup that gets opened with a click on the entry
            # We don't open it if it will be empty as it will
            # display a small rect with nothing in it. It's surely
            # better to not display anything in this case.
            if self.last_widgets_child is not None:
                if implot.BeginLegendPopup(self.imgui_label.c_str(),
                                           self._legend_button):
                    if self.last_widgets_child is not None:
                        # sub-window
                        pos_w = imgui.GetCursorScreenPos()
                        pos_p = pos_w
                        swap(pos_w, self.context._viewport.window_pos)
                        swap(pos_p, self.context._viewport.parent_pos)
                        draw_ui_children(self)
                        self.context._viewport.window_pos = pos_w
                        self.context._viewport.parent_pos = pos_p
                    implot.EndLegendPopup()
            self.state.cur.hovered = implot.IsLegendEntryHovered(self.imgui_label.c_str())


        # pop theme, font
        if self._theme is not None:
            self._theme.pop()

        self.context._viewport.pop_applied_pending_theme_actions()

        if self._font is not None:
            self._font.pop()

        self.run_handlers()

    cdef void draw_element(self) noexcept nogil:
        return

cdef class plotElementXY(plotElementWithLegend):
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

cdef class plotElementXYY(plotElementWithLegend):
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

cdef class PlotStems(plotElementXY):
    @property
    def horizontal(self):
        """
        Stems will be rendered horizontally
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotStemsFlags_Horizontal) != 0

    @horizontal.setter
    def horizontal(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotStemsFlags_Horizontal
        if value:
            self.flags |= implot.ImPlotStemsFlags_Horizontal

    cdef void draw_element(self) noexcept nogil:
        self.check_arrays()
        cdef int size = min(self._X.shape[0], self._Y.shape[0])
        if size == 0:
            return

        if cnp.PyArray_TYPE(self._X) == cnp.NPY_INT:
            implot.PlotStems[int](self.imgui_label.c_str(),
                                 <const int*>cnp.PyArray_DATA(self._X),
                                 <const int*>cnp.PyArray_DATA(self._Y),
                                 size,
                                 0.,
                                 self.flags,
                                 0,
                                 cnp.PyArray_STRIDE(self._X, 0))
        elif cnp.PyArray_TYPE(self._X) == cnp.NPY_FLOAT:
            implot.PlotStems[float](self.imgui_label.c_str(),
                                   <const float*>cnp.PyArray_DATA(self._X),
                                   <const float*>cnp.PyArray_DATA(self._Y),
                                   size,
                                   0.,
                                   self.flags,
                                   0,
                                   cnp.PyArray_STRIDE(self._X, 0))
        else:
            implot.PlotStems[double](self.imgui_label.c_str(),
                                    <const double*>cnp.PyArray_DATA(self._X),
                                    <const double*>cnp.PyArray_DATA(self._Y),
                                    size,
                                    0.,
                                    self.flags,
                                    0,
                                    cnp.PyArray_STRIDE(self._X, 0))

cdef class PlotBars(plotElementXY):
    def __cinit__(self):
        self._weight = 1.

    @property
    def weight(self):
        """
        bar_size. TODO better document
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._weight

    @weight.setter
    def weight(self, double value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._weight = value

    @property
    def horizontal(self):
        """
        Bars will be rendered horizontally
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotBarsFlags_Horizontal) != 0

    @horizontal.setter
    def horizontal(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotBarsFlags_Horizontal
        if value:
            self.flags |= implot.ImPlotBarsFlags_Horizontal

    cdef void draw_element(self) noexcept nogil:
        self.check_arrays()
        cdef int size = min(self._X.shape[0], self._Y.shape[0])
        if size == 0:
            return

        if cnp.PyArray_TYPE(self._X) == cnp.NPY_INT:
            implot.PlotBars[int](self.imgui_label.c_str(),
                                 <const int*>cnp.PyArray_DATA(self._X),
                                 <const int*>cnp.PyArray_DATA(self._Y),
                                 size,
                                 self._weight,
                                 self.flags,
                                 0,
                                 cnp.PyArray_STRIDE(self._X, 0))
        elif cnp.PyArray_TYPE(self._X) == cnp.NPY_FLOAT:
            implot.PlotBars[float](self.imgui_label.c_str(),
                                   <const float*>cnp.PyArray_DATA(self._X),
                                   <const float*>cnp.PyArray_DATA(self._Y),
                                   size,
                                   self._weight,
                                   self.flags,
                                   0,
                                   cnp.PyArray_STRIDE(self._X, 0))
        else:
            implot.PlotBars[double](self.imgui_label.c_str(),
                                    <const double*>cnp.PyArray_DATA(self._X),
                                    <const double*>cnp.PyArray_DATA(self._Y),
                                    size,
                                    self._weight,
                                    self.flags,
                                    0,
                                    cnp.PyArray_STRIDE(self._X, 0))

cdef class PlotStairs(plotElementXY):
    @property
    def pre_step(self):
        """
        The y value is continued constantly to the left
        from every x position, i.e. the interval
        (x[i-1], x[i]] has the value y[i].
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotStairsFlags_PreStep) != 0

    @pre_step.setter
    def pre_step(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotStairsFlags_PreStep
        if value:
            self.flags |= implot.ImPlotStairsFlags_PreStep

    @property
    def shaded(self):
        """
        a filled region between the stairs and horizontal
        origin will be rendered; use PlotShadedLine for
        more advanced cases.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotStairsFlags_Shaded) != 0

    @shaded.setter
    def shaded(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotStairsFlags_Shaded
        if value:
            self.flags |= implot.ImPlotStairsFlags_Shaded

    cdef void draw_element(self) noexcept nogil:
        self.check_arrays()
        cdef int size = min(self._X.shape[0], self._Y.shape[0])
        if size == 0:
            return

        if cnp.PyArray_TYPE(self._X) == cnp.NPY_INT:
            implot.PlotStairs[int](self.imgui_label.c_str(),
                                 <const int*>cnp.PyArray_DATA(self._X),
                                 <const int*>cnp.PyArray_DATA(self._Y),
                                 size,
                                 self.flags,
                                 0,
                                 cnp.PyArray_STRIDE(self._X, 0))
        elif cnp.PyArray_TYPE(self._X) == cnp.NPY_FLOAT:
            implot.PlotStairs[float](self.imgui_label.c_str(),
                                   <const float*>cnp.PyArray_DATA(self._X),
                                   <const float*>cnp.PyArray_DATA(self._Y),
                                   size,
                                   self.flags,
                                   0,
                                   cnp.PyArray_STRIDE(self._X, 0))
        else:
            implot.PlotStairs[double](self.imgui_label.c_str(),
                                    <const double*>cnp.PyArray_DATA(self._X),
                                    <const double*>cnp.PyArray_DATA(self._Y),
                                    size,
                                    self.flags,
                                    0,
                                    cnp.PyArray_STRIDE(self._X, 0))

cdef class plotElementX(plotElementWithLegend):
    def __cinit__(self):
        self._X = np.zeros(shape=(1,), dtype=np.float64)

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

    cdef void check_arrays(self) noexcept nogil:
        return


cdef class PlotInfLines(plotElementX):
    """
    Draw vertical (or horizontal) infinite lines at
    the passed coordinates
    """
    @property
    def horizontal(self):
        """
        Plot horizontal lines rather than plots
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotInfLinesFlags_Horizontal) != 0

    @horizontal.setter
    def horizontal(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotInfLinesFlags_Horizontal
        if value:
            self.flags |= implot.ImPlotInfLinesFlags_Horizontal

    cdef void draw_element(self) noexcept nogil:
        self.check_arrays()
        cdef int size = self._X.shape[0]
        if size == 0:
            return

        if cnp.PyArray_TYPE(self._X) == cnp.NPY_INT:
            implot.PlotInfLines[int](self.imgui_label.c_str(),
                                 <const int*>cnp.PyArray_DATA(self._X),
                                 size,
                                 self.flags,
                                 0,
                                 cnp.PyArray_STRIDE(self._X, 0))
        elif cnp.PyArray_TYPE(self._X) == cnp.NPY_FLOAT:
            implot.PlotInfLines[float](self.imgui_label.c_str(),
                                   <const float*>cnp.PyArray_DATA(self._X),
                                   size,
                                   self.flags,
                                   0,
                                   cnp.PyArray_STRIDE(self._X, 0))
        else:
            implot.PlotInfLines[double](self.imgui_label.c_str(),
                                    <const double*>cnp.PyArray_DATA(self._X),
                                    size,
                                    self.flags,
                                    0,
                                    cnp.PyArray_STRIDE(self._X, 0))

cdef class PlotScatter(plotElementXY):
    @property
    def no_clip(self):
        """
        Markers on the edge of a plot will not be clipped
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotScatterFlags_NoClip) != 0

    @no_clip.setter
    def no_clip(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotScatterFlags_NoClip
        if value:
            self.flags |= implot.ImPlotScatterFlags_NoClip

    cdef void draw_element(self) noexcept nogil:
        self.check_arrays()
        cdef int size = min(self._X.shape[0], self._Y.shape[0])
        if size == 0:
            return

        if cnp.PyArray_TYPE(self._X) == cnp.NPY_INT:
            implot.PlotScatter[int](self.imgui_label.c_str(),
                                 <const int*>cnp.PyArray_DATA(self._X),
                                 <const int*>cnp.PyArray_DATA(self._Y),
                                 size,
                                 self.flags,
                                 0,
                                 cnp.PyArray_STRIDE(self._X, 0))
        elif cnp.PyArray_TYPE(self._X) == cnp.NPY_FLOAT:
            implot.PlotScatter[float](self.imgui_label.c_str(),
                                   <const float*>cnp.PyArray_DATA(self._X),
                                   <const float*>cnp.PyArray_DATA(self._Y),
                                   size,
                                   self.flags,
                                   0,
                                   cnp.PyArray_STRIDE(self._X, 0))
        else:
            implot.PlotScatter[double](self.imgui_label.c_str(),
                                    <const double*>cnp.PyArray_DATA(self._X),
                                    <const double*>cnp.PyArray_DATA(self._Y),
                                    size,
                                    self.flags,
                                    0,
                                    cnp.PyArray_STRIDE(self._X, 0))

'''
cdef class PlotHistogram2D(plotElementXY):
    @property
    def density(self):
        """
        Counts will be normalized, i.e. the PDF will be visualized
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotHistogramFlags_Density) != 0

    @density.setter
    def density(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotHistogramFlags_Density
        if value:
            self.flags |= implot.ImPlotHistogramFlags_Density

    @property
    def no_outliers(self):
        """
        Exclude values outside the specifed histogram range
        from the count toward normalizing and cumulative counts.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotHistogramFlags_NoOutliers) != 0

    @no_outliers.setter
    def no_outliers(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotHistogramFlags_NoOutliers
        if value:
            self.flags |= implot.ImPlotHistogramFlags_NoOutliers

# TODO: row col flag ???

    cdef void draw_element(self) noexcept nogil:
        self.check_arrays()
        cdef int size = min(self._X.shape[0], self._Y.shape[0])
        if size == 0:
            return

        if cnp.PyArray_TYPE(self._X) == cnp.NPY_INT:
            implot.PlotScatter[int](self.imgui_label.c_str(),
                                 <const int*>cnp.PyArray_DATA(self._X),
                                 <const int*>cnp.PyArray_DATA(self._Y),
                                 size,
                                 self._weight,
                                 self.flags,
                                 0,
                                 cnp.PyArray_STRIDE(self._X, 0))
        elif cnp.PyArray_TYPE(self._X) == cnp.NPY_FLOAT:
            implot.PlotScatter[float](self.imgui_label.c_str(),
                                   <const float*>cnp.PyArray_DATA(self._X),
                                   <const float*>cnp.PyArray_DATA(self._Y),
                                   size,
                                   self._weight,
                                   self.flags,
                                   0,
                                   cnp.PyArray_STRIDE(self._X, 0))
        else:
            implot.PlotScatter[double](self.imgui_label.c_str(),
                                    <const double*>cnp.PyArray_DATA(self._X),
                                    <const double*>cnp.PyArray_DATA(self._Y),
                                    size,
                                    self._weight,
                                    self.flags,
                                    0,
                                    cnp.PyArray_STRIDE(self._X, 0))
'''
'''
cdef class plotDraggable(plotElement):
    """
    Base class for plot draggable elements.
    """
    def __cinit__(self):
        self.state.cap.can_be_hovered = True
        self.state.cap.can_be_clicked = True
        self.state.cap.can_be_active = True
        self.flags = implot.ImPlotDragToolFlags_None

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
    def no_cursors(self):
        """
        Writable attribute to make drag tools
        not change cursor icons when hovered or held.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotDragToolFlags_NoCursors) != 0

    @no_cursors.setter
    def no_cursors(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotDragToolFlags_NoCursors
        if value:
            self.flags |= implot.ImPlotDragToolFlags_NoCursors

    @property
    def ignore_fit(self):
        """
        Writable attribute to make the drag tool
        not considered for plot fits.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotDragToolFlags_NoFit) != 0

    @ignore_fit.setter
    def ignore_fit(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotDragToolFlags_NoFit
        if value:
            self.flags |= implot.ImPlotDragToolFlags_NoFit

    @property
    def ignore_inputs(self):
        """
        Writable attribute to lock the tool from user inputs
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotDragToolFlags_NoInputs) != 0

    @ignore_inputs.setter
    def ignore_inputs(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotDragToolFlags_NoInputs
        if value:
            self.flags |= implot.ImPlotDragToolFlags_NoInputs

    @property
    def delayed(self):
        """
        Writable attribute to delay rendering
        by one frame.

        One use case is position-contraints.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return (self.flags & implot.ImPlotDragToolFlags_Delayed) != 0

    @delayed.setter
    def delayed(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self.flags &= ~implot.ImPlotDragToolFlags_Delayed
        if value:
            self.flags |= implot.ImPlotDragToolFlags_Delayed

    @property
    def active(self):
        """
        Readonly attribute: is the drag tool held
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.cur.active

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
        return tuple(self.state.cur.clicked)

    @property
    def double_clicked(self):
        """
        Readonly attribute: has the item just been double-clicked.
        The returned value is a tuple of len 5 containing the individual test
        mouse buttons (up to 5 buttons)
        If True, the attribute is reset the next frame. It's better to rely
        on handlers to catch this event.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.cur.double_clicked

    @property
    def hovered(self):
        """
        Readonly attribute: Is the item hovered.
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self.state.cur.hovered

    cdef void draw(self) noexcept nogil:
        cdef int i
        cdef unique_lock[recursive_mutex] m = unique_lock[recursive_mutex](self.mutex)

        # Check the axes are enabled
        if not(self._show) or \
           not(self.context._viewport.enabled_axes[self._axes[0]]) or \
           not(self.context._viewport.enabled_axes[self._axes[1]]):
            self.state.cur.hovered = False
            self.state.cur.rendered = False
            for i in range(imgui.ImGuiMouseButton_COUNT):
                self.state.cur.clicked[i] = False
                self.state.cur.double_clicked[i] = False
            self.propagate_hidden_state_to_children_with_handlers()
            return

        # push theme, font
        self.context._viewport.push_pending_theme_actions(
            ThemeEnablers.ANY,
            ThemeCategories.t_plot
        )

        if self._theme is not None:
            self._theme.push()

        implot.SetAxes(self._axes[0], self._axes[1])
        self.state.cur.rendered = True
        self.draw_element()

        # pop theme, font
        if self._theme is not None:
            self._theme.pop()

        self.context._viewport.pop_applied_pending_theme_actions()

        self.run_handlers()

    cdef void draw_element(self) noexcept nogil:
        return
'''

cdef class DrawInPlot(plotElementWithLegend):
    """
    A plot element that enables to insert Draw* items
    inside a plot in plot coordinates.

    defaults to no_legend = True
    """
    def __cinit__(self):
        self.can_have_drawing_child = True
        self._legend = False
        self._ignore_fit = False

    @property
    def ignore_fit(self):
        """
        Writable attribute to make this element
        be ignored during plot fits
        """
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        return self._ignore_fit

    @ignore_fit.setter
    def ignore_fit(self, bint value):
        cdef unique_lock[recursive_mutex] m
        lock_gil_friendly(m, self.mutex)
        self._ignore_fit = value

    cdef void draw(self) noexcept nogil:

        # Check the axes are enabled
        if not(self._show) or \
           not(self.context._viewport.enabled_axes[self._axes[0]]) or \
           not(self.context._viewport.enabled_axes[self._axes[1]]):
            self.set_previous_states()
            self.state.cur.rendered = False
            self.state.cur.hovered = False
            self.propagate_hidden_state_to_children_with_handlers()
            self.run_handlers()
            return

        self.set_previous_states()

        # push theme, font
        if self._font is not None:
            self._font.push()

        self.context._viewport.push_pending_theme_actions(
            ThemeEnablers.ANY,
            ThemeCategories.t_plot
        )

        if self._theme is not None:
            self._theme.push()

        implot.SetAxes(self._axes[0], self._axes[1])

        # Reset current drawInfo
        self.context._viewport.scales = [1., 1.]
        self.context._viewport.shifts = [0., 0.]
        self.context._viewport.in_plot = True
        self.context._viewport.plot_fit = False if self._ignore_fit else implot.FitThisFrame()
        self.context._viewport.thickness_multiplier = implot.GetStyle().LineWeight
        self.context._viewport.size_multiplier = implot.GetPlotSize().x / implot.GetPlotLimits(self._axes[0], self._axes[1]).Size().x
        self.context._viewport.thickness_multiplier = self.context._viewport.thickness_multiplier * self.context._viewport.size_multiplier
        self.context._viewport.parent_pos = implot.GetPlotPos()

        cdef bint render = True

        if self._legend:
            render = implot.BeginItem(self.imgui_label.c_str(), self.flags, -1)
        else:
            implot.PushPlotClipRect(0.)

        if render:
            draw_drawing_children(self, implot.GetPlotDrawList())

            if self._legend:
                implot.EndItem()
            else:
                implot.PopPlotClipRect()

        self.state.cur.rendered = True
        self.state.cur.hovered = False
        cdef imgui.ImVec2 pos_w, pos_p
        if self._legend:
            # Popup that gets opened with a click on the entry
            # We don't open it if it will be empty as it will
            # display a small rect with nothing in it. It's surely
            # better to not display anything in this case.
            if self.last_widgets_child is not None:
                if implot.BeginLegendPopup(self.imgui_label.c_str(),
                                           self._legend_button):
                    if self.last_widgets_child is not None:
                        # sub-window
                        pos_w = imgui.GetCursorScreenPos()
                        pos_p = pos_w
                        swap(pos_w, self.context._viewport.window_pos)
                        swap(pos_p, self.context._viewport.parent_pos)
                        draw_ui_children(self)
                        self.context._viewport.window_pos = pos_w
                        self.context._viewport.parent_pos = pos_p
                    implot.EndLegendPopup()
            self.state.cur.hovered = implot.IsLegendEntryHovered(self.imgui_label.c_str())

        # pop theme, font
        if self._theme is not None:
            self._theme.pop()

        self.context._viewport.pop_applied_pending_theme_actions()

        if self._font is not None:
            self._font.pop()

        self.run_handlers()