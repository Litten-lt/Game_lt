# 修尔基础机动 Demo

当前场景只验证角色待机、移动、跳跃与瞬移，不包含敌人和战斗系统。

## 架构

- 主场景：`scenes/main.tscn`（地面 StaticBody2D + Camera2D + 角色实例）
- 角色场景：`scenes/player/xiuer.tscn`（CharacterBody2D + CollisionShape2D + Sprite2D）
- 角色控制器：`scenes/player/xiuer.gd`（状态机 + Godot 物理 + 手感特性）

## 操作

- `A/D`：高速悬行
- `Space/K`：二段跳（支持土狼时间 0.10s、跳跃输入缓存 0.12s、按住更高/松开更短的可变跳跃高度）
- `L`：地面瞬移；空中每次滞空可冲刺一次

## 当前动画

- 待机：`xiuer-video-replica-idle-v2-enhanced.png`，3×2、单格 512×512、6 帧。
- 移动：`xiuer-video-move-loop-v1.png`，从完整连续动作视频以 12 FPS 抽取，11×11、单格 512×512、有效 121 帧。
- 跳跃：`xiuer-idle-motion-jump-v1.png`，从待机六帧生成并移除地面椭圆，3×2、单格 512×512、6 帧。
- 瞬移：不绘制裂隙、波纹或尾流，只保留五层等比例渐变角色残影。

待机、移动和跳跃统一使用 512×512 单格与 `0.32` 显示比例。移动帧按躯干中心和统一角色高度注册，屏幕上的角色尺寸与待机一致；水平位移仍由 Godot 物理控制。

## 自动验证

在项目目录运行：

```powershell
godot --headless --path . --script res://scripts/verify_xiuer_hover_teleport.gd
godot --headless --path . --script res://scripts/verify_xiuer_double_jump.gd
```

两项测试分别覆盖地面移动/瞬移，以及二段跳/空中冲刺/落地重置。
