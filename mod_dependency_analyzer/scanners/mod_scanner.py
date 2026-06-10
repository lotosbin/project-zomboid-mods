"""
mod_scanner.py: 扫描 mod.info 文件,提取 Mod 节点与 REQUIRES 关系

mod.info 格式 (key=value):
    name=xxx
    id=xxx
    poster=poster.png
    versionMin=42.15.0
    modversion=1.0.0
    description=xxx
    require=ModA,ModB,ModC
    tags=QoL;Recipe
    author=xxx
    category=content
    loadModAfter=\\ModX,\\ModY
    incompatible=\\OldMod
"""

import os
import re
from typing import Dict, List, Optional
from dataclasses import dataclass, field


@dataclass
class ModInfo:
    """单个 mod.info 解析结果"""
    mod_id: str = ""
    name: str = ""
    author: str = ""
    version: str = ""  # modversion
    pz_version: str = ""  # versionMin
    description: str = ""
    tags: List[str] = field(default_factory=list)
    requires: List[str] = field(default_factory=list)
    incompatible: List[str] = field(default_factory=list)
    load_after: List[str] = field(default_factory=list)
    source_dir: str = ""  # mod 所在目录
    mod_info_path: str = ""


def parse_mod_info(path: str) -> Optional[ModInfo]:
    """
    解析单个 mod.info 文件
    """
    if not os.path.isfile(path):
        return None

    info = ModInfo(mod_info_path=path, source_dir=os.path.dirname(path))
    # source_dir 的上一层(典型为 <mod_root>/42.x/)
    info.source_dir = os.path.dirname(path)

    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            # 拆分 key=value (只拆第一个 =)
            key, _, value = line.partition('=')
            key = key.strip()
            value = value.strip()
            if not value:
                continue

            if key == 'id':
                info.mod_id = value
            elif key == 'name':
                info.name = value
            elif key == 'author':
                info.author = value
            elif key == 'modversion':
                info.version = value
            elif key == 'versionMin':
                info.pz_version = value
            elif key == 'description':
                info.description = value
            elif key == 'tags':
                info.tags = [t for t in value.split(';') if t]
            elif key == 'require':
                # require=ModA,ModB,ModC
                info.requires = [m.strip() for m in value.split(',') if m.strip()]
            elif key == 'incompatible':
                # incompatible=\\OldModA,\\OldModB
                info.incompatible = [m.strip().lstrip('\\') for m in value.split(',') if m.strip()]
            elif key == 'loadModAfter':
                info.load_after = [m.strip().lstrip('\\') for m in value.split(',') if m.strip()]

    if not info.mod_id:
        # 没有 id 字段的文件不是有效 mod.info
        return None

    return info


def scan_workshop(root: str, exclude_dirs: Optional[List[str]] = None) -> List[ModInfo]:
    """
    扫描整个 Workshop 目录,返回所有 mod.info 的解析结果
    root: Workshop 根目录
    exclude_dirs: 跳过的目录名列表(默认跳过 learn, bak, .git, docs)
    """
    if exclude_dirs is None:
        exclude_dirs = ['learn', 'bak', '.git', 'docs', 'mod_dependency_analyzer',
                        'node_modules', '__pycache__', '.idea']

    results = []
    for dirpath, dirnames, filenames in os.walk(root):
        # 过滤目录
        dirnames[:] = [d for d in dirnames if d not in exclude_dirs and not d.startswith('.')]

        for filename in filenames:
            if filename == 'mod.info':
                full_path = os.path.join(dirpath, filename)
                info = parse_mod_info(full_path)
                if info:
                    results.append(info)

    return results


if __name__ == '__main__':
    # 自测
    import sys
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    mods = scan_workshop(root)
    print(f"扫描到 {len(mods)} 个 mod:")
    for m in mods:
        print(f"  - {m.mod_id:40s} v{m.version:10s} ({m.pz_version})  req={m.requires}")
