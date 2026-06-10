"""
Project Zomboid 配方合成图数据模型

在 mod_dependency_analyzer/models.py 已有 ModDependencyGraph 基础上,
扩展支持:
- Recipe 节点 (制作配方)
- Item 节点 (物品)
- CONSUMES / PRODUCES / BELONGS_TO 关系

设计原则:
- 复用 py2neo 的 Graph 连接与约束模式
- 不重写 add_mod / add_dependency,通过组合复用
- 所有方法采用 MERGE 语义,确保幂等
"""

from py2neo import Graph, Node, Relationship
from typing import List, Dict, Optional, Set
import logging

logger = logging.getLogger(__name__)


class RecipeGraph:
    """Project Zomboid 配方合成图 (Item <-> Recipe)"""

    def __init__(self, uri: str = "bolt://localhost:7687", user: str = "neo4j", password: str = "password"):
        """
        初始化图数据库连接
        默认连接到本地 Neo4j 实例
        """
        self.graph = Graph(uri, auth=(user, password))
        self._create_constraints()

    def _create_constraints(self):
        """创建节点约束以确保唯一性"""
        try:
            # Recipe.recipe_id 全局唯一
            self.graph.run("CREATE CONSTRAINT recipe_id_unique IF NOT EXISTS FOR (r:Recipe) REQUIRE r.recipe_id IS UNIQUE")
            # Item.full_type 全局唯一
            self.graph.run("CREATE CONSTRAINT item_full_type_unique IF NOT EXISTS FOR (i:Item) REQUIRE i.full_type IS UNIQUE")
            logger.info("成功创建 Recipe/Item 唯一约束")
        except Exception as e:
            logger.warning(f"创建约束时出错: {e}")

    def add_recipe(self, recipe_id: str, mod_id: str, syntax: str = "B42",
                   time: int = 50, timed_action: str = "", category: str = "",
                   tags: str = "", allow_batch: bool = False,
                   need_to_learn: bool = False) -> bool:
        """
        添加 Recipe 节点到图数据库
        syntax: 'B41' 或 'B42'
        """
        try:
            query = """
            MERGE (r:Recipe {recipe_id: $recipe_id})
            SET r.mod_id = $mod_id,
                r.syntax = $syntax,
                r.time = $time,
                r.timed_action = $timed_action,
                r.category = $category,
                r.tags = $tags,
                r.allow_batch = $allow_batch,
                r.need_to_learn = $need_to_learn,
                r.updated_at = datetime()
            RETURN r
            """
            result = self.graph.run(query,
                                    recipe_id=recipe_id,
                                    mod_id=mod_id,
                                    syntax=syntax,
                                    time=time,
                                    timed_action=timed_action,
                                    category=category,
                                    tags=tags,
                                    allow_batch=allow_batch,
                                    need_to_learn=need_to_learn)
            if result.single():
                logger.info(f"成功添加/更新 Recipe: {recipe_id} ({syntax})")
                return True
            else:
                logger.error(f"未能添加 Recipe: {recipe_id}")
                return False
        except Exception as e:
            logger.error(f"添加 Recipe 失败 {recipe_id}: {e}")
            return False

    def add_item(self, full_type: str, display_name: str = "",
                 module: str = "", source_mod: str = "Base") -> bool:
        """
        添加 Item 节点
        full_type: 完整物品 ID, 如 "Base.Cheese" / "Xantji.RubberProjectile223"
        module: 物品所属 module,如 "Base", "Xantji" (从 full_type 解析)
        source_mod: 哪个 mod 定义了这个物品 (默认 "Base" 表示原版)
        """
        try:
            # 自动解析 module (full_type 的第一段)
            if not module and '.' in full_type:
                module = full_type.split('.', 1)[0]

            query = """
            MERGE (i:Item {full_type: $full_type})
            SET i.display_name = $display_name,
                i.module = $module,
                i.source_mod = $source_mod,
                i.updated_at = datetime()
            RETURN i
            """
            result = self.graph.run(query,
                                    full_type=full_type,
                                    display_name=display_name,
                                    module=module,
                                    source_mod=source_mod)
            if result.single():
                logger.debug(f"成功添加/更新 Item: {full_type} ({display_name})")
                return True
            return False
        except Exception as e:
            logger.error(f"添加 Item 失败 {full_type}: {e}")
            return False

    def add_belongs_to(self, recipe_id: str, mod_id: str) -> bool:
        """添加 (Recipe)-[:BELONGS_TO]->(Mod) 关系"""
        try:
            query = """
            MATCH (r:Recipe {recipe_id: $recipe_id})
            MERGE (m:Mod {mod_id: $mod_id})
            MERGE (r)-[:BELONGS_TO]->(m)
            RETURN r, m
            """
            result = self.graph.run(query, recipe_id=recipe_id, mod_id=mod_id)
            return result.single() is not None
        except Exception as e:
            logger.error(f"添加 BELONGS_TO 关系失败 {recipe_id} -> {mod_id}: {e}")
            return False

    def add_consumes(self, recipe_id: str, full_type: str, count: int = 1,
                     mode: str = "consume", prop: str = "") -> bool:
        """
        添加 (Recipe)-[:CONSUMES {count, mode, prop}]->(Item) 关系
        mode: 'consume' (默认消耗) / 'keep' (保留) / 'destroy' (销毁)
        prop: 'Prop1' (主手) / 'Prop2' (副手) / ''
        """
        try:
            query = """
            MATCH (r:Recipe {recipe_id: $recipe_id})
            MERGE (i:Item {full_type: $full_type})
            MERGE (r)-[rel:CONSUMES]->(i)
            SET rel.count = $count,
                rel.mode = $mode,
                rel.prop = $prop
            RETURN r, i
            """
            result = self.graph.run(query,
                                    recipe_id=recipe_id,
                                    full_type=full_type,
                                    count=count,
                                    mode=mode,
                                    prop=prop)
            return result.single() is not None
        except Exception as e:
            logger.error(f"添加 CONSUMES 关系失败 {recipe_id} -> {full_type}: {e}")
            return False

    def add_produces(self, recipe_id: str, full_type: str,
                     count: int = 1, chance: float = 1.0) -> bool:
        """
        添加 (Recipe)-[:PRODUCES {count, chance}]->(Item) 关系
        """
        try:
            query = """
            MATCH (r:Recipe {recipe_id: $recipe_id})
            MERGE (i:Item {full_type: $full_type})
            MERGE (r)-[rel:PRODUCES]->(i)
            SET rel.count = $count,
                rel.chance = $chance
            RETURN r, i
            """
            result = self.graph.run(query,
                                    recipe_id=recipe_id,
                                    full_type=full_type,
                                    count=count,
                                    chance=chance)
            return result.single() is not None
        except Exception as e:
            logger.error(f"添加 PRODUCES 关系失败 {recipe_id} -> {full_type}: {e}")
            return False

    def get_recipe_inputs(self, recipe_id: str) -> List[Dict]:
        """获取配方的所有原料"""
        try:
            query = """
            MATCH (r:Recipe {recipe_id: $recipe_id})-[c:CONSUMES]->(i:Item)
            RETURN i.full_type AS full_type,
                   i.display_name AS display_name,
                   c.count AS count,
                   c.mode AS mode,
                   c.prop AS prop
            ORDER BY i.full_type
            """
            return [record.data() for record in self.graph.run(query, recipe_id=recipe_id)]
        except Exception as e:
            logger.error(f"获取原料失败 {recipe_id}: {e}")
            return []

    def get_recipe_outputs(self, recipe_id: str) -> List[Dict]:
        """获取配方的所有产物"""
        try:
            query = """
            MATCH (r:Recipe {recipe_id: $recipe_id})-[p:PRODUCES]->(i:Item)
            RETURN i.full_type AS full_type,
                   i.display_name AS display_name,
                   p.count AS count,
                   p.chance AS chance
            ORDER BY i.full_type
            """
            return [record.data() for record in self.graph.run(query, recipe_id=recipe_id)]
        except Exception as e:
            logger.error(f"获取产物失败 {recipe_id}: {e}")
            return []

    def get_crafting_tree(self, item_full_type: str, max_depth: int = 5) -> List[Dict]:
        """
        获取指定物品的完整合成树(递归向上追溯原料)
        返回路径列表,每条路径描述一个可能的合成路线
        """
        try:
            query = f"""
            MATCH path = (i:Item {{full_type: $full_type}})<-[:PRODUCES]-(r:Recipe)
                  -[:CONSUMES*1..{max_depth}]->(sub:Item)
            WHERE r <> sub
            RETURN [n IN nodes(path) | COALESCE(n.recipe_id, n.full_type)] AS path_nodes,
                   [r IN relationships(path) | type(r)] AS path_rels,
                   length(path) AS depth
            LIMIT 100
            """
            return [record.data() for record in self.graph.run(query, full_type=item_full_type)]
        except Exception as e:
            logger.error(f"获取合成树失败 {item_full_type}: {e}")
            return []

    def get_recipes_producing(self, item_full_type: str) -> List[Dict]:
        """查找能产出指定物品的所有配方"""
        try:
            query = """
            MATCH (r:Recipe)-[p:PRODUCES]->(i:Item {full_type: $full_type})
            RETURN r.recipe_id AS recipe_id,
                   r.mod_id AS mod_id,
                   r.syntax AS syntax,
                   p.count AS count
            """
            return [record.data() for record in self.graph.run(query, full_type=item_full_type)]
        except Exception as e:
            logger.error(f"查找产出配方失败 {item_full_type}: {e}")
            return []

    def get_statistics(self) -> Dict:
        """统计图数据库现状"""
        try:
            stats = {}
            for label in ['Mod', 'Recipe', 'Item']:
                count = self.graph.run(f"MATCH (n:{label}) RETURN count(n) AS c").single()["c"]
                stats[f"{label.lower()}_count"] = count
            for rel in ['REQUIRES', 'BELONGS_TO', 'CONSUMES', 'PRODUCES']:
                count = self.graph.run(f"MATCH ()-[r:{rel}]->() RETURN count(r) AS c").single()["c"]
                stats[f"{rel.lower()}_count"] = count
            return stats
        except Exception as e:
            logger.error(f"获取统计信息失败: {e}")
            return {}

    def clear_all(self):
        """删除所有节点和关系 (慎用!)"""
        self.graph.run("MATCH (n) DETACH DELETE n")
        logger.warning("已清空图数据库")

    def close(self):
        """关闭数据库连接"""
        pass  # py2neo 的连接池会自动处理
