-- The caption a picture carries (#96): what happened, then who, at what level, where and
-- when, in the bottom-right corner for the moment of the picture. The client names every
-- screenshot file itself and an addon cannot rename one, so the picture says what it is.
-- Core/Format.lua's caption has the words, and the capture runner (Capture.lua) says
-- when. The frame sits in WorldFrame, not UIParent, so it stays on screen while the
-- interface is hidden for the picture, and it takes the interface's scale, so its text
-- is the size of the interface's own.

local _, ns = ...

local Caption = {}
ns.Caption = Caption

-- Space between the box's edge and the screen's, and between the text and the box's edge.
local MARGIN, PADDING = 24, 10

-- The sentences take the font's own gold, and the line under them is white.
local DETAIL = "|cffffffff%s|r"

---@class FootstepsCaption
---@field show fun(title: string, detail: string) puts the caption on screen
---@field hide fun() takes it away

---@return FootstepsCaption
function Caption.new()
  local frame = CreateFrame("Frame", nil, WorldFrame)
  frame:SetAllPoints()
  frame:SetFrameStrata("TOOLTIP")
  frame:Hide()

  -- One font string for both parts, right-aligned, and a translucent box drawn behind it
  -- that grows with the text.
  local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  text:SetJustifyH("RIGHT")
  text:SetPoint("BOTTOMRIGHT", -(MARGIN + PADDING), MARGIN + PADDING)
  local box = frame:CreateTexture(nil, "BACKGROUND")
  box:SetColorTexture(0, 0, 0, 0.55)
  box:SetPoint("TOPLEFT", text, "TOPLEFT", -PADDING, PADDING)
  box:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", PADDING, -PADDING)

  ---@type FootstepsCaption
  return {
    show = function(title, detail)
      -- The interface's scale can change between pictures, with the game's UI scale.
      frame:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())
      text:SetText(title .. "\n" .. DETAIL:format(detail))
      frame:Show()
    end,
    hide = function()
      frame:Hide()
    end,
  }
end
