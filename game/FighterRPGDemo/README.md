# 修尔基础机动 Demo

当前场景只验证角色待机、移动、跳跃与瞬移，不包含敌人和战斗系统。

## 操作

- `A/D`：高速悬行
- `Space/K`：二段跳
- `L`：地面瞬移；空中每次滞空可冲刺一次

## 当前动画

- 待机：`xiuer-video-replica-idle-v2-enhanced.png`，3×2、单格 512×512、6 帧。
- 移动：`xiuer-regal-glide-loop-v3.png`，3×2、单格 896×896、5 帧。
- 跳跃：`xiuer-idle-motion-jump-v1.png`，从待机六帧生成并移除地面椭圆，3×2、单格 512×512、6 帧。
- 瞬移：不绘制裂隙、波纹或尾流，只保留五层等比例渐变角色残影。

待机和跳跃统一使用 `0.32` 显示比例。移动使用规范化后的 896 图集和 `0.27` 比例，在屏幕上的角色尺寸与待机一致。

## 自动验证

在项目目录运行：

```powershell
godot --headless --path . --script res://scripts/verify_xiuer_hover_teleport.gd
godot --headless --path . --script res://scripts/verify_xiuer_double_jump.gd
```

两项测试分别覆盖地面移动/瞬移，以及二段跳/空中冲刺/落地重置。
