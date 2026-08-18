# 晓光项目结构

这是项目根目录，也是 Godot 工程入口。打开根目录下的 `project.godot` 即可运行。

```text
Game/
├─ project.godot              # Godot 工程配置；主场景指向神社测试关卡
├─ assets/                    # 运行时资源，只放游戏会直接加载的文件
│  ├─ characters/xiaoguang/   # 晓光动画帧与技能特效
│  ├─ environments/shrine/    # 神社场景背景
│  └─ monsters/rock_crown/    # 岩冠怪物原画与动画帧
├─ scenes/                    # 场景定义（.tscn）
├─ scripts/                   # 与场景对应的 GDScript（.gd）
├─ source_assets/             # 美术源文件、参考资料、生成素材与离线工具
│  ├─ character_design/       # 角色概念图、姿势与多视图设计
│  ├─ monsters/               # 怪物源视频和参考图
│  ├─ skills/                 # 技能制作素材与调试帧
│  ├─ tools/                  # 离线素材处理脚本和工作流
│  ├─ video_generation/       # 视频生成输入、提示词和结果
│  └─ workbench/              # 手工修图与边界标注
├─ README_PIPELINE.md         # 动画素材处理流程
└─ PROJECT_STRUCTURE.md       # 本文件
```

## 目录约定

- `assets/` 只保存 `res://` 场景或脚本实际引用的发布资源。
- `source_assets/` 保存不可直接发布的大文件、生成过程和可再生产工具。
- `scenes/` 与 `scripts/` 中同一功能使用相同文件名，例如 `rock_crown_monster.tscn` 对应 `rock_crown_monster.gd`。
- 新角色放入 `assets/characters/<角色名>/`，新怪物放入 `assets/monsters/<怪物名>/`，关卡环境放入 `assets/environments/<场景名>/`。
- Godot 生成的 `.godot/`、测试数据和构建输出不属于源码，由 `.gitignore` 排除。

## 当前入口与模块

- 主场景：`scenes/shrine_test_level.tscn`
- 玩家：`scenes/new_swordswoman.tscn`
- 玩家动画预览：`scenes/new_swordswoman_preview.tscn`
- 怪物：`scenes/rock_crown_monster.tscn`

`game/FighterRPGDemo/` 当前仅包含本地 Godot 缓存，不含工程源码，不应作为项目入口或提交到版本库。
