-- The journal window (DECISION-004, "The window"; the design's "The window"). /footsteps
-- opens and closes it, and so do Escape and its close button. Core/Timeline.lua works out
-- the rows, the title, the filter's checkboxes and the open entry's detail,
-- Core/Selection.lua which entry is open, and Core/Position.lua where the window opens;
-- this file puts them on screen, with Detail.lua for the open entry. The frame is made
-- the first time the window opens, not at login. Everything in it is Blizzard's, used as
-- Blizzard's code on the forever branch uses it (Gethe/wow-ui-source, forever at
-- e3ecc27):
--   - Blizzard_AddOnList/AddonList.xml, lines 120 to 222: the game's AddOn list, a frame
--     on ButtonFrameTemplate with a DropdownButton on WowStyle1DropdownTemplate, a
--     WowScrollBoxList and a MinimalScrollBar.
--   - Blizzard_Menu/Menu.lua, lines 1750 to 1778: a WowScrollBoxList and a
--     MinimalScrollBar made with CreateFrame, a CreateScrollBoxListLinearView whose rows
--     are a frame type ("Frame"), given by SetElementInitializer, and
--     ScrollUtil.InitScrollBoxListWithScrollBar.
--   - Blizzard_FriendsFrame/Camelot/FriendsFrame.lua, lines 335 and 795 to 866, in a file
--     only Forever loads: a linear view filled with CreateDataProvider, and
--     SetDataProvider keeping the scroll position.
--   - Blizzard_SharedXML/Shared/Scroll/ScrollBoxListView.lua, lines 480 to 494:
--     SetElementInitializer("Button", ...), with each row's parts made once.

local _, ns = ...

local Window = {}
ns.Window = Window

local L = ns.L
local Timeline, Position, Format, Migrations = ns.Timeline, ns.Position, ns.Format, ns.Migrations
local Journal, Selection, Detail, Dates = ns.Journal, ns.Selection, ns.Detail, ns.Dates
local readable = ns.Secrets.readable

-- The client makes the frame global under this name, which UISpecialFrames needs.
local NAME = "FootstepsFrame"
-- The list on the left, as wide as the window was before it had a detail view, and the
-- open entry on the right.
local LIST_WIDTH = 510
local DETAIL_GAP = 14
local WIDTH, HEIGHT = 4 + LIST_WIDTH + DETAIL_GAP + Detail.WIDTH + 12, 480
local ROW_HEIGHT = 22
local DATE_WIDTH = 76

-- The row's two marks, each one of the game's own textures that Blizzard's code uses on
-- the forever branch (Gethe/wow-ui-source, commit e3ecc27, build 70205), in a file that
-- loads for every game type. Probe Q15 checks they draw.
-- Blizzard_Communities/ClubFinder.xml, line 1298: the club finder's pending tab
local PICTURE_MARK = "Interface\\Icons\\inv_misc_notepicture1c"
-- Blizzard_UIPanels_Game/Mainline/QuestInfo.xml, line 541: a quest's title icon
local NOTE_MARK = "Interface\\Icons\\INV_Misc_Note_02"
-- Blizzard_AddOnList/AddonList.xml, line 5: each row's highlight
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"

---@class FootstepsWindow
---@field toggle fun() opens the window, or closes it
---@field refresh fun() shows the journal as it is now, while the window is open
---@field refreshTitle fun() shows time played as it is now in the title, while the window is open

---@class FootstepsRowFrame : Button
---@field Date FontString
---@field Icon Texture
---@field Text FontString
---@field Level FontString
---@field Picture Texture
---@field Note Texture
---@field index number? the entry the row shows

-- The frame on ButtonFrameTemplate, with the two parts of the template this file uses.
---@class FootstepsWindowFrame : Frame
---@field Inset Frame the template's inset, which holds the list
---@field CloseButton Button
---@field Detail FootstepsDetailFrame the open entry, beside the list

-- The words Core/Timeline.lua asks for. Dates.lua writes the date, as it does the chat
-- list's.
---@type FootstepsText
local text = {
  L = L,
  date = Dates.entry,
  line = function(entry)
    return Format.line(entry, L)
  end,
  place = function(entry)
    return Format.place(entry, L)
  end,
  duration = function(seconds)
    return Format.duration(seconds, L)
  end,
  -- The detail view's (step 6); the list does not ask for it.
  difficulty = function(id)
    return readable((GetDifficultyInfo(id)))
  end,
}

---@param db FootstepsDB the journal, loaded and writable
---@param played FootstepsPlayed time played, from Footsteps.lua
---@return FootstepsWindow
function Window.new(db, played)
  -- The filter lasts for the session and is never saved: every kind ticked, hidden
  -- entries left out, at each login.
  local filter = Timeline.newFilter(Migrations.kinds)
  -- The open entry, kept as the filter is: while the window closes and opens again, and
  -- never saved. What its button and note box do goes through Journal, bound here to the
  -- saved journal, because Core/Selection.lua does not read another Core module.
  local selection = Selection.new({
    hide = function(index)
      Journal.hide(db, index)
    end,
    restore = function(index)
      Journal.restore(db, index)
    end,
    setNote = function(index, note)
      Journal.setNote(db, index, note)
    end,
  })
  local frame, list, detail, hint

  -- Whether the list shows an entry, which the selection follows.
  local function listed(index)
    return Timeline.listed(db.entries, filter, index)
  end

  -- The title from the journal and time played as they are now.
  local function refreshTitle()
    local total = played:read(GetTime())
    frame:SetTitle(Timeline.titleText(db.entries, total, readable(UnitName("player")), text))
  end

  -- The rows, the title and the open entry from the journal as it is now. An entry that
  -- has left the list is closed first. The note box is loaded only with `loadNote`,
  -- when another entry opens or the window opens, so a refresh never takes away what
  -- the player is typing.
  ---@param loadNote boolean
  local function refresh(loadNote)
    local index = selection:follow(listed)
    list:SetDataProvider(CreateDataProvider(Timeline.rows(db.entries, filter, text)), true) -- RetainScrollPosition
    refreshTitle()
    local open = index and Timeline.detail(db.entries, index, text) or nil
    detail.show(open, loadNote)
    hint:SetShown(open == nil)
  end

  -- A click on a row opens its entry. A second click on the open one changes nothing,
  -- so the note box keeps what is being typed.
  ---@param row FootstepsRowFrame
  local function pick(row)
    if row.index then
      refresh(selection:select(row.index))
    end
  end

  -- What hovering a row shows: its sentence, then the rest from Timeline.tooltip.
  ---@param row FootstepsRowFrame
  local function showTooltip(row)
    local lines = row.index and Timeline.tooltip(db.entries, row.index, text)
    if lines == nil then
      return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, row.Text:GetText())
    for _, line in ipairs(lines) do
      GameTooltip_AddNormalLine(GameTooltip, line)
    end
    GameTooltip:Show()
  end

  local function hideTooltip()
    GameTooltip:Hide()
  end

  -- A row's parts, made once per frame: the date, the kind's icon, the sentence, the
  -- level, and the picture and note marks, whose places are kept when they are hidden
  -- so the columns line up.
  ---@param row FootstepsRowFrame
  local function build(row)
    row:SetHighlightTexture(HIGHLIGHT, "ADD")
    row.Date = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Date:SetPoint("LEFT", 4, 0)
    row.Date:SetWidth(DATE_WIDTH)
    row.Date:SetJustifyH("LEFT")
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(16, 16)
    row.Icon:SetPoint("LEFT", row.Date, "RIGHT", 4, 0)
    row.Note = row:CreateTexture(nil, "ARTWORK")
    row.Note:SetSize(14, 14)
    row.Note:SetPoint("RIGHT", -4, 0)
    row.Note:SetTexture(NOTE_MARK)
    row.Picture = row:CreateTexture(nil, "ARTWORK")
    row.Picture:SetSize(14, 14)
    row.Picture:SetPoint("RIGHT", row.Note, "LEFT", -2, 0)
    row.Picture:SetTexture(PICTURE_MARK)
    row.Level = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.Level:SetPoint("RIGHT", row.Picture, "LEFT", -6, 0)
    row.Level:SetWidth(22)
    row.Level:SetJustifyH("RIGHT")
    row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
    row.Text:SetPoint("RIGHT", row.Level, "LEFT", -6, 0)
    row.Text:SetJustifyH("LEFT")
    row.Text:SetWordWrap(false)
    row:SetScript("OnEnter", showTooltip)
    row:SetScript("OnLeave", hideTooltip)
    row:SetScript("OnClick", pick)
  end

  -- The scroll box makes frames only for the rows in view, and gives each its row from
  -- Timeline.rows as they scroll. A hidden entry, listed with "Show hidden", is greyed.
  ---@param row FootstepsRowFrame
  ---@param data FootstepsRow
  local function initRow(row, data)
    if row.Text == nil then
      build(row)
    end
    row.index = data.index
    row.Date:SetText(data.date)
    row.Icon:SetTexture(data.icon)
    row.Icon:SetDesaturated(data.hidden)
    row.Text:SetText(data.text)
    row.Level:SetText(data.level and tostring(data.level) or "")
    row.Picture:SetShown(data.hasPicture)
    row.Note:SetShown(data.hasNote)
    row:SetAlpha(data.hidden and 0.5 or 1)
    -- The open entry's row stays lit, whichever frame shows it.
    row:SetHighlightLocked(data.index == selection:get())
    -- The list changed under the mouse: OnEnter does not run again, so the tooltip this
    -- row shows is drawn again for its new entry.
    if GameTooltip:GetOwner() == row and GameTooltip:IsShown() then
      showTooltip(row)
    end
  end

  -- The filter: a checkbox per kind in the settings' order, then "Show hidden". The
  -- menu stays open while the player ticks, and the list follows each click.
  local function ticked(kind)
    return Timeline.ticked(filter, kind)
  end
  local function toggle(kind)
    Timeline.toggle(filter, kind)
    refresh(false)
  end
  local function showsHidden()
    return filter.showHidden
  end
  local function toggleHidden()
    Timeline.toggleHidden(filter)
    refresh(false)
  end

  -- What the detail view passes back. Hiding needs nothing confirmed and prints nothing
  -- (DECISION-004, assumption 9). A note is saved as it is typed; the list is drawn again
  -- only when the entry gains its note or loses it, so the row's mark follows.
  ---@type FootstepsDetailActions
  local actions = {
    hideOrRestore = function()
      selection:hideOrRestore(db.entries)
      refresh(false)
    end,
    noteTyped = function(note)
      if selection:saveNote(db.entries, note) then
        refresh(false)
      end
    end,
  }

  -- The frame and everything in it. It is shown once made, as every new frame is.
  local function create()
    local new = CreateFrame("Frame", NAME, UIParent, "ButtonFrameTemplate") --[[@as FootstepsWindowFrame]]
    new:SetSize(WIDTH, HEIGHT)
    ButtonFrameTemplate_HidePortrait(new)
    ButtonFrameTemplate_HideButtonBar(new)
    -- The inset holds the list only. Blizzard's FrameTemplate_SetButtonBarHeight, which
    -- ButtonFrameTemplate_HideButtonBar calls, sets the inset's bottom right corner to the
    -- frame's (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua, lines 57 to 63, at
    -- e3ecc27); this sets the same corner further left, at the list's width.
    new.Inset:SetPoint("BOTTOMRIGHT", new, "BOTTOMLEFT", 4 + LIST_WIDTH, 4)
    new:SetToplevel(true)
    new:SetClampedToScreen(true)
    -- place() alone decides where the window opens, from settings.window. A frame the
    -- player moved is otherwise written to the character's layout cache
    -- (WTF\Account\<acct>\<realm>\<character>\layout-local.txt) at logout; this keeps
    -- the window out of it.
    new:SetDontSavePosition(true)
    new:SetMovable(true)
    new:EnableMouse(true)
    new:RegisterForDrag("LeftButton")
    new:SetScript("OnDragStart", new.StartMoving)
    new:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      Position.remember(db.settings.window, self:GetLeft(), self:GetTop())
    end)
    -- The template's close button calls HideUIPanel, which refuses in combat when the
    -- call is not secure (Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua,
    -- lines 854 to 858 and 920, Gethe forever at e3ecc27). The window is not a UI panel
    -- and nothing in it is protected, so it simply hides.
    new.CloseButton:SetScript("OnClick", function()
      new:Hide()
    end)
    -- Escape closes the frames named in UISpecialFrames.
    tinsert(UISpecialFrames, NAME)

    local dropdown = CreateFrame("DropdownButton", nil, new, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", 12, -30)
    dropdown:SetWidth(140)
    -- Fixed text: this template's text otherwise lists every ticked box.
    dropdown:OverrideText(L["Filter"])
    dropdown:SetupMenu(function(_, root)
      for _, kind in ipairs(Migrations.kinds) do
        root:CreateCheckbox(Timeline.kindName(kind, L), ticked, toggle, kind)
      end
      root:CreateDivider()
      root:CreateCheckbox(L["Show hidden"], showsHidden, toggleHidden)
    end)

    list = CreateFrame("Frame", nil, new.Inset, "WowScrollBoxList")
    list:SetPoint("TOPLEFT", 4, -4)
    list:SetPoint("BOTTOMRIGHT", -20, 4)
    local bar = CreateFrame("EventFrame", nil, new.Inset, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, -2)
    bar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 6, 2)
    local view = CreateScrollBoxListLinearView()
    -- A frame type rather than a template has no height to read, so the rows' is set.
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", initRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(list, bar, view)

    -- The open entry, beside the list, and a line in its place while none is open.
    detail = Detail.create(new, actions)
    detail.frame:SetPoint("TOPLEFT", new.Inset, "TOPRIGHT", DETAIL_GAP, -4)
    detail.frame:SetSize(Detail.WIDTH, HEIGHT - 60 - 8)
    new.Detail = detail.frame
    hint = new:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    hint:SetPoint("CENTER", detail.frame, "CENTER")
    hint:SetWidth(Detail.WIDTH)
    hint:SetText(L["Click an entry to open it here."])
    return new
  end

  -- Opening anchors the window from settings.window and shows the journal as it is now.
  local function place()
    local point, relativePoint, x, y = Position.anchor(db.settings.window)
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, relativePoint, x, y)
  end

  ---@type FootstepsWindow
  local window = {
    -- Whether it is open is the frame's own state, so Escape and the close button,
    -- which hide it, need nothing from here.
    toggle = function()
      if frame == nil then
        frame = create()
      elseif frame:IsShown() then
        frame:Hide()
        return
      end
      place()
      refresh(true)
      frame:Show()
    end,
    -- Shown, not visible: while a picture hides the interface the window stays open,
    -- and it is current when the interface comes back.
    refresh = function()
      if frame ~= nil and frame:IsShown() then
        refresh(false)
      end
    end,
    -- When the client answers about time played; the rows do not change.
    refreshTitle = function()
      if frame ~= nil and frame:IsShown() then
        refreshTitle()
      end
    end,
  }
  return window
end
