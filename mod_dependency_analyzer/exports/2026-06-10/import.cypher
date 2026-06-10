// =============================================
// Neo4j Cypher 导入脚本
// 由 import_workshop.py 自动生成
// 用法: cypher-shell -u neo4j -p password < import.cypher
// =============================================

// === Mod 节点 ===
MERGE (m:Mod {mod_id: "XantjiRecycleEverything_CN"}) SET m.name = "Xantji's Recycle Everything 中文补丁", m.version = "1.0.13", m.author = "bin^2", m.pz_version = "42.15", m.description = "Sincerely Xantji";
MERGE (m:Mod {mod_id: "EPR_B42_CN"}) SET m.name = "Extensive Power Rework B42 CN", m.version = "1.1.0", m.author = "bin^2", m.pz_version = "42.0.0", m.description = "Extensive Power Rework B42 中文补丁";
MERGE (m:Mod {mod_id: "Lingering Voices CN"}) SET m.name = "Lingering Voices CN", m.version = "1.1.0", m.author = "bin^2", m.pz_version = "42.13.1", m.description = "包括扑击、踉跄、假死、敲门和攻击时的台词，让中文玩家获得更好的游戏体验。";
MERGE (m:Mod {mod_id: "bin2_B42_13_1_Collection"}) SET m.name = "[Obsoleted]bin2的B42.13.1合集", m.version = "1.0.3", m.author = "bin^2", m.pz_version = "42.13.1", m.description = "bin2的B42.13.1合集 | 包含29个精选mod的组合，包括中文汉化、UI增强、建筑系统、食物扩展等。本modpack已为B42.13.1版本优化。";
MERGE (m:Mod {mod_id: "bin2_B42_13_Collection"}) SET m.name = "[Obsoleted]bin2的B42.13合集", m.version = "1.0.3", m.author = "bin^2", m.pz_version = "42.13", m.description = "bin2的B42.13合集 | 包含29个精选mod的组合，包括中文汉化、UI增强、建筑系统、食物扩展等。本modpack已为B42.13版本优化。";
MERGE (m:Mod {mod_id: "bin2_B42_14_1_Collection"}) SET m.name = "[Obsoleted]bin2的B42.14.1合集", m.version = "1.0.3", m.author = "bin^2", m.pz_version = "42.14.1", m.description = "bin2的B42.14.1合集 | 包含精选mod的组合，包括中文汉化、UI增强、建筑系统、食物扩展等。本modpack已为B42.14.1版本优化。";
MERGE (m:Mod {mod_id: "bin2_B42_Collection"}) SET m.name = "bin2的B42合集", m.version = "1.0.8", m.author = "bin^2", m.pz_version = "42.16.0", m.description = "bin2的B42合集 | 包含精选mod的组合，包括中文汉化、UI增强、建筑系统、食物扩展等。本modpack已为B42.15.0版本优化。";
MERGE (m:Mod {mod_id: "bin2_extension"}) SET m.name = "bin2扩展", m.version = "1.1.1", m.author = "bin^2", m.pz_version = "42.15.0", m.description = "bin2的扩展模组 - 添加各种便利配方";
MERGE (m:Mod {mod_id: "Project_Cook_Controller_Support"}) SET m.name = "Project Cook Controller Support", m.version = "1.0.0", m.author = "bin^2", m.pz_version = "42.13.1", m.description = "需要 Project Cook (Workshop ID: 3490188370)";
MERGE (m:Mod {mod_id: "EHR_CN"}) SET m.name = "Extensive Health Rework B42 CN", m.version = "1.1.4", m.author = "bin^2", m.pz_version = "42.15.0", m.description = "Extensive Health Rework B42 中文补丁";
MERGE (m:Mod {mod_id: "Respawn2"}) SET m.name = "Keep XP When Respawn 2", m.version = "", m.author = "", m.pz_version = "", m.description = "Respawn character with reduced perk level";
MERGE (m:Mod {mod_id: "NotTheEnd2"}) SET m.name = "Death Is Not The End 2", m.version = "", m.author = "", m.pz_version = "", m.description = "Retrieve XP from your corpse.";
MERGE (m:Mod {mod_id: "ERS_SmallProducersPack_CN"}) SET m.name = "ERS – Small Producers Pack 中文补丁", m.version = "1.0.1", m.author = "bin^2", m.pz_version = "42.15.0", m.description = "Early game compact energy producers compatible with ERS Framework.";
MERGE (m:Mod {mod_id: "EnergyRoutingSystem_CN"}) SET m.name = "ERS – Energy Routing System - CN", m.version = "1.5.0", m.author = "bin^2", m.pz_version = "42.13.0", m.description = "Advanced off-grid energy management system for Project Zomboid. Adds a server-authoritative Energy Routing Controller with real-time UI, solar panels, wind turbines, batteries, energy storage, consumption groups, priority modes, degradation, and maintenance-ready mechanics. Designed for realistic survival gameplay.";

// === Recipe 节点 ===
MERGE (r:Recipe {recipe_id: "Bin2DisassembleCrudeWoodenTongs"}) SET r.mod_id = "bin2_extension", r.syntax = "B42", r.time = 5, r.timed_action = "Making", r.category = "Cooking", r.tags = "InHandCraft;CanBeDoneFromFloor";
MERGE (r:Recipe {recipe_id: "Bin2DisassembleSplint"}) SET r.mod_id = "bin2_extension", r.syntax = "B42", r.time = 5, r.timed_action = "Making", r.category = "Cooking", r.tags = "InHandCraft;CanBeDoneFromFloor";
MERGE (r:Recipe {recipe_id: "Bin2MakeCheese"}) SET r.mod_id = "bin2_extension", r.syntax = "B42", r.time = 50, r.timed_action = "Making", r.category = "Cooking", r.tags = "AnySurfaceCraft";
MERGE (r:Recipe {recipe_id: "DisassembleCrudeWoodenTongs"}) SET r.mod_id = "bin2_extension", r.syntax = "B41", r.time = 5.0, r.timed_action = "", r.category = "", r.tags = "";
MERGE (r:Recipe {recipe_id: "DisassembleSplint"}) SET r.mod_id = "bin2_extension", r.syntax = "B41", r.time = 5.0, r.timed_action = "", r.category = "", r.tags = "";

// === Item 节点 ===
MERGE (i:Item {full_type: "Base.CrudeWoodenTongs"}) SET i.display_name = "简易木钳", i.module = "Base", i.source_mod = "Base";
MERGE (i:Item {full_type: "Base.ShortBat"}) SET i.display_name = "短棒", i.module = "Base", i.source_mod = "Base";
MERGE (i:Item {full_type: "Base.RippedSheets"}) SET i.display_name = "碎布条", i.module = "Base", i.source_mod = "Base";
MERGE (i:Item {full_type: "Base.Splint"}) SET i.display_name = "夹板", i.module = "Base", i.source_mod = "Base";
MERGE (i:Item {full_type: "Base.Bowl"}) SET i.display_name = "碗", i.module = "Base", i.source_mod = "Base";
MERGE (i:Item {full_type: "Base.CheeseCloth"}) SET i.display_name = "奶酪布", i.module = "Base", i.source_mod = "Base";
MERGE (i:Item {full_type: "Base.Milk"}) SET i.display_name = "牛奶", i.module = "Base", i.source_mod = "Base";
MERGE (i:Item {full_type: "Base.Sugar"}) SET i.display_name = "糖", i.module = "Base", i.source_mod = "Base";
MERGE (i:Item {full_type: "Base.Salt"}) SET i.display_name = "盐", i.module = "Base", i.source_mod = "Base";
MERGE (i:Item {full_type: "Base.Vinegar2"}) SET i.display_name = "醋", i.module = "Base", i.source_mod = "Base";
MERGE (i:Item {full_type: "Base.Cheese"}) SET i.display_name = "奶酪", i.module = "Base", i.source_mod = "Base";

// === REQUIRES 关系 ===
MATCH (a:Mod {mod_id: "bin2_B42_13_1_Collection"}), (b:Mod {mod_id: "Lingering Voices CN"}) MERGE (a)-[:REQUIRES]->(b);
MATCH (a:Mod {mod_id: "bin2_B42_14_1_Collection"}), (b:Mod {mod_id: "EHR_CN"}) MERGE (a)-[:REQUIRES]->(b);
MATCH (a:Mod {mod_id: "bin2_B42_14_1_Collection"}), (b:Mod {mod_id: "EPR_B42_CN"}) MERGE (a)-[:REQUIRES]->(b);
MATCH (a:Mod {mod_id: "bin2_B42_14_1_Collection"}), (b:Mod {mod_id: "Lingering Voices CN"}) MERGE (a)-[:REQUIRES]->(b);
MATCH (a:Mod {mod_id: "bin2_B42_Collection"}), (b:Mod {mod_id: "EnergyRoutingSystem_CN"}) MERGE (a)-[:REQUIRES]->(b);
MATCH (a:Mod {mod_id: "bin2_B42_Collection"}), (b:Mod {mod_id: "EHR_CN"}) MERGE (a)-[:REQUIRES]->(b);
MATCH (a:Mod {mod_id: "bin2_B42_Collection"}), (b:Mod {mod_id: "EPR_B42_CN"}) MERGE (a)-[:REQUIRES]->(b);
MATCH (a:Mod {mod_id: "bin2_B42_Collection"}), (b:Mod {mod_id: "Lingering Voices CN"}) MERGE (a)-[:REQUIRES]->(b);
MATCH (a:Mod {mod_id: "bin2_B42_Collection"}), (b:Mod {mod_id: "XantjiRecycleEverything_CN"}) MERGE (a)-[:REQUIRES]->(b);
MATCH (a:Mod {mod_id: "bin2_B42_Collection"}), (b:Mod {mod_id: "ERS_SmallProducersPack_CN"}) MERGE (a)-[:REQUIRES]->(b);

// === BELONGS_TO 关系 ===
MATCH (r:Recipe {recipe_id: "Bin2DisassembleCrudeWoodenTongs"}), (m:Mod {mod_id: "bin2_extension"}) MERGE (r)-[:BELONGS_TO]->(m);
MATCH (r:Recipe {recipe_id: "Bin2DisassembleSplint"}), (m:Mod {mod_id: "bin2_extension"}) MERGE (r)-[:BELONGS_TO]->(m);
MATCH (r:Recipe {recipe_id: "Bin2MakeCheese"}), (m:Mod {mod_id: "bin2_extension"}) MERGE (r)-[:BELONGS_TO]->(m);
MATCH (r:Recipe {recipe_id: "DisassembleCrudeWoodenTongs"}), (m:Mod {mod_id: "bin2_extension"}) MERGE (r)-[:BELONGS_TO]->(m);
MATCH (r:Recipe {recipe_id: "DisassembleSplint"}), (m:Mod {mod_id: "bin2_extension"}) MERGE (r)-[:BELONGS_TO]->(m);

// === CONSUMES 关系 ===
MATCH (r:Recipe {recipe_id: "Bin2DisassembleCrudeWoodenTongs"}), (i:Item {full_type: "Base.CrudeWoodenTongs"}) MERGE (r)-[rel:CONSUMES {count: 1, mode: "consume", prop: ""}]->(i);
MATCH (r:Recipe {recipe_id: "Bin2DisassembleSplint"}), (i:Item {full_type: "Base.Splint"}) MERGE (r)-[rel:CONSUMES {count: 1, mode: "consume", prop: ""}]->(i);
MATCH (r:Recipe {recipe_id: "Bin2MakeCheese"}), (i:Item {full_type: "Base.Bowl"}) MERGE (r)-[rel:CONSUMES {count: 1, mode: "keep", prop: "Prop1"}]->(i);
MATCH (r:Recipe {recipe_id: "Bin2MakeCheese"}), (i:Item {full_type: "Base.CheeseCloth"}) MERGE (r)-[rel:CONSUMES {count: 1, mode: "consume", prop: ""}]->(i);
MATCH (r:Recipe {recipe_id: "Bin2MakeCheese"}), (i:Item {full_type: "Base.Milk"}) MERGE (r)-[rel:CONSUMES {count: 1, mode: "consume", prop: ""}]->(i);
MATCH (r:Recipe {recipe_id: "Bin2MakeCheese"}), (i:Item {full_type: "Base.Sugar"}) MERGE (r)-[rel:CONSUMES {count: 1, mode: "consume", prop: ""}]->(i);
MATCH (r:Recipe {recipe_id: "Bin2MakeCheese"}), (i:Item {full_type: "Base.Salt"}) MERGE (r)-[rel:CONSUMES {count: 1, mode: "consume", prop: ""}]->(i);
MATCH (r:Recipe {recipe_id: "Bin2MakeCheese"}), (i:Item {full_type: "Base.Vinegar2"}) MERGE (r)-[rel:CONSUMES {count: 1, mode: "consume", prop: ""}]->(i);
MATCH (r:Recipe {recipe_id: "DisassembleCrudeWoodenTongs"}), (i:Item {full_type: "Base.CrudeWoodenTongs"}) MERGE (r)-[rel:CONSUMES {count: 1, mode: "consume", prop: ""}]->(i);
MATCH (r:Recipe {recipe_id: "DisassembleSplint"}), (i:Item {full_type: "Base.Splint"}) MERGE (r)-[rel:CONSUMES {count: 1, mode: "consume", prop: ""}]->(i);

// === PRODUCES 关系 ===
MATCH (r:Recipe {recipe_id: "Bin2DisassembleCrudeWoodenTongs"}), (i:Item {full_type: "Base.ShortBat"}) MERGE (r)-[rel:PRODUCES {count: 2, chance: 1.0}]->(i);
MATCH (r:Recipe {recipe_id: "Bin2DisassembleCrudeWoodenTongs"}), (i:Item {full_type: "Base.RippedSheets"}) MERGE (r)-[rel:PRODUCES {count: 1, chance: 1.0}]->(i);
MATCH (r:Recipe {recipe_id: "Bin2DisassembleSplint"}), (i:Item {full_type: "Base.ShortBat"}) MERGE (r)-[rel:PRODUCES {count: 2, chance: 1.0}]->(i);
MATCH (r:Recipe {recipe_id: "Bin2DisassembleSplint"}), (i:Item {full_type: "Base.RippedSheets"}) MERGE (r)-[rel:PRODUCES {count: 1, chance: 1.0}]->(i);
MATCH (r:Recipe {recipe_id: "Bin2MakeCheese"}), (i:Item {full_type: "Base.Cheese"}) MERGE (r)-[rel:PRODUCES {count: 1, chance: 1.0}]->(i);
MATCH (r:Recipe {recipe_id: "DisassembleCrudeWoodenTongs"}), (i:Item {full_type: "Base.ShortBat"}) MERGE (r)-[rel:PRODUCES {count: 2, chance: 1.0}]->(i);
MATCH (r:Recipe {recipe_id: "DisassembleCrudeWoodenTongs"}), (i:Item {full_type: "Base.RippedSheets"}) MERGE (r)-[rel:PRODUCES {count: 1, chance: 1.0}]->(i);
MATCH (r:Recipe {recipe_id: "DisassembleSplint"}), (i:Item {full_type: "Base.ShortBat"}) MERGE (r)-[rel:PRODUCES {count: 2, chance: 1.0}]->(i);
MATCH (r:Recipe {recipe_id: "DisassembleSplint"}), (i:Item {full_type: "Base.RippedSheets"}) MERGE (r)-[rel:PRODUCES {count: 1, chance: 1.0}]->(i);
