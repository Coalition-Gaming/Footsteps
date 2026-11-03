-- The capture runner (the design's "Capture flow"): the timers, the interface, the
-- caption and Screenshot(). Core/Shots.lua's capture decides when a picture is taken and
-- which entries it serves, and Core/Interface.lua whether the interface may be hidden
-- and when it is owed back; this file asks them and does what they answer. Every path
-- gives the interface back: the client's answer, a Screenshot() that raises, five
-- seconds of silence, the start of combat, and the end of combat when lockdown had
-- begun. The caption (Caption.lua) goes when the picture settles, on every one of those
-- paths but combat's, which leaves the picture still being taken.

local _, ns = ...

local L = ns.L
local readable = ns.Secrets.readable

local Capture = {}
ns.Capture = Capture

---@class FootstepsCaptureRunner
---@field request fun(index: number, policy: FootstepsShotPolicy) a recorded entry wants its picture

-- The date stamp the client puts in a screenshot's file name (Shots.fileName).
local function stamp()
  return date("%m%d%y_%H%M%S")
end

local function isOpen(window)
  return window ~= nil and window:IsShown()
end

-- Popups whose OnHide ends what they ask about (Gethe forever at e3ecc27).
-- StaticPopup_Show parents each to UIParent (Blizzard_StaticPopup/StaticPopup.lua, line
-- 417, through GetAppropriateTopLevelParent, Blizzard_SharedXMLBase/FrameUtil.lua, lines
-- 304 to 310), so hiding UIParent runs its dialog's GameDialogMixin:OnHide, which calls
-- StaticPopup_OnHide and so the popup's own (Blizzard_StaticPopup_Game/GameDialog.lua,
-- line 735; StaticPopup.lua, lines 626 to 641). PARTY_INVITE's declines the invite
-- (Blizzard_StaticPopup_Game/GameDialogDefs.lua, lines 1319 to 1324), and Forever shows
-- an invite with it (GameEvent.HandlePartyInviteRequest, Blizzard_Game/Mainline/
-- EventImplementation.lua, lines 757 to 778); QUIT's cancels the logout
-- (GameDialogDefs.lua, lines 1451 to 1456); each EQUIP_BIND one's cancels the equip
-- (Mainline/GameDialogDefs.lua, lines 455, 479 and 503); and
-- PREMADE_GROUP_LEADER_CHANGE_DELIST_WARNING's can take the group's listing down
-- (GameDialogDefs.lua, lines 3377 to 3381). Not every popup: the release spirit dialog's
-- OnHide only resets its buttons (Mainline/GameDialogDefs.lua, lines 222 to 229), and a
-- check for any popup would keep the interface in every death's picture.
local POPUPS = {
  "PARTY_INVITE",
  "QUIT",
  "EQUIP_BIND",
  "EQUIP_BIND_REFUNDABLE",
  "EQUIP_BIND_TRADEABLE",
  "PREMADE_GROUP_LEADER_CHANGE_DELIST_WARNING",
}

-- Whether one of those popups is shown.
local function asking()
  for _, which in ipairs(POPUPS) do
    if StaticPopup_Visible(which) then
      return true
    end
  end
  return false
end

-- Whether hiding the interface would close what the player is doing. Each of these
-- windows sits in UIParent and ends its interaction in its OnHide (Gethe forever at
-- e3ecc27): GossipFrameSharedMixin:OnHide calls C_GossipInfo.CloseGossip
-- (Blizzard_UIPanels_Game/Shared/GossipFrameShared.lua, line 176), QuestFrame_OnHide
-- CloseQuest (Mainline/QuestFrame.lua, line 436), MerchantFrame_OnHide CloseMerchant
-- (Mainline/MerchantFrame.lua, line 163), LootFrameMixin:OnHide CloseLoot
-- (Mainline/LootFrame.lua, line 210), TradeFrame_OnHide CloseTrade (Mainline/
-- TradeFrame.lua, line 234), MailMixin:OnHide CloseMail (Blizzard_MailFrame/
-- MailFrame.lua, line 52), BankFrameBaseMixin:OnHide C_Bank.CloseBankFrame
-- (Mainline/BankFrameTemplates.lua, line 104), TaxiFrame's OnHide CloseTaxiMap
-- (Blizzard_UIPanels_Game/Shared/TaxiFrame.xml, line 44), ItemTextFrame's CloseItemText
-- (Mainline/ItemTextFrame.xml, lines 170 to 173), PetitionFrame's ClosePetition
-- (Mainline/PetitionFrame.xml, lines 202 to 206), TabardFrame's CloseTabardCreation
-- (Mainline/TabardFrame.xml, lines 381 to 384) and StableFrameMixin:OnHide
-- C_StableInfo.ClosePetStables (Blizzard_StableUI/Camelot/Blizzard_StableUI.lua, lines 61
-- and 62), on the frame Forever names PetStableFrame (Camelot/Blizzard_StableUI.xml, line
-- 79). Five more are in load-on-demand addons, so each is nil until its addon loads:
-- AuctionHouseFrameMixin:OnHide calls C_AuctionHouse.CloseAuctionHouse
-- (Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.lua, line 458),
-- ClassTrainerFrame_OnHide CloseTrainer (Blizzard_TrainerUI/Mainline/
-- Blizzard_TrainerUI.lua, line 284), ProfessionsMixin:OnHide
-- C_TradeSkillUI.CloseTradeSkill (Blizzard_Professions/Blizzard_ProfessionsFrame.lua,
-- line 539), FlightMapMixin:OnHide CloseTaxiMap (Blizzard_FlightMap/Blizzard_FlightMap.lua,
-- line 107) and GuildBankFrameMixin:OnHide CloseGuildBankFrame (Blizzard_GuildBankUI/
-- Mainline/Blizzard_GuildBankUI.lua, lines 124 to 129). GuildRegistrarFrame, the guild
-- charter vendor, calls CloseGuildRegistrar in its OnHide (Blizzard_UIPanels_Game/
-- Mainline/GuildRegistrarFrame.xml, lines 215 to 219), and GuildInviteFrame, a guild
-- invite, calls DeclineGuild unless the player accepted it (Blizzard_FrameXML/
-- GuildInviteFrame.xml, lines 150 to 156). The guild invite is not a popup asking() can
-- name: StaticPopupSpecial_Show shows it (GuildInviteFrame.lua, line 35), and puts it in
-- UIParent as StaticPopup_Show puts a popup (Blizzard_StaticPopup/StaticPopup.lua, lines
-- 949 and 905, through GetFullScreenFrame, lines 115 to 117). A flight master opens
-- TaxiFrame or FlightMapFrame, by its map (GameEvent.HandleTaxiMapOpened, Blizzard_Game/
-- Mainline/EventImplementation.lua, lines 735 to 741). A box with the keyboard, the chat
-- box say, would be hidden while the player types into it, and one of the popups above
-- would end what it asks about.
local function busy()
  return isOpen(GossipFrame)
    or isOpen(QuestFrame)
    or isOpen(MerchantFrame)
    or isOpen(LootFrame)
    or isOpen(TradeFrame)
    or isOpen(MailFrame)
    or isOpen(BankFrame)
    or isOpen(AuctionHouseFrame)
    or isOpen(ClassTrainerFrame)
    or isOpen(ProfessionsFrame)
    or isOpen(FlightMapFrame)
    or isOpen(TaxiFrame)
    or isOpen(ItemTextFrame)
    or isOpen(PetitionFrame)
    or isOpen(TabardFrame)
    or isOpen(PetStableFrame)
    or isOpen(GuildBankFrame)
    or isOpen(GuildRegistrarFrame)
    or isOpen(GuildInviteFrame)
    or asking()
    or GetCurrentKeyBoardFocus() ~= nil
end

---@param events table Kit.Events, for the client's screenshot and combat events
---@param db FootstepsDB the journal the entries are in
---@param say fun(entry: FootstepsEntry) says an entry in chat once its picture is settled
---@param changed fun() called once the entries have their picture, for the window
---@return FootstepsCaptureRunner
function Capture.new(events, db, say, changed)
  local capture = ns.Shots.newCapture()
  -- UIParent is hidden or shown only when this says so. It never does in combat,
  -- when UIParent's protected children lock it.
  local screen = ns.Interface.new()
  local caption = ns.Caption.new()

  -- The caption for the entries the picture serves so far, dated by the first of them.
  -- The character's name is read now, and left out if it comes secret.
  ---@param indexes number[]
  local function showCaption(indexes)
    local entries = {}
    for i, index in ipairs(indexes) do
      entries[i] = db.entries[index]
    end
    local name = readable((UnitName("player")))
    caption.show(ns.Format.caption(entries, L, name, ns.Dates.entry(entries[1].at, true)))
  end

  local onTimer

  -- A picture is settled. If milestones came while it was being taken, the timer for
  -- their picture is set first, so nothing below can leave them without one; it wakes on
  -- the next frame if their time has passed. Then take the caption away and give the
  -- interface back if Footsteps hid it, then the shot to every entry it served, then say
  -- each one, then tell the window. The next picture's own caption and interface wait
  -- for its timer. A picture saved after it was settled as lost only gets its file: the
  -- caption went, the interface came back, and each entry was said, when it was lost.
  ---@param indexes number[]?
  ---@param shot FootstepsShot?
  ---@param late boolean?
  ---@param fireAt number? when the picture for the milestones that waited is due
  local function settle(indexes, shot, late, fireAt)
    if indexes == nil or shot == nil then
      return
    end
    if fireAt ~= nil then
      C_Timer.After(math.max(fireAt - GetTime(), 0), onTimer)
    end
    if not late then
      caption.hide()
      if screen:restore(InCombatLockdown()) then
        UIParent:Show()
      end
    end
    ns.Journal.attachShot(db, indexes, shot)
    if not late then
      for _, index in ipairs(indexes) do
        say(db.entries[index])
      end
    end
    changed()
  end

  function onTimer()
    local now = GetTime()
    local action, detail = capture:due(now, stamp())
    if action == "wait" then
      ---@cast detail number
      C_Timer.After(detail - now, onTimer)
    elseif action == "fire" then
      ---@cast detail boolean
      -- The way back is set first, so nothing below can leave the picture pending and
      -- the interface hidden. The timer names its picture by when it fired.
      C_Timer.After(capture.timeout, function()
        settle(capture:expire(now))
      end)
      if db.settings.caption then
        showCaption(capture.indexes)
      end
      if screen:hide(detail, InCombatLockdown(), UIParent:IsShown(), busy()) then
        UIParent:Hide()
      end
      if not pcall(Screenshot) then
        settle(capture:finished(false))
      end
    end
  end

  events:On("SCREENSHOT_STARTED", function()
    capture:started(stamp())
  end)
  events:On("SCREENSHOT_SUCCEEDED", function()
    settle(capture:finished(true, C_CVar.GetCVar("screenshotFormat")))
  end)
  events:On("SCREENSHOT_FAILED", function()
    settle(capture:finished(false))
  end)
  -- On live clients PLAYER_REGEN_DISABLED comes before combat lockdown begins, so an
  -- interface Footsteps hid can still be shown and the player never fights without it.
  -- If lockdown has begun already, PLAYER_REGEN_ENABLED gives it back.
  events:On("PLAYER_REGEN_DISABLED", function()
    if screen:combatStarting(InCombatLockdown()) then
      UIParent:Show()
    end
  end)
  events:On("PLAYER_REGEN_ENABLED", function()
    if screen:combatEnded() then
      UIParent:Show()
    end
  end)

  ---@type FootstepsCaptureRunner
  local runner = {
    request = function(index, policy)
      local now = GetTime()
      local action, fireAt = capture:request(now, index, policy)
      if action == "schedule" then
        ---@cast fireAt number
        C_Timer.After(fireAt - now, onTimer)
      end
      -- "join": the scheduled picture serves this entry too, and its timer is already
      -- set; a later fire time is met by "wait" above. "queue": a picture is being taken,
      -- and settle sets the timer for the next one when it settles.
    end,
  }
  return runner
end
