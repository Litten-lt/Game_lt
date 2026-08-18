# 晓光角色动画处理区

- `assets/characters/xiaoguang/animations/`：Godot 使用的透明序列帧。
- `source_assets/video_generation/`：视频生成输入、提示词和结果。
- `source_assets/workbench/`：视频裁切、候选帧、PSD 修图和边界标注等中间产物。
- `source_assets/tools/project_tools/build_animation_candidates.py`：重新生成候选动画帧。
- `source_assets/tools/project_tools/build_rock_crown_animations.py`：重新生成岩冠怪物动画帧。
- `scenes/new_swordswoman_preview.tscn`：独立动画预览入口。

当前动作帧数：idle 8、walk 12、run 11、jump 17、dash 17、普攻一段 8、二段 10、三段 10。

三段普攻由 `source_assets/tools/project_tools/build_normal_attack_combo.py` 根据确认过的候选帧生成，统一输出为透明 1024×512 PNG，并保持人物脚底锚点一致。运行素材生成脚本后，需要让 Godot 完成图片重新导入再启动游戏。

处理原则：源视频、提示词和调试图保留在 `source_assets/`，只有最终确认且被 Godot 使用的 PNG 序列帧进入 `assets/`。
