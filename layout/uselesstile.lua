
--[[

     Licensed under GNU General Public License v2
      * (c) 2014, projektile, worron
      * (c) 2013, Luke Bonham
      * (c) 2009, Donald Ephraim Curtis
      * (c) 2008, Julien Danjolu

--]]

local tag       = require("awful.tag")
local client    = require("awful.client")
local beautiful = require("beautiful")
local ipairs    = ipairs
local math      = { floor = math.floor,
                    ceil  = math.ceil,
                    max   = math.max,
                    min   = math.min }
local tonumber  = tonumber
local capi =
{
    mouse = mouse,
    screen = screen,
    mousegrabber = mousegrabber
}

local uselesstile = {}

-- Transformation functions
local function flip(canvas, geometry)
    return {
        -- vertical only
        x = 2 * canvas.x + canvas.width - geometry.x - geometry.width,
        y = geometry.y,
        width = geometry.width,
        height = geometry.height
    }
end

local function swap(geometry)
    return { x = geometry.y, y = geometry.x, width = geometry.height, height = geometry.width }
end

-- Find geometry for secondary windows column
local function cut_column(wa, n, index)
    local width = math.floor(wa.width / n)
    local area = { x = wa.x + (index - 1) * width, y = wa.y, width = width, height = wa.height }

    return area
end

-- Find geometry for certain window in column
local function cut_row(wa, factor, index, used)
    local height = math.floor(wa.height * factor.window[index] / factor.total)
    local area = { x = wa.x, y = wa.y + used, width = wa.width, height = height }

    return area
end

local function mouse_resize_handler(c, corner, x, y, orientation)
    local orientation = orientation or "tile"
    local wa = capi.screen[c.screen].workarea
    local mwfact = c.screen.selected_tag.master_width_factor
    local cursor
    local g = c:geometry()
    local offset = 0
    local x,y
    if orientation == "tile" then
        cursor = "cross"
        if g.height+15 > wa.height then
            offset = g.height * .5
            cursor = "sb_h_double_arrow"
        elseif not (g.y+g.height+15 > wa.y+wa.height) then
            offset = g.height
        end
        capi.mouse.coords({ x = wa.x + wa.width * mwfact, y = g.y + offset })
    elseif orientation == "left" then
        cursor = "cross"
        if g.height+15 >= wa.height then
            offset = g.height * .5
            cursor = "sb_h_double_arrow"
        elseif not (g.y+g.height+15 > wa.y+wa.height) then
            offset = g.height
        end
        capi.mouse.coords({ x = wa.x + wa.width * (1 - mwfact), y = g.y + offset })
    elseif orientation == "bottom" then
        cursor = "cross"
        if g.width+15 >= wa.width then
            offset = g.width * .5
            cursor = "sb_v_double_arrow"
        elseif not (g.x+g.width+15 > wa.x+wa.width) then
            offset = g.width
        end
        capi.mouse.coords({ y = wa.y + wa.height * mwfact, x = g.x + offset})
    else
        cursor = "cross"
        if g.width+15 >= wa.width then
            offset = g.width * .5
            cursor = "sb_v_double_arrow"
        elseif not (g.x+g.width+15 > wa.x+wa.width) then
            offset = g.width
        end
        capi.mouse.coords({ y = wa.y + wa.height * (1 - mwfact), x= g.x + offset })
    end

    capi.mousegrabber.run(function (_mouse)
                              for k, v in ipairs(_mouse.buttons) do
                                  if v then
                                      local fact_x = (_mouse.x - wa.x) / wa.width
                                      local fact_y = (_mouse.y - wa.y) / wa.height
                                      local mwfact

                                      local g = c:geometry()


                                      -- we have to make sure we're not on the last visible client where we have to use different settings.
                                      local wfact
                                      local wfact_x, wfact_y
                                      if (g.y+g.height+15) > (wa.y+wa.height) then
                                          wfact_y = (g.y + g.height - _mouse.y) / wa.height
                                      else
                                          wfact_y = (_mouse.y - g.y) / wa.height
                                      end

                                      if (g.x+g.width+15) > (wa.x+wa.width) then
                                          wfact_x = (g.x + g.width - _mouse.x) / wa.width
                                      else
                                          wfact_x = (_mouse.x - g.x) / wa.width
                                      end


                                      if orientation == "tile" then
                                          mwfact = fact_x
                                          wfact = wfact_y
                                      elseif orientation == "left" then
                                          mwfact = 1 - fact_x
                                          wfact = wfact_y
                                      elseif orientation == "bottom" then
                                          mwfact = fact_y
                                          wfact = wfact_x
                                      else
                                          mwfact = 1 - fact_y
                                          wfact = wfact_x
                                      end

				      c.screen.selected_tag.master_width_factor
					      = math.min(math.max(mwfact, 0.01), 0.99)
				      client.setwfact(math.min(math.max(wfact,0.01), 0.99), c)
                                      return true
                                  end
                              end
                              return false
                          end, cursor)
end

-- Client geometry correction depending on useless gap and window border
local function size_correction(c, geometry, useless_gap)
    geometry.width  = math.max(geometry.width  - 2 * c.border_width - useless_gap, 1)
    geometry.height = math.max(geometry.height - 2 * c.border_width - useless_gap, 1)
    geometry.x = geometry.x + useless_gap / 2
    geometry.y = geometry.y + useless_gap / 2
end

-- Check size factor for group of clients and calculate total
local function calc_factor(n, winfactors)
    local factor = { window = winfactors, total = 0, min = 1 }

    for i = 1, n do
        if not factor.window[i] then
            factor.window[i] = factor.min
        else
            factor.min = math.min(factor.window[i], factor.min)
            if factor.window[i] < 0.05 then factor.window[i] = 0.05 end
        end
        factor.total = factor.total + factor.window[i]
    end

    return factor
end

-- Tile group of clients in given area
-- @canvas need for proper transformation only
-- @winfactors table with clients size factors
local function tile_column(canvas, area, list, useless_gap, transformation, winfactors)
    local used = 0
    local factor = calc_factor(#list, winfactors)

    for i, c in ipairs(list) do
        local g = cut_row(area, factor, i, used)
        if i == #list then g.height = area.height - used end
        used = used + g.height

        -- swap workarea dimensions
        if transformation.flip then g = flip(canvas, g) end
        if transformation.swap then g = swap(g) end

        -- useless gap and border correction
        size_correction(c, g, useless_gap)


        c:geometry(g)
    end
end

--Main tile function
local function tile(p, orientation)

    -- Theme vars
    local useless_gap = beautiful.useless_gap_width or 0
    local global_border = beautiful.global_border_width or 0

    -- Aliases
    local wa = p.workarea
    local cls = p.clients
    local t = p.tag or capi.screen[p.screen].selected_tag

    -- Nothing to tile here
    if #cls == 0 then return end

    -- Get tag prop
    local nmaster = math.min(t.master_count, #cls)
    local mwfact = t.master_width_factor

    if nmaster == 0 then
        mwfact = 0
    elseif nmaster == #cls then
        mwfact = 1
    end

    -- clients size factor
    local data = tag.getdata(t).windowfact

    if not data then
        data = {}
        tag.getdata(t).windowfact = data
    end

    -- Workarea size correction depending on useless gap and global border
    wa.height = wa.height - 2 * global_border - useless_gap
    wa.width  = wa.width -  2 * global_border - useless_gap
    wa.x = wa.x + useless_gap / 2 + global_border
    wa.y = wa.y + useless_gap / 2 + global_border

    -- Find which transformation we need for given orientation
    local transformation = {
        swap = orientation == 'top' or orientation == 'bottom',
        flip = orientation == 'left' or orientation == 'top'
    }

    -- Swap workarea dimensions if orientation vertical
    if transformation.swap then wa = swap(wa) end

    -- Split master and other windows
    local cls_master, cls_other = {}, {}

    for i, c in ipairs(cls) do
        if i <= nmaster then
            table.insert(cls_master, c)
        else
            table.insert(cls_other, c)
        end
    end

    -- Tile master windows
    local master_area = {
        x = wa.x,
        y = wa.y,
        width  = nmaster > 0 and math.floor(wa.width * mwfact) or 0,
        height = wa.height
    }

    if not data[0] then data[0] = {} end
    tile_column(wa, master_area, cls_master, useless_gap, transformation, data[0])

    -- Tile other windows
    local other_area = {
        x = wa.x + master_area.width,
        y = wa.y,
        width  = wa.width - master_area.width,
        height = wa.height
    }

    -- get column number for other windows
    local ncol = math.min(t.column_count, #cls_other)

    if ncol == 0 then ncol = 1 end

    -- split other windows to column groups
    local last_small_column = ncol - #cls_other % ncol
    local rows_min = math.floor(#cls_other / ncol)

    local client_index = 1
    local used = 0
    for i = 1, ncol do
        local position = transformation.flip and ncol - i + 1 or i
        local rows = i <= last_small_column and rows_min or rows_min + 1
        local column = {}

        for j = 1, rows do
            table.insert(column, cls_other[client_index])
            client_index = client_index + 1
        end

        -- and tile
        local column_area = cut_column(other_area, ncol, position)
        if i == ncol then column_area.width = other_area.width - used end
        used = used + column_area.width

        if not data[i] then data[i] = {} end
        tile_column(wa, column_area, column, useless_gap, transformation, data[i])
    end
end

-- Layout constructor
local function construct_layout(name, orientation)
    return {
        name = name,
        -- @p screen number to tile
        arrange = function(p) return tile(p, orientation) end
    }
end

-- Build layouts with different tile direction
uselesstile.right  = construct_layout("uselesstile", "right")
uselesstile.left   = construct_layout("uselesstileleft", "left")
uselesstile.bottom = construct_layout("uselesstilebottom", "bottom")
uselesstile.top    = construct_layout("uselesstiletop", "top")

function uselesstile.right.mouse_resize_handler(c, corner, x, y)
    return mouse_resize_handler(c, corner, x, y)
end

function uselesstile.left.mouse_resize_handler(c, corner, x, y)
    return mouse_resize_handler(c, corner, x, y, "left")
end

function uselesstile.top.mouse_resize_handler(c, corner, x, y)
    return mouse_resize_handler(c, corner, x, y, "top")
end

function uselesstile.bottom.mouse_resize_handler(c, corner, x, y)
    return mouse_resize_handler(c, corner, x, y, "bottom")
end


-- Module aliase
uselesstile.arrange = uselesstile.right.arrange
uselesstile.mouse_resize_handler = uselesstile.right.mouse_resize_handler
uselesstile.name = uselesstile.right.name

return uselesstile
