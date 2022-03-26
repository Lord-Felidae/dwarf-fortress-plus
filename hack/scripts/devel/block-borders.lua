-- overlay that displays map block borders

--[====[

devel/block-borders
===================

An overlay that draws borders of map blocks. Must be run from the main fortress
mode screen. See :doc:`/docs/api/Maps` for details on map blocks.

]====]

local gui = require "gui"
local guidm = require "gui.dwarfmode"
local utils = require "utils"

local ui = df.global.ui

local DRAW_CHARS = {
    ns = string.char(179),
    ew = string.char(196),
    ne = string.char(192),
    nw = string.char(217),
    se = string.char(218),
    sw = string.char(191),
}
local VALID_SIDEBAR_MODES = utils.invert{
    df.ui_sidebar_mode.Default,
    df.ui_sidebar_mode.LookAround,
}
-- persist across script runs
color = color or COLOR_LIGHTCYAN

BlockBordersOverlay = defclass(BlockBordersOverlay, guidm.MenuOverlay)
BlockBordersOverlay.ATTRS{
    block_size = 16,
    draw_borders = true,
}

function BlockBordersOverlay:onInput(keys)
    if keys.LEAVESCREEN then
        self:dismiss()
    elseif keys.D_PAUSE then
        self.draw_borders = not self.draw_borders
    elseif keys.CUSTOM_B then
        self.block_size = self.block_size == 16 and 48 or 16
    elseif keys.CUSTOM_C then
        color = color + 1
        if color > 15 then
            color = 1
        end
    elseif keys.CUSTOM_SHIFT_C then
        color = color - 1
        if color < 1 then
            color = 15
        end
    elseif keys.D_LOOK then
        self:sendInputToParent(ui.main.mode == df.ui_sidebar_mode.LookAround and 'LEAVESCREEN' or 'D_LOOK')
    else
        self:propagateMoveKeys(keys)
    end
end

function BlockBordersOverlay:onRenderBody(dc)
    dc = dc:viewport(1, 1, dc.width - 2, dc.height - 2)
    dc:key_string('D_PAUSE', 'Toggle borders')
      :newline()
    dc:key_string('CUSTOM_B', self.block_size == 16 and '1 block (16 tiles)' or '3 blocks (48 tiles)')
      :newline()
    dc:key('CUSTOM_C')
      :string(', ')
      :key_string('CUSTOM_SHIFT_C', 'Color: ')
      :string('Example', color)
      :newline()
    dc:key_string('D_LOOK', 'Toggle cursor')
      :newline()

    self:renderOverlay()
end

function BlockBordersOverlay:renderOverlay()
    local viewport = self:getViewport()
    local dc = gui.Painter.new(self.df_layout.map)
    local block_end = self.block_size - 1
    local cursor = guidm.getCursorPos()
    dc:map(true)
    dc:pen(color or COLOR_LIGHTCYAN)

    if self.draw_borders then
        for x = viewport.x1, viewport.x2 do
            local block_x = x % self.block_size
            for y = viewport.y1, viewport.y2 do
                local block_y = y % self.block_size
                local key
                if block_x == 0 and block_y == 0 then
                    key = 'se'
                elseif block_x == 0 and block_y == block_end then
                    key = 'ne'
                elseif block_x == block_end and block_y == 0 then
                    key = 'sw'
                elseif block_x == block_end and block_y == block_end then
                    key = 'nw'
                elseif block_x == 0 or block_x == block_end then
                    key = 'ns'
                elseif block_y == 0 or block_y == block_end then
                    key = 'ew'
                end
                if key and (not cursor or cursor.x ~= x or cursor.y ~= y) then
                    dc:seek(x - viewport.x1, y - viewport.y1):string(DRAW_CHARS[key])
                end
            end
        end
    end
end

local scr = dfhack.gui.getCurViewscreen()
if df.viewscreen_dwarfmodest:is_instance(scr) and VALID_SIDEBAR_MODES[ui.main.mode] then
    BlockBordersOverlay():show()
else
    qerror('This script must be run from the fortress mode screen with no sidebar open')
end
