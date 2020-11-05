#*****************************************************************************
#* File: lua/modules/ui/game/SCREEN_skilltree.lua
#*
#* Copyright � 2008 Gas Powered Games, Inc.  All rights reserved.
#*****************************************************************************

local UIMain = import('/lua/ui/uimain.lua')
local UIUtil = import('/lua/ui/uiutil.lua')
local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local Group = import('/lua/maui/group.lua').Group
local Bitmap = import('/lua/maui/bitmap.lua').Bitmap
local Button = import('/lua/maui/button.lua').Button
local Window = import('/lua/ui/controls/window.lua').Window
local TreePicker = import('/lua/ui/game/TreePicker.lua').TreePicker
local EffectHelpers = import('/lua/maui/effecthelpers.lua')
local Tooltip = import('/lua/ui/game/tooltip.lua')
local GameCommon = import('/lua/ui/game/gamecommon.lua')
local Common = import('/lua/common/CommonUtils.lua')
local InGameUI = import('/lua/ui/game/InGameUI.lua')
local Shop = import('/lua/ui/game/SCREEN_shop_tabbed.lua')
local CharWindow = import('/lua/ui/game/SCREEN_hero.lua')
local InfoPanel  = import('/lua/ui/game/HUD_infopanel.lua')
local Scoreboard  = import('/lua/ui/game/HUD_scoreboard.lua')
local Citadel  = import('/lua/ui/game/SCREEN_citadel.lua')
local CanPickSkill = import('/lua/common/ValidateSkill.lua').CanPickSkill
local AchievementShop = import('/lua/ui/game/SCREEN_shopachievements.lua')
local MsgsFailure = import('/lua/ui/game/HUD_msgs_failure.lua').ShowFailureMsg
local UserSync = import('/lua/UserSync.lua')
local HeroUnit = import('/lua/sim/HeroUnit.lua').HeroUnit
local Skill = import('/lua/sim/skill.lua')

local overlay_have = '/skill_circleframe_have.dds'
local overlay_canpick = '/skill_circleframe_glow.dds'
local overlay_invalid = '/skill_circleframe_invalid.dds'
local overlay_owned = '/skill_circleframe_owned.dds'

local NoPoints = false
local points = nil
local pulseThread = false
local SkillTreeButton = nil
local hero = nil
local SkillTreeGUI = nil
local syncData = nil
local savedHero = nil
local savedHeroTree = nil
local checkedHero = false
local isReplay = false

# Audio cues, used when ability specific entries do not exist in the ability
local DefaultOnEnterCue = 'Forge/UI/Hud/snd_ui_hud_generic_mouseover'
local DefaultOnActivateCue = 'Forge/UI/Hud/snd_ui_hud_generic_click'

# Other screens need to close this one if its visible when they open
function CloseSkillTreeScreen()
    if SkillTreeGUI and not SkillTreeGUI:IsHidden() then
        SkillTreeGUI:Hide()
    end
end

function CheckSkillTreeVisible()
    if SkillTreeGUI and not IsDestroyed(SkillTreeGUI) and SkillTreeGUI:IsHidden() then
        return false
    else
        return true
    end
end


# So that we can toggle the skills from a hotkey
function ToggleSkills()
    SkillTreeButton:OnClick()
end


local function PulseIcon(ctrl)
   while true do
        EffectHelpers.FadeOut(ctrl.icon, 2.0, 1, 0.2)
        #Play sound for when skill tree pulses
        PlaySound( 'Forge/UI/Hud/snd_ui_hud_skill_button_pulse' )
        WaitSeconds(2)
   end
end


local function ShowSkillsIndicator(btn)
    while true do
        EffectHelpers.FadeIn(btn, 1.0, 0, 1)
        WaitSeconds(5)
        EffectHelpers.FadeOut(btn, 1.0, 1, 0)
    end
end

local function CreatePopupButton(parent)
    local btn = UIUtil.CreateButton(parent,
        '/buttons/newskillpoints.dds',
        '/buttons/newskillpoints.dds',
        '/buttons/newskillpoints.dds',
        '/buttons/newskillpoints.dds')
    btn.Width:Set(80)
    btn.Height:Set(80)
    LayoutHelpers.AtBottomIn(btn, GetFrame(0), 24)
    LayoutHelpers.AtHorizontalCenterIn(btn, GetFrame(0), -410)

    return btn
end


function CreateTree()
    #currentHero = SkillTreeButton.hero

    if not SkillTreeButton.hero then
        error('No hero available to build a skill tree for.')
        return
    end

    if SkillTreeGUI.tree then
        SkillTreeGUI.tree:Destroy()
        NoPoints = false
        points = nil
        hero = nil
        syncData = nil
        savedHero = nil
        savedHeroTree = nil
        checkedHero = false
    end
    
    SkillTreeGUI.tree = TreePicker(SkillTreeGUI, 'Skill Tree Client')
    local tree = SkillTreeGUI.tree

    ####### TREE FUNCTIONS #######
    ### Tree: Has Skill
    function tree.HasSkill(self, name)
        return (self.skills != nil) and (table.find(self.skills, name) != nil)
    end

    ### Tree: Get Icon
    function tree.GetIcon(self, item)
        local icon = item.Icon
        if not icon and item.Gains then
            icon = item.Gains[1]
        end
        return UIUtil.UIFile('/abilities/icons/'..icon..'.dds')
    end

    ### Tree: On Item Click
    function tree.OnItemClick(self, slot, event)
        if isReplay then
            return
        end
        if SkillTreeButton.hero and not SkillTreeButton.hero:IsDead() and slot.canpick and tree.points > 0 then
            PurchaseSkill( SkillTreeButton.hero, slot.image.item )
            PlaySound('Forge/UI/Hud/snd_ui_skilltree_click')
            self.UpdateTime = GetGameTimeSeconds()

            SkillTreeGUI:UpdateTreeTitle()

            if not self.skills then
                self.skills = {}
            end
            table.insert( self.skills, slot.image.item )

            self.points = self.points - 1
            if self.points == 0 then
                SkillTreeGUI.closeButton.OnClick()
            end
             
            self:UpdateTree()
        else
            #LOG("Sorry, you can't pick that.")
            #MsgsFailure('<LOC error_0026>Unable to purchase skill')
            CanPickSkill(SkillTreeButton.hero, slot.image.item, false, true)
            PlaySound( 'Forge/UI/Hud/snd_ui_ingame_unique_fail' )
        end
    end

    ### Tree: Update Item
    function tree.UpdateItem(self, slot)
        slot.overlay:SetAlpha(1)
        slot.underlay:SetAlpha(1)
        if self:HasSkill(slot.image.item) then
            slot.canpick = false
            slot.frame.Disable(self)
            if slot.underlay.Pulsing then
                EffectHelpers.StopPulse(slot.underlay)
            end
            #slot.underlay:SetAlpha(0)
            slot.underlay:SetTexture(UIUtil.UIFile(overlay_owned))
            if NoPoints then
                slot.overlay:SetAlpha(0)
            else
                slot.overlay:SetTexture(UIUtil.UIFile(overlay_have))
                slot.overlay:SetAlpha(0.4)
            end
        elseif CanPickSkill(SkillTreeButton.hero, slot.image.item, true) then
            slot.overlay:SetAlpha(0)
            if NoPoints then
                if slot.underlay.Pulsing then
                    EffectHelpers.StopPulse(slot.underlay)
                end
                slot.underlay:SetAlpha(0)
                slot.overlay:SetTexture(UIUtil.UIFile(overlay_invalid))
                slot.overlay:SetAlpha(1)
            else
                slot.underlay:SetTexture(UIUtil.UIFile(overlay_canpick))
                EffectHelpers.Pulse(slot.underlay, 1.0, 0.4, 1)
                slot.underlay:SetAlpha(1)
                slot.overlay:SetAlpha(0)
            end
            slot.canpick = true
            slot.frame.Enable(self)
        else
            slot.overlay:SetTexture(UIUtil.UIFile(overlay_invalid))
            slot.overlay:SetAlpha(1)
            slot.canpick = false
            slot.frame.Disable(self)
            if slot.underlay.Pulsing then
                EffectHelpers.StopPulse(slot.underlay)
            end
            slot.underlay:SetAlpha(0)
        end
    end

    ### Tree: Mouseover Item
    function tree.OnMouseEnterItem(self, slot)
        # Because the stats buffs are in a separate definitions file, we have to
        # create a special table to pass in for these
        if string.sub(slot.image.item, 1, 9) == 'StatsBuff' then
            local def = nil
            if SkillTreeButton.hero and not SkillTreeButton.hero:IsDead()then
                def = SkillTreeButton.hero:GetBlueprint().Abilities.Tree[slot.image.item]
            else
                #def = savedHero:GetBlueprint().Abilities.Tree[slot.image.item]
                def = savedHeroTree[slot.image.item]
            end
            local buffsData = {}

            buffsData.DisplayName = def.Name
            buffsData.Description = def.Description

            slot.image.tooltip = Tooltip.CreateAbilityTooltip(slot.image, buffsData, true)
        else
            local abilityDef = Ability[slot.image.item]
            slot.image.tooltip = Tooltip.CreateAbilityTooltip(slot.image, abilityDef, true)
        end
        PlaySound( 'Forge/UI/Hud/snd_ui_hud_generic_mouseover' ) 
    end

    ### Tree: Mouseexit Item
    function tree.OnMouseExitItem(self, slot)
        if slot.image.tooltip then
            slot.image.tooltip:Destroy()
        end
    end
    
    function tree.UpdateLevel(self, slot)
    end

    ### Tree: Update
    function tree.UpdateTree(self)
        if not SkillTreeButton.hero or SkillTreeButton.hero:IsDead() then
            return
        end

        local dirty = false
        local syncData = EntityData[SkillTreeButton.hero:GetEntityId()]

        if self.points != syncData.SkillPoints then
            dirty = true
            self.points = syncData.SkillPoints
        end

        if self.UpdateTime and GetGameTimeSeconds() > (self.UpdateTime + 0.3) then
            self.UpdateTime = GetGameTimeSeconds()

            if self.skills != syncData.Skills then
                self.UpdateTime = GetGameTimeSeconds()
                dirty = true
                self.skills = syncData.Skills
            end
        else
            self.UpdateTime = GetGameTimeSeconds()
        end

        if not IsDestroyed(self) and self.points == 0 and not self:IsHidden() then
            dirty = true
            NoPoints = true
            if SkillTreeGUI.pointsglow.Pulsing then
                EffectHelpers.StopPulse(SkillTreeGUI.pointsglow)
                SkillTreeGUI.pointsglow:SetAlpha(0)
                SkillTreeGUI.pointsinner:SetAlpha(0.7)
            end
        else
            NoPoints = false
            if not SkillTreeGUI.pointsglow.Pulsing then
                EffectHelpers.Pulse(SkillTreeGUI.pointsglow, 2.0, 0, 1)
                SkillTreeGUI.pointsinner:SetAlpha(1)
            end
        end

        #if dirty and self.tree then
        if dirty then
            self:Update()
            SkillTreeGUI:UpdateTreeTitle()
        end
    end

    # Populate the tree

    local heroCharacter = SkillTreeButton.hero:GetBlueprint().Display.Character
    local layout = UserSync.AbilitiesTable[heroCharacter]
    if not layout then
        layout = import(SkillTreeButton.hero:GetBlueprint().Abilities.Layout).Layout
    end
    local data = SkillTreeButton.hero:GetBlueprint().Abilities.Tree
    local syncData = EntityData[SkillTreeButton.hero:GetEntityId()]

    tree.points = syncData.SkillPoints
    tree.skills = syncData.Skills
    SkillTreeGUI:UpdateTreeTitle()

    # Torch Bearers tree is big, so modify accordingly
    if SkillTreeButton.hero:GetBlueprint().Display.Character == 'Mage' or 'MageFire' then
        local GRID_WIDTH    = 52
        local GRID_HEIGHT   = 52
        local ITEM_WIDTH    = 60
        local ITEM_HEIGHT   = 60
        tree:Layout(layout, data, GRID_WIDTH, GRID_HEIGHT, ITEM_WIDTH, ITEM_HEIGHT)
    else
        tree:Layout(layout, data)
    end

    LayoutHelpers.AtCenterIn(tree, SkillTreeGUI, -10, 0)
    LayoutHelpers.DepthOverParent(tree, SkillTreeGUI, 10)
    #tree.Depth:Set(6000)

    tree:UpdateTree()

end

local function OnFocusArmyHeroChange(hero)
    if not hero then
        return
    end

    SkillTreeButton.hero = hero
    CreateTree()
end


function Create(parent, inIsReplay)
    isReplay = inIsReplay
    InGameUI.OnFocusArmyHeroChange:Add(OnFocusArmyHeroChange)

    # Create the basic GUI
    SkillTreeGUI = Group(parent, 'Skill Tree')
    #LayoutHelpers.CenteredAbove(SkillTreeGUI, parent, -50)
    SkillTreeGUI.Width:Set(1000)
    SkillTreeGUI.Height:Set(647)

    SkillTreeGUI.bg = Bitmap(SkillTreeGUI, '/textures/ui/hud/screen_skilltree.dds')
    LayoutHelpers.FillParent(SkillTreeGUI.bg, SkillTreeGUI)
    SkillTreeGUI.bg.Depth:Set( SkillTreeGUI.Depth )

    SkillTreeGUI.pointsbg = Bitmap(SkillTreeGUI, '/textures/ui/common/circleframe.dds')
    SkillTreeGUI.pointsbg.Width:Set(80)
    SkillTreeGUI.pointsbg.Height:Set(80)
    LayoutHelpers.AtLeftTopIn(SkillTreeGUI.pointsbg, SkillTreeGUI.bg)

    SkillTreeGUI.pointsinner = Bitmap(SkillTreeGUI, '/textures/ui/common/circleframe_inner.dds')
    SkillTreeGUI.pointsinner.Width:Set(81)
    SkillTreeGUI.pointsinner.Height:Set(81)
    LayoutHelpers.AtCenterIn(SkillTreeGUI.pointsinner, SkillTreeGUI.pointsbg, 0.5, -0.5)

    SkillTreeGUI.pointsglow = Bitmap(SkillTreeGUI, '/textures/ui/common/circleframe_glow.dds')
    SkillTreeGUI.pointsglow.Width:Set(98)
    SkillTreeGUI.pointsglow.Height:Set(98)
    LayoutHelpers.AtCenterIn(SkillTreeGUI.pointsglow, SkillTreeGUI.pointsinner)
    LayoutHelpers.DepthUnderParent(SkillTreeGUI.pointsglow, SkillTreeGUI.pointsinner)

    EffectHelpers.Pulse(SkillTreeGUI.pointsglow, 2.0, 0, 1)

    SkillTreeGUI.title = UIUtil.CreateText(SkillTreeGUI, 'Skill Points', 36, UIUtil.bodyFont)
    SkillTreeGUI.title:DisableHitTest()
    LayoutHelpers.AtCenterIn(SkillTreeGUI.title, SkillTreeGUI.pointsbg, -1, -4)
    SkillTreeGUI.title:SetColor('ff000000')

    # Skill Reset Button
    SkillTreeGUI.skillResetButton = UIUtil.CreateButton(SkillTreeGUI,
        '/buttons/dummy.dds',
        '/buttons/dummy.dds',
        '/buttons/dummy.dds',
        '/buttons/dummy.dds')
    LayoutHelpers.AtRightTopIn(SkillTreeGUI.skillResetButton, SkillTreeGUI, 70, 70)
    SkillTreeGUI.skillResetButton.Width:Set(GameCommon.abilityIconWidth)
    SkillTreeGUI.skillResetButton.Height:Set(GameCommon.abilityIconHeight)
    SkillTreeGUI.skillResetButton.Depth:Set(function() return SkillTreeGUI.bg.Depth() + 1000 end)

    SkillTreeGUI.skillResetButton.icon = Bitmap(SkillTreeGUI.skillResetButton, UIUtil.UIFile('/buttons/close_icon.dds'))
    SkillTreeGUI.skillResetButton.icon.Width:Set(26)
    SkillTreeGUI.skillResetButton.icon.Height:Set(26)
    LayoutHelpers.AtCenterIn(SkillTreeGUI.skillResetButton.icon, SkillTreeGUI.skillResetButton)
    SkillTreeGUI.skillResetButton.icon.Depth:Set( function() return SkillTreeGUI.skillResetButton.Depth() - 2 end)
    SkillTreeGUI.skillResetButton.icon:SetAlpha(0)

    function SkillTreeGUI.skillResetButton.OnClick(btn)
        if isReplay then
            return
        end
        
        if SkillTreeButton.hero and  not SkillTreeButton.hero:IsDead() then
            print("Pushed a button")

            local syncData = EntityData[SkillTreeButton.hero:GetEntityId()]

            syncData.SkillPoints = 30
            syncData.Skills = {}
            SkillTreeGUI.tree.points = 30
            SkillTreeGUI.tree.skills = {}

            EntityData[SkillTreeButton.hero:GetEntityId()] = syncData
        end
    end

    function SkillTreeGUI.skillResetButton.HandleEvent(btn, event)
        if event.Type == 'MouseEnter' then
            PlaySound( 'Forge/UI/Hud/snd_ui_hud_generic_mouseover' )
            SkillTreeGUI.skillResetButton.icon:SetAlpha(1)
        elseif event.Type == 'MouseExit' then
            SkillTreeGUI.skillResetButton.icon:SetAlpha(0)
        end
        return Button.HandleEvent(btn, event)
    end

    # Close Button
    SkillTreeGUI.closeButton = UIUtil.CreateButton(SkillTreeGUI,
        '/buttons/dummy.dds',
        '/buttons/dummy.dds',
        '/buttons/dummy.dds',
        '/buttons/dummy.dds')
    LayoutHelpers.AtRightTopIn(SkillTreeGUI.closeButton, SkillTreeGUI, 15, 20)
    SkillTreeGUI.closeButton.Width:Set(GameCommon.abilityIconWidth)
    SkillTreeGUI.closeButton.Height:Set(GameCommon.abilityIconHeight)
    SkillTreeGUI.closeButton.Depth:Set(function() return SkillTreeGUI.bg.Depth() + 1000 end)

    SkillTreeGUI.closeButton.icon = Bitmap(SkillTreeGUI.closeButton, UIUtil.UIFile('/buttons/close_icon.dds'))
    SkillTreeGUI.closeButton.icon.Width:Set(26)
    SkillTreeGUI.closeButton.icon.Height:Set(26)
    LayoutHelpers.AtCenterIn(SkillTreeGUI.closeButton.icon, SkillTreeGUI.closeButton)
    SkillTreeGUI.closeButton.icon.Depth:Set( function() return SkillTreeGUI.closeButton.Depth() - 2 end)
    SkillTreeGUI.closeButton.icon:SetAlpha(0)

    function SkillTreeGUI.closeButton.OnClick(btn)
        PlaySound( 'Forge/UI/snd_ui_generic_close' ) 
        SkillTreeGUI:Hide()
        
    end

    function SkillTreeGUI.closeButton.HandleEvent(btn, event)
        if event.Type == 'MouseEnter' then
        	PlaySound( 'Forge/UI/Hud/snd_ui_hud_generic_mouseover' )
            SkillTreeGUI.closeButton.icon:SetAlpha(1)
        elseif event.Type == 'MouseExit' then
            SkillTreeGUI.closeButton.icon:SetAlpha(0)
        end
        return Button.HandleEvent(btn, event)
    end

    # Create screen-size button to close if clicked outside
    SkillTreeGUI.btnCloseOutside = UIUtil.CreateClickOutsideButton(SkillTreeGUI, SkillTreeGUI.closeButton.OnClick)

    # Update Tree Title
    function SkillTreeGUI.UpdateTreeTitle(self)
        self.title:SetText( LOC(' ') .. tostring(self.tree.points) )
    end

    # On Hide
    function SkillTreeGUI.Hide(self)
        # Kill the update thread
        if self.UpdateThread then
            KillThread(self.UpdateThread)
            self.UpdateThread = nil
        end

        # Release the selection window
        #InfoPanel.ReleasePopup()

        # Remove the escape handler
        UIMain.RemoveEscapeHandler(SkillTreeGUI.EscapeHandler)

        # Hide the skilltree GUI
        Group.Hide(self)

        # If the ministats were up, reshow them
        #if InGameUI.miniHero.miniUp then
            #InGameUI.miniHero:Show()
        #end
    end

    # On Show
    function SkillTreeGUI.Show(self)
        # Hide any other UI windows that are open
        CharWindow.CloseCharacterScreen()
        #InfoPanel.HidePopup()
        Shop.CloseShop()
        Scoreboard.CloseScoreboard()
        AchievementShop.CloseShop()
        Citadel.CloseCitadelScreen()
        #InGameUI.miniHero:Hide()

        # Start the update thread
        self.UpdateThread = ForkThread(self.tree.UpdateTree, self.tree)

        # Add the escape handler
        UIMain.AddEscapeHandler(SkillTreeGUI.EscapeHandler, UIUtil.ESCPRI_SkillTree)

        # Show the Skill tree GUI
        Group.Show(self)
    end

    # Escape Handler
    function SkillTreeGUI.EscapeHandler()
        if SkillTreeGUI then
            SkillTreeGUI:Hide()
        end
    end

    SkillTreeGUI:Hide()
    return SkillTreeGUI

end


function CreateButton(parent)

    local button = UIUtil.CreateButton(parent,
        '/buttons/main_btn_skills_up.dds',
        '/buttons/main_btn_skills_up.dds',
        '/buttons/main_btn_skills_up.dds',
        '/buttons/main_btn_skills_up.dds')
    button.Width:Set(64)
    button.Height:Set(44)
    #button.Depth:Set(12000)
    LayoutHelpers.DepthOverParent(button, parent, 10)
    button:SetAlpha(0)
    button:UseAlphaHitTest(true)

    button.pointsbg = Bitmap(button, UIUtil.UIFile('/buttons/main_btn_skills_pointsbg.dds'))
    button.pointsbg.Width:Set(64)
    button.pointsbg.Height:Set(44)
    LayoutHelpers.AtCenterIn(button.pointsbg, button)
    button.pointsbg:SetAlpha(0)
    LayoutHelpers.DepthOverParent(button.pointsbg, button, 10)
    button.pointsbg:DisableHitTest(true)

    button.plus = Bitmap(button.pointsbg, UIUtil.UIFile('/buttons/main_btn_skills_plus.dds'))
    button.plus.Width:Set(32)
    button.plus.Height:Set(32)
    LayoutHelpers.AtCenterIn(button.plus, button.pointsbg, 3, -5)
    button.plus:SetAlpha(0)
    LayoutHelpers.DepthOverParent(button.plus, button.pointsbg, 10)
    button.plus:DisableHitTest(true)

    button.icon = Bitmap(button, UIUtil.UIFile('/buttons/icon_skills_over.dds'))
    button.icon.Width:Set(100)
    button.icon.Height:Set(66)
    LayoutHelpers.AtCenterIn(button.icon, button, 5, -5)
    button.icon:SetAlpha(0)
    LayoutHelpers.DepthOverParent(button.icon, button, 10)
    button.icon:DisableHitTest(true)

    button.points = UIUtil.CreateText(button, '', 22, 'Arial Bold')
    LayoutHelpers.AtCenterIn(button.points, button, 4, -4)
    button.points:SetColor('ff4d4a34')
    LayoutHelpers.DepthOverParent(button.points, button, 10)
    button.points:DisableHitTest(true)

	button.mRolloverCue = DefaultOnEnterCue

    #button.mClickCue = DefaultOnActivateCue

	#Tooltip.AddButtonTooltip(button, 'button_character_skills')

	if parent:IsHidden() then
		button:Hide()
	end

    button.HandleEvent = function(self, event)
        if event.Type == 'MouseEnter' then
        	PlaySound( 'Forge/UI/Hud/snd_ui_hud_generic_mouseover' )
            EffectHelpers.FadeIn(button.icon, 0.1, 0, 0.7)
            button.tooltip = Tooltip.CreateGenericTooltip(button, 'button_character_skills', true)
        elseif event.Type == 'MouseExit' then
            EffectHelpers.FadeOut(button.icon, 0.35, 0.7, 0)
            if button.tooltip then
                button.tooltip:Destroy()
            end
        end
        return Button.HandleEvent(self, event)
    end

    function button.OnClick(self, modifiers)
        #if GetFocusArmy() != -1 then
        if self.hero then
            if SkillTreeGUI:IsHidden() then
                SkillTreeGUI:Show()
                # Play Sound when OPENING skill tree
                PlaySound( 'Forge/UI/snd_ui_generic_open' )    
            else
                # Play Sound when CLOSING skill tree
                PlaySound( 'Forge/UI/snd_ui_generic_close' ) 
                SkillTreeGUI:Hide()             
            end
        end
	end

    function button.GetHero(self)
        #if not self.hero or self.hero != (InGameUI.GetHeroInteraction()).SelectedHero then
        if not self.hero or self.hero != InGameUI.GetFocusArmyHero() then
            #local inf = InGameUI.GetHeroInteraction()
            #self.hero = inf.SelectedHero
            self.hero = InGameUI.GetFocusArmyHero()
            
            if self.hero then
                savedHero = self.hero
                savedHeroTree = self.hero:GetBlueprint().Abilities.Tree
                if not SkillTreeGUI.tree then
                    CreateTree()
                end
            end
        else
            return
        end
    end

	function button.Update(self)
	    if self.hero and self.hero:IsDead() and not IsDestroyed(SkillTreeGUI) then
	        if points then points = 0 end
	        if pulseThread then
	            KillThread(pulseThread)
	            pulseThread = false
	            button.pointsbg:SetAlpha(0)
	            button.plus:SetAlpha(0)
	            button.points:SetText('')
	        end
	        return
	    end

	    if GetFocusArmy() == -1 or not self.hero or IsDestroyed(self.hero) then
            if pulseThread then
                KillThread(pulseThread)
            end
	        return
	    elseif self.hero then
	        syncData = Common.GetSyncData(self.hero)
	        if points == syncData.SkillPoints then
	            return
	        end
	    end

	    points = syncData.SkillPoints

        if not IsDestroyed(parent) then
    	    if (not SkillTreeGUI.tree or SkillTreeGUI:IsHidden()) and points > 0 then
    	        if not pulseThread then
    	            pulseThread = ForkThread(PulseIcon, button)
    	            button.pointsbg:SetAlpha(1)
    	            button.plus:SetAlpha(1)
    	        end
    	    elseif points == 0 then
    	        if pulseThread then
    	            KillThread(pulseThread)
    	            pulseThread = false
    	            button.pointsbg:SetAlpha(0)
    	            button.plus:SetAlpha(0)
    	            button.points:SetText('')
    	        end
    	    end
    	end

	    if SkillTreeGUI.tree then
			SkillTreeGUI.tree:UpdateTree()
		end
	end

	import('/lua/ui/game/gameMain.lua').BeatCallback:Add(button.Update, button)
	import('/lua/ui/game/gameMain.lua').BeatCallback:Add(button.GetHero, button)

    SkillTreeButton = button
	return button
end

