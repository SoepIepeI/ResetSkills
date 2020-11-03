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
    SkillTreeGUI.tree:resetSkills()
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

### Tree: Reset skills
function tree.resetSkills(self)
    if isReplay then
        return
    end
       
    if SkillTreeButton.hero and not SkillTreeButton.hero:IsDead() then
        SkillTreeButton.hero:ResetSkillPoints()
    end
end