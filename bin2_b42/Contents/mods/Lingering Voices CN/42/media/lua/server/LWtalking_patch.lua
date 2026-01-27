-- Lingering Voices CN Patch
-- Override global variables with getText() for Chinese translation

local function patchLingeringVoicesCN()

    lungeLines = { zombieLine:new("%s", {
        getText("Sandbox_LW_lunge_1"),
        getText("Sandbox_LW_lunge_2"),
        getText("Sandbox_LW_lunge_3"),
        getText("Sandbox_LW_lunge_4"),
        getText("Sandbox_LW_lunge_5"),
        getText("Sandbox_LW_lunge_6"),
        getText("Sandbox_LW_lunge_7"),
        getText("Sandbox_LW_lunge_8"),
        getText("Sandbox_LW_lunge_9"),
        getText("Sandbox_LW_lunge_10"),
        getText("Sandbox_LW_lunge_11"),
        getText("Sandbox_LW_lunge_12"),
        getText("Sandbox_LW_lunge_13"),
    })}

    staggerLines = { zombieLine:new("%s", {
        getText("Sandbox_LW_stagger_1"),
        getText("Sandbox_LW_stagger_2"),
        getText("Sandbox_LW_stagger_3"),
        getText("Sandbox_LW_stagger_4"),
        getText("Sandbox_LW_stagger_5"),
        getText("Sandbox_LW_stagger_6"),
        getText("Sandbox_LW_stagger_7"),
        getText("Sandbox_LW_stagger_8"),
        getText("Sandbox_LW_stagger_9"),
        getText("Sandbox_LW_stagger_10"),
        getText("Sandbox_LW_stagger_11"),
        getText("Sandbox_LW_stagger_12"),
        getText("Sandbox_LW_stagger_13"),
        getText("Sandbox_LW_stagger_14"),
        getText("Sandbox_LW_stagger_15"),
        getText("Sandbox_LW_stagger_16"),
        getText("Sandbox_LW_stagger_17"),
        getText("Sandbox_LW_stagger_18"),
        getText("Sandbox_LW_stagger_19"),
        getText("Sandbox_LW_stagger_20"),
        getText("Sandbox_LW_stagger_21"),
        getText("Sandbox_LW_stagger_22"),
        getText("Sandbox_LW_stagger_23"),
        getText("Sandbox_LW_stagger_24"),
        getText("Sandbox_LW_stagger_25"),
        getText("Sandbox_LW_stagger_26"),
        getText("Sandbox_LW_stagger_27"),
        getText("Sandbox_LW_stagger_28"),
        getText("Sandbox_LW_stagger_29"),
        getText("Sandbox_LW_stagger_30"),
        getText("Sandbox_LW_stagger_31"),
        getText("Sandbox_LW_stagger_32"),
    })}

    fakeDeadLines = { zombieLine:new("%s", {
        getText("Sandbox_LW_fakeDead_1"),
        getText("Sandbox_LW_fakeDead_2"),
        getText("Sandbox_LW_fakeDead_3"),
        getText("Sandbox_LW_fakeDead_4"),
        getText("Sandbox_LW_fakeDead_5"),
        getText("Sandbox_LW_fakeDead_6"),
        getText("Sandbox_LW_fakeDead_7"),
        getText("Sandbox_LW_fakeDead_8"),
    })}

    thumpingLines = { zombieLine:new("%s", {
        getText("Sandbox_LW_thumping_1"),
        getText("Sandbox_LW_thumping_2"),
        getText("Sandbox_LW_thumping_3"),
        getText("Sandbox_LW_thumping_4"),
        getText("Sandbox_LW_thumping_5"),
        getText("Sandbox_LW_thumping_6"),
        getText("Sandbox_LW_thumping_7"),
        getText("Sandbox_LW_thumping_8"),
        getText("Sandbox_LW_thumping_9"),
        getText("Sandbox_LW_thumping_10"),
    })}

    attackLines = { zombieLine:new("%s", {
        getText("Sandbox_LW_attack_1"),
        getText("Sandbox_LW_attack_2"),
        getText("Sandbox_LW_attack_3"),
        getText("Sandbox_LW_attack_4"),
        getText("Sandbox_LW_attack_5"),
        getText("Sandbox_LW_attack_6"),
        getText("Sandbox_LW_attack_7"),
        getText("Sandbox_LW_attack_8"),
        getText("Sandbox_LW_attack_9"),
        getText("Sandbox_LW_attack_10"),
        getText("Sandbox_LW_attack_11"),
        getText("Sandbox_LW_attack_12"),
        getText("Sandbox_LW_attack_13"),
        getText("Sandbox_LW_attack_14"),
        getText("Sandbox_LW_attack_15"),
        getText("Sandbox_LW_attack_16"),
        getText("Sandbox_LW_attack_17"),
        getText("Sandbox_LW_attack_18"),
        getText("Sandbox_LW_attack_19"),
        getText("Sandbox_LW_attack_20"),
    })}

    print("[Lingering Voices CN] Chinese patch loaded!")
end

patchLingeringVoicesCN()
