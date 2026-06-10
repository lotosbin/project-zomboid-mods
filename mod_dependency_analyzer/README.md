# 模组依赖关系分析器

## 功能特性
- 动态抓取 Steam Workshop 模组信息
- 解析模组依赖关系
- 使用图数据库存储依赖关系
- 提供 Web 查询界面

## 技术栈
- Python 3.x
- Neo4j 图数据库
- Flask/FastAPI Web 框架
- requests/BeautifulSoup4 网络爬虫
- Steam API

## 安装依赖
```bash
pip install neo4j flask requests beautifulsoup4
```

## 使用方法
1. 启动 Neo4j 数据库
2. 配置数据库连接信息
3. 运行数据抓取脚本
4. 启动 Web 服务