For compatibility and ease of porting of applications written for DearPyGui (DPG), DearCyGui (DCG) supports a thin python layer that converts the original DPG calls into new DCG ones. Since DCG intends to be close to DPG, and both try to match closely to Dear ImGui, this layer is lightweight.
In many cases it suffices to replace your ```import dearpygui.dearpygui as dpg``` by ```import dearcygui.dearpygui as dpg``` for DCG to run your program. In addition, as items created by the wrapper are DCG objects, you have access to the new DCG features with them.

Still some features of DearPyGui are not perfectly matched to DCG, and compatibility issues might arise. Here is a list of features that might need manual changes on your side:

- Item types. In DCG instead of checking the type of an object using ```get_item_type``` or ```get_item_types``` against specific strings, one should instead test with ```isinstance()``` if the object derives from the target class. This allows better handling of subclassing. While in the future, the wrapper may support mapping the new types to the old names, for now this is not supported and if one relied on the item types, manual porting is needed.

- Themes targetting specific item types. In order to help porting, the wrapper maps types that could be used for themes meant to target specific item types, into DCG theme targets. This is not entirely complete yet and some items might not map to the correct category.

- Children slots. DPG organized children into 4 slots. Depending on the parent, different types of children could end up in the same slots. A significant chunck of code decided which parent could accept which child, and vice-versa. Instead DCG simplifies the parenting rules, and more items are compatible as siblings. However in order to achieve this, more slots are used. Except a few exceptions, an item which can have children only supports one slot. The advantage is that it simplifies various parts of the drawing mecanism (some parts of DPG need to go through the children several times to run specific children at specific moments of the rendering process). In addition if children ended up in different slots, one couldn't run them after (or before) children of another slot. This is still true, but to a much lesser extent since much more children end up in the same slots. The impact on your code is that if you relied on the child slot, get_item_slot might be inaccurate, and in addition the siblings of your items might not go through all the children of the target slot.

- Due to the above, A few items that used to be allowed as siblings or as parent/children, cannot anymore. Tooltips is in the uiItem slot and thus cannot be child/sibling of various elements it was allowed before. This restriction is compensated by the fact Tooltips can target any item (`target=` argument), and not just their previous sibling. Just insert them at a different place of your rendering tree that accepts uiItem. The wrapper attemps to do that for you. Another similar change is that the plotElement category, in which plot series reside, are direct children of the plot, and not anymore of the Y axis. Instead axes are children of the plot and reside in a different child slot than plotElement. They take `axes` argument to indicate which axes they target (contrary to DPG, X2, X3 are allowed). The wrapper handles that for you.

- Horizontal groups and vertical groups are split. Thus you cannot switch from one to the other using `configure(horizontal=)`.

- Colors might misbehave without porting efforts. Previously depending on the type of data to which the color was meant, sometimes the color data was divided by 255., sometimes not. Instead DPG supports uniformized 3 types of color format that can be passed to all color arguments. If you used to pass floating point color data in the [0, 255] range, you will need to either divide by 255, or convert to ints before passing them. Negative color fields are not supported either (and used to be clamped to 0).

- Textures are uploaded right away, and thus require the context viewport to be initialized before being created.

- rect_min, rect_max and context_area_avail were not properly documented and corresponded respectively to the top left of the item in screen space, the bottom right and the remaining area in the window starting from the bottom right. Instead content_area_avail is only defined for items which span a window area, and it corresponds to the full area available from the start of the window area. The old rect_min, rect_max and context_area_avail can be deduced from pos_to_viewport, rect_size, pos_to_window and the windows's content_area_avail. 