import logging
from typing import Dict, List, Optional

from py2neo import Graph, Node, Relationship

logger = logging.getLogger(__name__)


class ModDependencyGraph:
    """Project Zomboid 模组依赖关系图数据库"""

    def __init__(
        self,
        uri: str = "bolt://localhost:7687",
        user: str = "neo4j",
        password: str = "please_change_md",
    ):
        """
        初始化图数据库连接
        默认连接到本地 Neo4j 实例
        """
        self.graph = Graph(uri, auth=(user, password))
        self._create_constraints()

    def _create_constraints(self):
        """创建节点约束以确保唯一性"""
        try:
            # 创建模组 ID 的唯一约束
            self.graph.run(
                "CREATE CONSTRAINT mod_id_unique IF NOT EXISTS FOR (m:Mod) REQUIRE m.mod_id IS UNIQUE"
            )
            logger.info("成功创建模组 ID 唯一约束")
        except Exception as e:
            logger.warning(f"创建约束时出错: {e}")

    def add_mod(
        self,
        mod_id: str,
        name: str,
        author: str = "",
        version: str = "",
        description: str = "",
        workshop_url: str = "",
    ) -> bool:
        """
        添加模组节点到图数据库
        如果模组已存在则更新信息
        """
        try:
            # 使用 MERGE 确保唯一性，如果不存在则创建，存在则更新
            query = """
            MERGE (m:Mod {mod_id: $mod_id})
            SET m.name = $name,
                m.author = $author,
                m.version = $version,
                m.description = $description,
                m.workshop_url = $workshop_url,
                m.updated_at = datetime()
            RETURN m
            """
            result = self.graph.run(
                query,
                mod_id=mod_id,
                name=name,
                author=author,
                version=version,
                description=description,
                workshop_url=workshop_url,
            )

            if result.single():
                logger.info(f"成功添加/更新模组: {mod_id} - {name}")
                return True
            else:
                logger.error(f"未能添加模组: {mod_id}")
                return False

        except Exception as e:
            logger.error(f"添加模组失败 {mod_id}: {e}")
            return False

    def add_dependency(self, parent_mod_id: str, child_mod_id: str) -> bool:
        """
        添加依赖关系: parent_mod 依赖于 child_mod
        """
        try:
            # 创建依赖关系 (parent)-[:REQUIRES]->(child)
            query = """
            MATCH (parent:Mod {mod_id: $parent_mod_id})
            MATCH (child:Mod {mod_id: $child_mod_id})
            MERGE (parent)-[:REQUIRES]->(child)
            RETURN parent, child
            """
            result = self.graph.run(
                query, parent_mod_id=parent_mod_id, child_mod_id=child_mod_id
            )

            if result.single():
                logger.info(f"成功添加依赖关系: {parent_mod_id} -> {child_mod_id}")
                return True
            else:
                logger.warning(
                    f"无法建立依赖关系，可能因为模组未找到: {parent_mod_id} -> {child_mod_id}"
                )
                # 尝试创建缺失的节点
                self._ensure_mod_exists(parent_mod_id)
                self._ensure_mod_exists(child_mod_id)
                # 再次尝试创建关系
                result_retry = self.graph.run(
                    query, parent_mod_id=parent_mod_id, child_mod_id=child_mod_id
                )
                return result_retry.single() is not None

        except Exception as e:
            logger.error(f"添加依赖关系失败 {parent_mod_id} -> {child_mod_id}: {e}")
            return False

    def _ensure_mod_exists(self, mod_id: str):
        """确保模组节点存在，如果不存在则创建一个基本节点"""
        try:
            query = """
            MERGE (m:Mod {mod_id: $mod_id})
            ON CREATE SET m.name = $mod_id, m.created_at = datetime()
            """
            self.graph.run(query, mod_id=mod_id)
        except Exception as e:
            logger.error(f"确保模组存在失败 {mod_id}: {e}")

    def get_dependencies(self, mod_id: str) -> List[Dict]:
        """获取指定模组的直接依赖项"""
        try:
            query = """
            MATCH (m:Mod {mod_id: $mod_id})-[r:REQUIRES]->(dep:Mod)
            RETURN dep.mod_id AS mod_id, dep.name AS name, dep.author AS author, dep.version AS version
            """
            result = self.graph.run(query, mod_id=mod_id)
            return [record.data() for record in result]
        except Exception as e:
            logger.error(f"获取依赖项失败 {mod_id}: {e}")
            return []

    def get_dependents(self, mod_id: str) -> List[Dict]:
        """获取依赖指定模组的所有模组"""
        try:
            query = """
            MATCH (dep:Mod)-[r:REQUIRES]->(m:Mod {mod_id: $mod_id})
            RETURN dep.mod_id AS mod_id, dep.name AS name, dep.author AS author, dep.version AS version
            """
            result = self.graph.run(query, mod_id=mod_id)
            return [record.data() for record in result]
        except Exception as e:
            logger.error(f"获取被依赖项失败 {mod_id}: {e}")
            return []

    def get_full_dependency_graph(self, mod_id: str, depth: int = 3) -> Dict:
        """获取完整依赖图（递归）"""
        try:
            # 使用 Cypher 查询递归获取依赖图
            query = f"""
            MATCH (root:Mod {{mod_id: $mod_id}})
            OPTIONAL MATCH path = (root)-[:REQUIRES*0..{depth}]->(dep:Mod)
            WITH root, collect(path) as paths
            UNWIND paths as p
            WITH nodes(p) as nodes_in_path
            UNWIND nodes_in_path as node
            RETURN DISTINCT node.mod_id as mod_id,
                          node.name as name,
                          node.author as author,
                          node.version as version
            """
            result = self.graph.run(query, mod_id=mod_id)
            nodes = [record.data() for record in result]

            # 获取所有关系
            rel_query = f"""
            MATCH (root:Mod {{mod_id: $mod_id}})-[:REQUIRES*0..{depth}]-(dep:Mod)
            MATCH (from:Mod)-[:REQUIRES]->(to:Mod)
            WHERE (from.mod_id IN [n.mod_id IN nodes(p) WHERE length(nodes(p)) > 0] AND
                   to.mod_id IN [n.mod_id IN nodes(p) WHERE length(nodes(p)) > 0])
            RETURN from.mod_id as from_id, to.mod_id as to_id
            """
            rel_result = self.graph.run(rel_query, mod_id=mod_id)
            edges = [
                {"from": record["from_id"], "to": record["to_id"]}
                for record in rel_result
            ]

            return {"nodes": nodes, "edges": edges}
        except Exception as e:
            logger.error(f"获取完整依赖图失败 {mod_id}: {e}")
            return {"nodes": [], "edges": []}

    def search_mods(self, query_str: str, limit: int = 10) -> List[Dict]:
        """搜索模组"""
        try:
            query = """
            MATCH (m:Mod)
            WHERE toLower(m.name) CONTAINS toLower($query_str) OR
                  toLower(m.mod_id) CONTAINS toLower($query_str) OR
                  toLower(m.author) CONTAINS toLower($query_str)
            RETURN m.mod_id AS mod_id, m.name AS name, m.author AS author, m.version AS version
            LIMIT $limit
            """
            result = self.graph.run(query, query_str=query_str, limit=limit)
            return [record.data() for record in result]
        except Exception as e:
            logger.error(f"搜索模组失败: {e}")
            return []

    def get_statistics(self) -> Dict:
        """获取数据库统计信息"""
        try:
            stats_query = """
            MATCH (m:Mod)
            RETURN count(m) as mod_count
            """
            mod_count = self.graph.run(stats_query).single()["mod_count"]

            deps_query = """
            MATCH ()-[r:REQUIRES]->()
            RETURN count(r) as dependency_count
            """
            dep_count = self.graph.run(deps_query).single()["dependency_count"]

            return {"total_mods": mod_count, "total_dependencies": dep_count}
        except Exception as e:
            logger.error(f"获取统计信息失败: {e}")
            return {"total_mods": 0, "total_dependencies": 0}

    def close(self):
        """关闭数据库连接"""
        pass  # py2neo 的连接池会自动处理
