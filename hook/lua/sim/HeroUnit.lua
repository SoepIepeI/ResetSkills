local CharacterUnit = import('/lua/sim/CharacterUnit.lua').CharacterUnit
local Buff = import('/lua/sim/buff.lua')
local AM = import('/lua/sim/ability.lua')
local Skill = import('/lua/sim/skill.lua')
local Inventory = import('/lua/sim/Inventory.lua').Inventory
local Game = import('/lua/game.lua')
local Entity = import('/lua/sim/entity.lua').Entity

HeroUnit = Class(CharacterUnit) {

    ClassCallbacks = {
        OnLevel = Callback(),
        OnStopBeingBuilt = Callback(),
    },

    OnStopBeingBuilt = function(self, builder, layer)
        CharacterUnit.OnStopBeingBuilt(self, builder, layer)

        local bp = self:GetBlueprint()

        self.Sync.HeroLevel = 1
        self.Sync.XP = 0
        self.Sync.ThisLevelXP = 0
        self.Sync.NextLevelXP = self:GetExperienceTable()[2].Amount
        self.Sync.SkillPoints = 1
        self.Sync.Bounty = 0
        self.Sync.DamageRange = 0
        self.Sync.PrimaryWeaponDamage = 0
        self.Sync.ShopId = false
        self.Sync.AvatarState = 1

        local wep = self:GetWeapon(1)
        local dam = wep:GetBaseDamage()
        if wep then
            self.Sync.PrimaryWeaponDamage = dam
            self.Sync.Range = wep:GetMaxRadius()
            self.Sync.AttackTime = 1 / wep:GetBlueprint().RateOfFire
        end

        self:InitStats()
        
        if self:GetAIBrain().BrainController == 'AI' then
            self:ApplyAIBuffs()
        end
        
        self.Sync.MovementSpeed = self:GetBlueprint().Physics.MaxSpeed

        # Table of minions to help the hero find his boys faster
        self.Minions = {}
        self.MinionCounts = {
            Soldiers = 0,
            Archers = 0,
            Priests = 0,
            Special = 0,
        }
        self.Sync.MinionCounts = table.copy(self.MinionCounts)

        self:SetupInventory()

        # Reference to my brains score table
        self.Score = ArmyBrains[self:GetArmy()].Score
        self.Score.HeroId = bp.BlueprintId

        # Add Hero based callbacks
        self.Callbacks.OnLevel = Callback()
        self.Callbacks.OnInventoryAdded = Callback()
        self.Callbacks.OnInventoryRemoved = Callback()

        self:GetAIBrain():ResetHeroKillStreak()

        HeroUnit.ClassCallbacks.OnStopBeingBuilt:Call(self, builder, layer)
    end,

    OnDestroy = function(self)
        self:DestroyMinions()
        CharacterUnit.OnDestroy(self)
    end,

    OnKilled = function(self)
        self:KillMinions()

        CharacterUnit.OnKilled(self)

        if self.NoDeathScore then
            return
        end
        self.Score.HeroDeaths = self.Score.HeroDeaths + 1
    end,

    DeathThread = function(self,overkillRatio,instigator)
		# Remove being frozen here, temporarily hacked in here to make sure we dont leave frozen units on death

        if not self.IsFrozen then
		    local anim = self.Character:PlayDie()
		    
		    local animDuration = 0
		    if anim then
                animDuration = anim:GetDuration()
            end

            # Spawn loot always at 3 seconds or sooner if the death animation is quicker
            if animDuration > 3.0 then
                WaitSeconds(3)
                self:SpawnLoot()
                WaitSeconds(animDuration-3)
            else
                WaitSeconds(animDuration)
                self:SpawnLoot()
            end

            self:PlayUnitSound('Destroyed')

            local blueprint = self:GetBlueprint()
            local slide = true

            if blueprint then
                if blueprint.General.CorpseDecayTime then
			        local decayTime = (blueprint.General.CorpseDecayTime * GameData.CorpseDecayMult) or 0
			        WaitSeconds(decayTime)
                end
                if blueprint.General.IgnoreDeathSlider then
                    slide = false
                end
		    end

            if slide then
		        local slider = CreateSlider(self,-1,0.0,-4.0,0.0,1)
		        self.Trash:Add(slider)
		        WaitFor(slider)
            end
        else
            self:CreateFrozenShatterEffects()
        end

        self:Destroy()
    end,
    
    -- Applies AI HP buffs based on lobby options
    ApplyAIBuffs = function(self)
        if ScenarioInfo.Options.AiHitpoints and ScenarioInfo.Options.AiHitpoints != 'Normal' then
            #LOG('*DEBUG: Applying AI HP Buff: X'..Game.GameData.AIHpMultiplier[ScenarioInfo.Options.AiHitpoints])
            BuffBlueprint {
                Name = 'AI HP Modifier',
                DisplayName = 'AIHpModifier',
                BuffType = 'AIHPMODIFIER',
                Debuff = false,
                Stacks = 'ALWAYS',
                Duration = -1,
                Affects = {
                    MaxHealth = {Add = Game.GameData.AIHpMultiplier[ScenarioInfo.Options.AiHitpoints], AdjustHealth = true},
                },
            }
            Buff.ApplyBuff(self, 'AI HP Modifier')
        end
    end,

    InitStats = function(self)
        local buffName = self:GetUnitId() .. 'InitialStats'
        local bpStats = self:GetBlueprint().Stats

        if not Buffs[buffName] then
            BuffBlueprint {
                Name = self:GetUnitId() .. 'InitialStats',
                DisplayName = 'InitialStats',
                BuffType = 'INITIALSTATS',
                Debuff = false,
                Stacks = 'ALWAYS',
                Duration = -1,
                Affects = {
                    MaxHealth = {Add = bpStats.MaxHealth, AdjustHealth = true},
                    Regen = {Add = bpStats.Regen},
                    RateOfFire = {Add = bpStats.RateOfFire},
                    Armor = {Add = bpStats.Armor},
                    MaxEnergy = {Add = bpStats.MaxEnergy, AdjustEnergy = true},
                    EnergyRegen = {Add = bpStats.EnergyRegen},
                    DamageRating = {Add = bpStats.DamageRating},
                },
            }
        end
        Buff.ApplyBuff(self, buffName)

        # Set our initial health and energy
        self:AdjustHealth( bpStats.MaxHealth )
        self:SetEnergy( bpStats.MaxEnergy )
    end,

    Respawn = function(self,data)
        #LOG('RESPAWN: ', self:GetUnitId())
        #LOG('data = ', repr(data))

        # Re-level up.
        self.Sync.HeroLevel = 1
        while self.Sync.HeroLevel < data.HeroLevel do
            self:LevelUp(true)
        end
        self.Sync.XP = data.XP
        self.Sync.ThisLevelXP = data.ThisLevelXP
        self.Sync.SkillPoints = data.SkillPoints

        if data.Skills then
            for k, skill in data.Skills do
                Skill.AddSkill(self,skill,true)
            end
        end

        if not self.Inventory or table.empty(self.Inventory) then
            WARN('Inventory not setup correctly on hero; Running setup again')
            self:SetupInventory()
        end

        if data.Items then
            for invName,inv in data.Items do
                for k,item in inv do
                    if item:BeenDestroyed() then
                        WARN('*ITEM DESTROYED BEFORE RESPAWN')
                        continue
                    end
                    item:GiveTo(self)
                end
            end
        end

        # Adjust health and energy back up to max
        self:AdjustHealth( self:GetMaxHealth() )
        self:SetEnergy( self:GetMaxEnergy() )
    end,

    ChangeStat = function(self, stat, num)
        if not num then return end
        if not stat then return end

        if num > 0 then
            Buff.ApplyBuff(self, self:GetBlueprint().Stats.Primary .. 'Hero' .. stat .. 'Stat', nil, num )
            #LOG('*DEBUG: Syncing stats table for ' .. stat .. ', value = ', repr(self.Sync.Stats[stat]))
        elseif num < 0 then
            Buff.RemoveBuff(self, self:GetBlueprint().Stats.Primary .. 'Hero' .. stat .. 'Stat', nil, num )
        end
        self.Stats[stat] = self.Stats[stat] + num
        self.Sync[stat] = self.Sync[stat] + num
    end,

    GainExperience = function(self, amount)
        local handicap = Game.GameData.GameHandicap[ ArmyBrains[ self:GetArmy() ].Name .. 'ExpMultiplier' ] or  Game.GameData.GameHandicap[ ArmyBrains[ self:GetArmy() ]:GetTeamArmy().Name .. 'ExpMultiplier' ] or 1
        local xpMult = Game.GameData.ExperienceMultiplier[ ScenarioInfo.Options.ExperienceRate or 'Normal' ]
        amount = amount * handicap * xpMult
        amount = amount * (self.ExperienceMod or 1)

        if(ScenarioInfo.Options.TournamentMode) then
            if(not ScenarioInfo.HumanIndex) then
                # Find the human army so we can check if were friends with them
                for k, v in ScenarioInfo.ArmySetup do
                    if(v.Human) then
                        ScenarioInfo.HumanIndex = v.ArmyIndex
                        break
                    end
                end
            end
            if(ScenarioInfo.HumanIndex) then
                if(IsAlly(self.Army, ScenarioInfo.HumanIndex)) then
                    local spXPMult = Game.GameData.SPExperienceMult[ScenarioInfo.ArmySetup[ArmyBrains[ScenarioInfo.HumanIndex].Name].Difficulty] or 1
                    amount = amount * spXPMult
                end
            end
        end

        if amount < 0 then
            error("*ERROR: We don\'t currently support negative experience gains.")
            return
        end

        local xp = self.Sync.XP
        xp = math.floor(xp + amount)
        self.Sync.XP = xp

#        if self:GetArmy() == GetFocusArmy() and amount > 0 then
#            FloatTextOn(self, "+"..math.floor(amount), 'Experience')
#        end

        #LOG('*XP: Hero gained experience! XP Gained: ', repr(amount), ' Total XP: ', repr(xp))
        self:CheckLevel()

    end,

    GetDamageRating = function(self)
        return self.Sync.DamageRating
    end,

    SpawnLoot = function(self)
        local lt = self:GetLootTable()
        local lvl = self.Sync.HeroLevel
        if lt[lvl] and lt[lvl].Loot then
            CreateLoot(lt[lvl].Loot, table.copy(self:GetPosition()), self)
        end
    end,

    GetLootTable = function(self)
        return self:GetBlueprint().Experience.Loot or GameData.DefaultLoot
    end,

    # This function checks to see if the hero can level up based on
    # the current amount of XP; Calculates how many levels to gain
    CheckLevel = function(self)
        local xpTable = self:GetExperienceTable()
        local xp = self.Sync.XP
        local lvl = self.Sync.HeroLevel
        local numLevels = 0

        if lvl < table.getn(xpTable) then
            # Calculate the number of levels to gain
            while numLevels + lvl < table.getn(xpTable) do
                # If we have more xp than the next level, hooray!
                if xp >= xpTable[numLevels + lvl + 1].Amount then
                    numLevels = numLevels + 1
                # Leave; we don't have enough for next level
                else
                    break
                end
            end

            # Leave if we aren't gaining any levels
            if numLevels == 0 then
                return
            end

            # Level up for each level; The final level is not quiet (Plays sound and effects)
            for i=1,numLevels do
                local quiet = not (i == numLevels)
                self:LevelUp(quiet)
            end
        end
    end,


    ResetSkillPoints = function(self)
        print("skillResetButton ResetSkillPoints")
        #LOG('ROBIN: ', "skillResetButton ResetSkillPoints")
        PlaySound('Forge/UI/Hud/snd_ui_skilltree_click')
        self.Sync.SkillPoints = 20
        self.Sync.Skills = {}
    end,

    # This function figures out how many levels the hero should gain based on current exp
    # This function is ONLY called when the hero has enough to level
    LevelUp = function(self, quiet)
        local xpTable = self:GetExperienceTable()
        local maxLevel = table.getn(xpTable)
        local level = self.Sync.HeroLevel + 1

        # If we are already at maximum level; leave
        if level > maxLevel then
            return
        end

        # Apply level up buffs
        local bpxp = self:GetBlueprint().Experience
        if bpxp.LevelUpBuffs then
            for k, bf in bpxp.LevelUpBuffs do
                Buff.ApplyBuff(self, bf, self)
            end
        end

        # Send data to the sync table
        self.Sync.HeroLevel = level
        self.Score.HeroLevel = level

        # if this function is called and we have less xp than the next levle;
        local xp4lvl = xpTable[level].Amount
        #LOG('*XP: Hero Leveled! Level: ', repr(level), ' XP:', repr(self.Sync.XP), ' Buff: ', repr(xptbl.Buff))
        if self.Sync.XP < xp4lvl then
            self.Sync.XP = xp4lvl
        end

        self.Sync.ThisLevelXP = xp4lvl

        if level < maxLevel then
            self.Sync.NextLevelXP = xpTable[level+1].Amount
        end

        self.Sync.SkillPoints = self.Sync.SkillPoints + 1

        if not quiet then
            if not self.IsInvisible then
                CreateTemplatedEffectAtPos( 'Common', 'Levelup', self:GetEffectBuffClassification(), self:GetArmy(), self:GetPosition() )
            end
            local pos = table.copy(self:GetPosition())
            pos[2] = pos[2] + ( self:GetBlueprint().SizeY * 1.3 )
            FloatTextAt(pos, LOCF("<LOC floattext_0009>Level %d!", level), 'LevelUp', self:GetArmy() )
            self:PlayUnitSound('OnLevelUp')
        end

        if self:GetArmy() == GetFocusArmy() then
            SetAudioParameter('LEVEL', level);
        end

        self.Callbacks.OnLevel:Call(self, level)
        HeroUnit.ClassCallbacks.OnLevel:Call(self, level)
    end,

    GetGold = function(agent)
        #Get the agents army gold
        local gold = GetArmyBrain(agent:GetArmy()).mGold
        return gold
    end,

    GetLevel = function(self)
        return self.Sync.HeroLevel
    end,

    GetExperienceTable = function(self)
        return self:GetBlueprint().Experience.Levels or GameData.DefaultHeroExp
    end,

    AddMinion = function(self, unit)
        table.insert( self.Minions, unit )

        if EntityCategoryContains( categories.MINOCAPTAIN, unit ) then
            self.MinionCounts.Soldiers = self.MinionCounts.Soldiers + 1
        elseif EntityCategoryContains( categories.SIEGEARCHER, unit ) then
            self.MinionCounts.Archers = self.MinionCounts.Archers + 1
        elseif EntityCategoryContains( categories.HIGHPRIEST, unit ) then
            self.MinionCounts.Priests = self.MinionCounts.Priests + 1
        else
            self.MinionCounts.Special = self.MinionCounts.Special + 1
        end

        self.Sync.MinionCounts = table.copy(self.MinionCounts)
    end,

    RemoveMinion = function(self, unit)
        if unit.RemoveCounted then
            return
        end
        unit.RemoveCounted = true
        if EntityCategoryContains( categories.MINOCAPTAIN, unit ) then
            self.MinionCounts.Soldiers = self.MinionCounts.Soldiers - 1
        elseif EntityCategoryContains( categories.SIEGEARCHER, unit ) then
            self.MinionCounts.Archers = self.MinionCounts.Archers - 1
        elseif EntityCategoryContains( categories.HIGHPRIEST, unit ) then
            self.MinionCounts.Priests = self.MinionCounts.Priests - 1
        else
            self.MinionCounts.Special = self.MinionCounts.Special - 1
        end

        self.Sync.MinionCounts = table.copy(self.MinionCounts)
    end,

    DestroyMinions = function(self, category)
        category = category or categories.MINION
        
        # If I have minions, kill them
        local brain = self:GetAIBrain()
        if(not brain.Conquest.IsTeamArmy and not brain.Conquest.IsNeutralArmy) then
            local minions = brain:GetListOfUnits(category, false)
            for k, v in minions do
                if v:BeenDestroyed() then
                    continue
                end
                v:Destroy()
            end
        end

        for k,v in self.Minions do
            if v:BeenDestroyed() then
                continue
            end
            
            if not EntityCategoryContains(category, v) then
                continue
            end

            v:Destroy()
        end
    end,

    KillMinions = function(self, category)
        category = category or categories.MINION

        # If I have minions, kill them
        local brain = self:GetAIBrain()
        if(not brain.Conquest.IsTeamArmy and not brain.Conquest.IsNeutralArmy) then
            local minions = brain:GetListOfUnits(category, false)
            for k, v in minions do
                if v:IsDead() then
                    continue
                end

                v.KillData = self.KillData
                v:KillSelf()
            end
        end

        for k,v in self.Minions do
            if v:IsDead() then
                continue
            end

            if not EntityCategoryContains(category, v) then
                continue
            end

            v.KillData = self.KillData
            v:KillSelf()
        end
    end,

    SetupInventory = function(self)
        local bp = self:GetBlueprint()

        self.Inventory = {}
        if bp.Inventory then
            for invName,invSlots in bp.Inventory do
                self.Inventory[invName] = Inventory(self,invName,invSlots)
                self.Trash:Add(self.Inventory[invName])
            end
        end
    end,

    UpdateInventorySync = function(self)
        self.Sync.Inventory = {}
        for invName,inv in self.Inventory do
            self.Sync.Inventory[invName] = { NumSlots = inv.NumSlots, Slots = table.copy(inv.Slots) }
        end
    end,

    OnInventoryAdded = function(self,item)
        if item.Blueprint.Abilities then
            for k,abil in item.Blueprint.Abilities do
                AM.AddAbility(self,abil, true)
            end
        end
        self.Callbacks.OnInventoryAdded:Call(self, item)
    end,

    OnInventoryRemoved = function(self,item)
        # See if we should remove abilities. We only want to remove if there are no
        # other items in the inventory granting the same ability. Right now we just
        # check for other instances of the same item and rely on the rule that different
        # items cant grant the exact same ability. This rule could be changed with some
        # work.
        if item.Blueprint.Abilities then
            local counts = self.Inventory[item.Blueprint.InventoryType or 'Equipment']:GetCount(item.Blueprint.Name)
            local total = 0
            for k,info in counts do
                total = total + info.Count
            end

            if total == 0 then
                for k,abil in item.Blueprint.Abilities do
                    AM.RemoveAbility(self,abil)
                end
            end
        end
        self.Callbacks.OnInventoryRemoved:Call(self, item)
    end,

    SetInvisible = function( self, bEnable )
        if bEnable then
            self.IsInvisible = true
            # Destoy unit ambient effects
            self:DestroyAmbientEffects()

            # Remove any active ambient effects created by abilities
            if self.AbilityData then
                for k, v in self.AbilityData do
                     if v.ActiveEffectDestroyables then
                         v.ActiveEffectDestroyables:Destroy()
                     end
                end
            end

            # Disable the weapons ability to allow the AI to attack with them
            for i = 1, self.NumWeapons do
                local wep = self:GetWeapon(i)
                Buff.ApplyBuff(self, 'StayOnTarget', self)
            end

			# Tell the steering entity it is invisible
			self:SetSteeringInvisible()

            # Set visibility info
            self:SetVizToNeutrals('Never')
            self:SetVizToEnemies('Never')

            # Cloaking should handle this, however AI currently will attack a cloaked
            # unit if it has been seen once. This fixes that, however has the side affect
            # of being invisible to omni visibility.
            self:SetWeaponsDoNotTarget(true)
        else
            self.IsInvisible = false
            # Re-create ambient effects
            self:CreateAmbientEffects()

            # Re-enable any ability ambients for active non disabled abilities.
            local bp = self:GetBlueprint()
            for abilityName, AbilData in self.Sync.Abilities do
                if not AbilData.Disabled and not AbilData.Removed then
                    local def = Ability[abilityName]
                    if def.CreateAbilityAmbients then
                        def:CreateAbilityAmbients( self, self.AbilityData[abilityName].ActiveEffectDestroyables )
                    end
                end
            end

			# Tell the steering entity it is invisible
			self:SetSteeringVisible()

            # Renable weapon opportunity
            if Buff.HasBuff(self, 'StayOnTarget') then
                Buff.RemoveBuff(self, 'StayOnTarget', self)
                #Lets make sure that the last instance of the buff is removed
                if not Buff.HasBuff(self, 'StayOnTarget') then
                    for i = 1, self.NumWeapons do
                        local wep = self:GetWeapon(i)
                        wep:SetStayOnTarget(false)
                    end
                end
            end

            # Set visibility info
            self:SetVizToNeutrals('Intel')
            self:SetVizToEnemies('Intel')
            self:SetWeaponsDoNotTarget(false)
        end
    end,

    SetInvisibleMesh = function( self, bEnable )
        if self.Character then
            if bEnable then
                local meshBp = self.Character.CharBP.Meshes.Invisibility
                if meshBp then
                    self:AddEffectMeshState( 'Invisible', string.lower(meshBp), true, true )
                else
                    LOG( 'Warning: No invisible mesh bp definded for hero ' .. GetUnitId() )
                end
            else
                self:RemoveEffectMeshState( 'Invisible', true )
            end
        end
    end,
}

# -----------------------------------------------------------------------------
# Debug functions for heroes
# -----------------------------------------------------------------------------
_G.AddSkillPoints = function(num)
    local selection = __selected_units
    if table.empty(selection) then
        print("No units selected.")
    end
    for k,unit in selection do
        if unit.Sync.SkillPoints then
            unit.Sync.SkillPoints = unit.Sync.SkillPoints + num
        end
    end
end

_G.SetLevel = function(lvl)
    local selection = __selected_units
    if table.empty(selection) then
        print("No units selected.")
    end
    for k,unit in selection do
        if unit.LevelUp then
            while unit.Sync.HeroLevel < lvl do
                unit:LevelUp( (unit.Sync.HeroLevel != (lvl - 1) ) )
            end
        end
    end
end

_G.GiveAllSkills = function()
    local selection = __selected_units
    if table.empty(selection) then
        print("No units selected.")
    end
    for k,unit in selection do
        local bp = unit:GetBlueprint()
        if not bp.Abilities or not bp.Abilities.Tree or not bp.Abilities.Layout then
            return
        end
        local layout = import(bp.Abilities.Layout).Layout
        for row, tbl in layout do
            for key, skillName in tbl do
                if bp.Abilities.Tree[skillName] then
                    Skill.AddSkill(unit, skillName, true)
                end
            end
        end
        unit.Sync.SkillPoints = 0
    end
end

_G.GiveItem = function(item)
    local selection = __selected_units
    if table.empty(selection) then
        print("No units selected.")
        return
    end

    if not item then
        print("No item specified.")
        return
    end
    for k,unit in selection do
        if EntityCategoryContains(categories.HERO,unit) then
            local item = CreateCarriedItem(item, unit)
            if item:GiveTo(unit) then
                print('Gave hero a ', item)
            else
                print("Hero can't carry a ", item)
            end
            return
        end
    end
end

_G.Task = function()
    local selection = __selected_units
    if table.empty(selection) then
        print("No units selected.")
    end
    for k,unit in selection do
        if unit.GetCommandQueue then
            local q = unit:GetCommandQueue()
            local cmd = q:GetCurrentCommand()
            local type
            if cmd then
                type = cmd:GetType()
            else
                type = 'none'
            end
            LOG(unit:GetUnitId(), ' ', unit:GetEntityId(), ' has task:', type)
        end
    end
end

_G.Inventory = function()
    local selection = __selected_units
    if table.empty(selection) then
        print("No units selected.")
    end
    for k,unit in selection do
        if unit.Inventory then
            for invName,inv in unit.Inventory do
                LOG(unit:GetUnitId(), ' ', unit:GetEntityId(), ' Inventory:')
                LOG('Slots = ',repr(inv.Slots))
                LOG('Sync = ',repr(inv))
                LOG('Items = ')
                for k,slot in inv.Slots do
                    for i,id in slot do
                        local item = GetEntityById(id)
                        LOG('    ', id, ' = ', item.Sync.Name)
                    end
                end
            end
        end
    end
end

_G.SetHealth = function(hlth)
    local selection = __selected_units
    if table.empty(selection) then
        print("No units selected.")
    end
    for k, v in selection do
        v:SetHealth(hlth)
    end
end
