function removeAllSkills(unit)
    print("removeAllSkills")
    print(unit.Sync.Skills)
    unit.Sync.Skills = {}
    return
end