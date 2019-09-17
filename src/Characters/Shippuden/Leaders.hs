{-# LANGUAGE OverloadedLists #-}
{-# OPTIONS_HADDOCK hide     #-}

module Characters.Shippuden.Leaders (cs) where

import Characters.Base

import qualified Model.Skill as Skill

cs :: [Category -> Character]
cs =
  [ Character
    "Tsunade"
    "Tsunade has become the fifth Hokage. Knowing the Hidden Leaf Village's fate depends on her, she holds nothing back. Even if one of her allies is on the verge of dying, she can keep them alive long enough for her healing to get them back on their feet."
    [ [ Skill.new
        { Skill.name      = "Heaven Spear Kick"
        , Skill.desc      = "Tsunade spears an enemy with her foot, dealing 20 piercing damage to them. If an ally is affected by [Healing Wave], their health cannot drop below 1 next turn. Spends a Seal if available to deal 20 additional damage and demolish the target's destructible defense and Tsunade's destructible barrier."
        , Skill.classes   = [Physical, Melee]
        , Skill.cost      = [Tai]
        , Skill.effects   =
          [ To Enemy do
                has <- userHas "Strength of One Hundred Seal"
                when has demolishAll
                pierce (20 + if has then 20 else 0)
          , To Allies $ whenM (targetHas "Healing Wave") $ apply 1 [Endure]
          , To Self do
              remove "Strength of One Hundred Seal"
              vary "Strength of One Hundred Seal" baseVariant
          ]
        }
      ]
    , [ Skill.new
        { Skill.name      = "Healing Wave"
        , Skill.desc      = "Tsunade pours chakra into an ally, restoring 30 health to them immediately and 10 health each turn for 2 turns. Spends a Seal if available to restore 10 additional health immediately and last 3 turns."
        , Skill.classes   = [Chakra, Unremovable]
        , Skill.cost      = [Nin, Rand]
        , Skill.cooldown  = 1
        , Skill.effects   =
          [ To XAlly do
                has <- userHas "Strength of One Hundred Seal"
                heal (20 + if has then 10 else 0)
                apply (if has then (-3) else (-2)) [Heal 10]
          , To Self do
                remove "Strength of One Hundred Seal"
                vary "Strength of One Hundred Seal" baseVariant
          ]
        }
      ]
    , [ Skill.new
        { Skill.name      = "Strength of One Hundred Seal"
        , Skill.desc      = "Tsunade activates her chakra-storing Seal, restoring 25 health and empowering her next skill. Spends a Seal if available to instead restore 50 health to Tsunade and gain 2 random chakra."
        , Skill.classes   = [Chakra]
        , Skill.cost      = [Rand]
        , Skill.cooldown  = 3
        , Skill.effects   =
          [ To Self do
                heal 25
                tag 0
                vary "Strength of One Hundred Seal"
                     "Strength of One Hundred Seal"
          ]
        }
      , Skill.new
        { Skill.name      = "Strength of One Hundred Seal"
        , Skill.desc      = "Tsunade activates her chakra-storing Seal, restoring 25 health and empowering her next skill. Spends a Seal if available to instead restore 50 health to Tsunade and gain 2 random chakra."
        , Skill.classes   = [Chakra]
        , Skill.cost      = [Rand]
        , Skill.cooldown  = 3
        , Skill.effects   =
          [ To Self do
                heal 50
                gain [Rand, Rand]
                vary "Strength of One Hundred Seal" baseVariant
                remove "Strength of One Hundred Seal"
          ]
        }
      ]
    , [ invuln "Block" "Tsunade" [Physical] ]
    ]
  , Character
    "Ōnoki"
    "The third Tsuchikage of the Hidden Rock Village, Onoki is the oldest and most stubborn Kage. His remarkable ability to control matter on an atomic scale rapidly grows in strength until it can wipe out a foe in a single attack."
    [ [ Skill.new
        { Skill.name      = "Earth Golem"
        , Skill.desc      = "A golem of rock emerges from the ground, providing 10 permanent destructible defense to his team and dealing 10 damage to all enemies."
        , Skill.classes   = [Chakra, Physical, Melee]
        , Skill.cost      = [Nin]
        , Skill.cooldown  = 1
        , Skill.effects   =
          [ To Allies  $ defend 0 10
          , To Enemies $ damage 10
          ]
        }
      ]
    , [ Skill.new
        { Skill.name      = "Lightened Boulder"
        , Skill.desc      = "Ōnoki negates the gravity of an ally, providing 10 points of damage reduction to them for 2 turns. While active, the target cannot be countered or reflected."
        , Skill.classes   = [Physical, Melee]
        , Skill.cost      = [Rand]
        , Skill.cooldown  = 1
        , Skill.effects   =
          [ To XAlly $ apply 2 [Reduce All Flat 10, AntiCounter] ]
        }
      ]
    , [ Skill.new
        { Skill.name      = "Atomic Dismantling"
        , Skill.desc      = "The atomic bonds within an enemy shatter, dealing 20 piercing damage to them and permanently increasing the damage of this skill by 10."
        , Skill.classes   = [Chakra, Ranged]
        , Skill.cost      = [Nin]
        , Skill.effects   =
          [ To Enemy do
                stacks <- userStacks "Atomic Dismantling"
                pierce (20 + 10 * stacks)
          , To Self addStack
          ]
        }
      ]
    , [ invuln "Flight" "Ōnoki" [Chakra] ]
    ]
  , Character
    "Mei Terumi"
    "The third Mizukage of the Hidden Mist Village, Mei works tirelessly to help her village overcome its dark history and become a place of kindness and prosperity. Her corrosive attacks eat away at the defenses of her enemies."
    [ [ Skill.new
        { Skill.name      = "Solid Fog"
        , Skill.desc      = "Mei exhales a cloud of acid mist that deals 15 affliction damage to an enemy for 3 turns."
        , Skill.classes   = [Bane, Chakra, Ranged]
        , Skill.cost      = [Blood]
        , Skill.cooldown  = 3
        , Skill.effects   =
          [ To Enemy $ apply 3 [Afflict 15] ]
        }
      ]
    , [ Skill.new
        { Skill.name      = "Water Bomb"
        , Skill.desc      = "Water floods the battlefield, dealing 20 piercing damage to all enemies and preventing them from reducing damage or becoming invulnerable for 1 turn."
        , Skill.classes   = [Chakra, Ranged]
        , Skill.cost      = [Nin, Rand]
        , Skill.cooldown  = 1
        , Skill.effects   =
          [ To Enemies do
                pierce 20
                apply 1 [Expose]
          ]
        }
      ]
    , [ Skill.new
        { Skill.name      = "Lava Monster"
        , Skill.desc      = "Mei spits a stream of hot lava, dealing 10 affliction damage to all enemies and removing 20 destructible defense from them for 3 turns."
        , Skill.classes   = [Bane, Chakra, Ranged]
        , Skill.cost      = [Blood, Rand]
        , Skill.cooldown  = 3
        , Skill.dur       = Action 3
        , Skill.effects   =
          [ To Enemies do
              demolish 20
              afflict 10
          ]
        }
      ]
    , [ invuln "Flee" "Mei" [Physical] ]
    ]
  ]