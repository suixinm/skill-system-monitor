#!/bin/bash
# 7日趋势图（本地生成，不发送外部服务）

# 获取技能目录（脚本在 skills/skill-system-monitor/scripts/ 下）
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HISTORY_DIR="${SKILL_DIR}/history"
DAYS=7

if [ ! -d "$HISTORY_DIR" ]; then
    echo "⚠️ 历史目录不存在: $HISTORY_DIR"
    exit 1
fi

python3 << 'PYEOF'
import os
import re
from datetime import datetime, timedelta
from collections import defaultdict

HISTORY_DIR = os.environ.get('HISTORY_DIR', '/home/app/.openclaw/skills/skill-system-monitor/history')
DAYS = 7

day_disk = defaultdict(list)
day_mem = defaultdict(list)

cutoff = datetime.now() - timedelta(days=DAYS)

for filename in os.listdir(HISTORY_DIR):
    if not filename.endswith('.json'):
        continue
    
    filepath = os.path.join(HISTORY_DIR, filename)
    mtime = datetime.fromtimestamp(os.path.getmtime(filepath))
    
    if mtime < cutoff:
        continue
    
    day = mtime.strftime('%m-%d')
    
    try:
        with open(filepath) as f:
            content = f.read()
            percents = re.findall(r'"percent":\s*(\d+)', content)
            if len(percents) >= 2:
                day_disk[day].append(int(percents[0]))
                day_mem[day].append(int(percents[-1]))
    except:
        continue

if not day_disk:
    print("⚠️ 无历史数据")
    exit(0)

sorted_days = sorted(day_disk.keys())

# 今天和昨天对比
today = datetime.now().strftime('%m-%d')
yesterday = (datetime.now() - timedelta(days=1)).strftime('%m-%d')

print("📈 7日系统监控趋势")
print("================================")

if today in day_disk and yesterday in day_disk:
    today_disk = sum(day_disk[today]) // len(day_disk[today])
    yesterday_disk = sum(day_disk[yesterday]) // len(day_disk[yesterday])
    today_mem = sum(day_mem[today]) // len(day_mem[today])
    yesterday_mem = sum(day_mem[yesterday]) // len(day_mem[yesterday])
    
    disk_diff = today_disk - yesterday_disk
    mem_diff = today_mem - yesterday_mem
    
    disk_sign = "+" if disk_diff > 0 else ""
    mem_sign = "+" if mem_diff > 0 else ""
    
    print(f"💾 硬盘: {yesterday_disk}% → {today_disk}% ({disk_sign}{disk_diff}%)")
    print(f"🧠 内存: {yesterday_mem}% → {today_mem}% ({mem_sign}{mem_diff}%)")
    
    if disk_diff > 5:
        print("⚠️ 硬盘使用增长较快！")
    if mem_diff > 10:
        print("⚠️ 内存使用增长较快！")
else:
    print("⚠️ 缺少昨日数据，无法对比")

print()

# 本地 ASCII 图表
def make_bar(percent, width=20):
    """生成 ASCII 条形图"""
    filled = int(percent / 100 * width)
    bar = "█" * filled + "░" * (width - filled)
    return bar

print("📊 趋势图表 (本地生成)")
print("-" * 40)

print("\n💾 硬盘使用率:")
for day in sorted_days:
    avg = sum(day_disk[day]) // len(day_disk[day])
    bar = make_bar(avg)
    print(f"  {day} [{bar}] {avg}%")

print("\n🧠 内存使用率:")
for day in sorted_days:
    avg = sum(day_mem[day]) // len(day_mem[day])
    bar = make_bar(avg)
    print(f"  {day} [{bar}] {avg}%")

print()
print("─" * 40)
print("✅ 图表已本地生成，无外部数据传输")
PYEOF
