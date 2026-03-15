#!/usr/bin/env python3
"""
Project Zomboid 翻译文件转换脚本
将旧格式 .txt 翻译文件转换为新格式 .json 文件

用法:
    python convert_translation.py

转换规则:
    - 旧格式: UI_CN.txt, Sandbox_CN.txt 等
    - 新格式: UI.json, Sandbox.json (去掉 _CN 后缀)
    - 目录: media/lua/shared/Translate/CN/
"""

import re
import json
import os
import glob
import sys


def parse_lua_table(content):
    """解析 Lua 表内容为 Python 字典"""
    result = {}

    # 移除单行注释
    lines = content.split('\n')
    cleaned_lines = []
    for line in lines:
        # 移除行内注释（但不在字符串内）
        if '--' in line:
            before_comment = line[:line.find('--')]
            # 只在字符串外移除
            if before_comment.count('"') % 2 == 0 and before_comment.count("'") % 2 == 0:
                line = before_comment.rstrip()
        if line.strip():
            cleaned_lines.append(line)

    content = '\n'.join(cleaned_lines)

    # 移除表头如 "UI_CN = {" 或 "local EPR_UI = {"
    content = re.sub(r'^\s*\w+\s*=\s*\{', '', content)
    content = re.sub(r'local\s+\w+\s*=\s*\{', '', content)
    # 移除闭合大括号
    content = re.sub(r'^\s*\}\s*$', '', content)

    # 过滤掉 Lua 表扩展模式
    lines = content.split('\n')
    filtered_lines = []
    for line in lines:
        if 'or' in line and '{}' in line:
            continue
        if line.strip().startswith('for '):
            continue
        if line.strip().startswith('if '):
            continue
        if line.strip() == 'end':
            continue
        filtered_lines.append(line)

    content = '\n'.join(filtered_lines)

    # 匹配 key = "value" 模式
    pattern = r'^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+)'

    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('--'):
            continue

        match = re.match(pattern, line)
        if match:
            key = match.group(1)
            value = match.group(2).rstrip(',')

            # 移除尾部逗号
            value = value.rstrip(',')

            # 移除引号
            if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
                value = value[1:-1]

            # 处理转义序列
            value = value.replace('\\n', '\n').replace('\\"', '"').replace("\\'", "'")

            result[key] = value

    return result


def convert_file(input_file, output_file):
    """转换单个文件"""
    with open(input_file, 'r', encoding='utf-8') as f:
        content = f.read()

    data = parse_lua_table(content)

    if data:
        # 确保输出目录存在
        os.makedirs(os.path.dirname(output_file), exist_ok=True)

        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=4)
        print(f"✓ {input_file} -> {output_file} ({len(data)} keys)")
        return True
    else:
        print(f"✗ 解析失败: {input_file}")
        return False


# 需要转换的文件列表
CONVERSIONS = [
    # Respawn2
    ("bin2/Contents/mods/Respawn2/media/lua/shared/Translate/CN/UI_CN.txt",
     "bin2/Contents/mods/Respawn2/media/lua/shared/Translate/CN/UI.json"),

    # Lingering Voices CN
    ("bin2_lingering_voices_cn/Contents/mods/Lingering Voices CN/42/media/lua/shared/Translate/CN/Sandbox_CN.txt",
     "bin2_lingering_voices_cn/Contents/mods/Lingering Voices CN/42/media/lua/shared/Translate/CN/Sandbox.json"),

    # Extensive Power Rework CN
    ("bin2_extensive_power_rework/Contents/mods/Extensive Power Rework CN/42/media/lua/shared/Translate/CN/UI_CN.txt",
     "bin2_extensive_power_rework/Contents/mods/Extensive Power Rework CN/42/media/lua/shared/Translate/CN/UI.json"),
    ("bin2_extensive_power_rework/Contents/mods/Extensive Power Rework CN/42/media/lua/shared/Translate/CN/ContextMenu_CN.txt",
     "bin2_extensive_power_rework/Contents/mods/Extensive Power Rework CN/42/media/lua/shared/Translate/CN/ContextMenu.json"),
    ("bin2_extensive_power_rework/Contents/mods/Extensive Power Rework CN/42/media/lua/shared/Translate/CN/Sandbox_CN.txt",
     "bin2_extensive_power_rework/Contents/mods/Extensive Power Rework CN/42/media/lua/shared/Translate/CN/Sandbox.json"),

    # Extensive Health Rework
    ("bin2_extensive_health_rework/Contents/mods/Extensive Health Rework/42/media/lua/shared/Translate/CN/Sandbox_CN.txt",
     "bin2_extensive_health_rework/Contents/mods/Extensive Health Rework/42/media/lua/shared/Translate/CN/Sandbox.json"),
    ("bin2_extensive_health_rework/Contents/mods/Extensive Health Rework/42/media/lua/shared/Translate/CN/Tooltip_CN.txt",
     "bin2_extensive_health_rework/Contents/mods/Extensive Health Rework/42/media/lua/shared/Translate/CN/Tooltip.json"),
    ("bin2_extensive_health_rework/Contents/mods/Extensive Health Rework/42/media/lua/shared/Translate/CN/UI_CN.txt",
     "bin2_extensive_health_rework/Contents/mods/Extensive Health Rework/42/media/lua/shared/Translate/CN/UI.json"),

    # EnergyRoutingSystem_CN
    ("bin2_energy_routing_system/Contents/mods/EnergyRoutingSystem_CN/42/media/lua/shared/Translate/CN/IG_UI_CN.txt",
     "bin2_energy_routing_system/Contents/mods/EnergyRoutingSystem_CN/42/media/lua/shared/Translate/CN/IG_UI.json"),
    ("bin2_energy_routing_system/Contents/mods/EnergyRoutingSystem_CN/42/media/lua/shared/Translate/CN/Sandbox_CN.txt",
     "bin2_energy_routing_system/Contents/mods/EnergyRoutingSystem_CN/42/media/lua/shared/Translate/CN/Sandbox.json"),
]


def main():
    base_dir = '/Users/liubinbin/Zomboid/Workshop'

    print("=== Project Zomboid 翻译文件转换 ===\n")

    success_count = 0
    fail_count = 0

    for src, dst in CONVERSIONS:
        src_path = os.path.join(base_dir, src)
        dst_path = os.path.join(base_dir, dst)

        if os.path.exists(src_path):
            if convert_file(src_path, dst_path):
                success_count += 1
            else:
                fail_count += 1
        else:
            print(f"✗ 源文件不存在: {src_path}")
            fail_count += 1

    print(f"\n=== 完成: {success_count} 成功, {fail_count} 失败 ===")


if __name__ == '__main__':
    main()
