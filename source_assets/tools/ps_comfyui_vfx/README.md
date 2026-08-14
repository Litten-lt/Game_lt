# 小光 PS + ComfyUI 特效工作区

## 文件流

1. Photoshop 在 768×768 透明画布中建立：`角色参考`、`特效草图`、`生成遮罩` 三组。
2. 导出 `input/effect_base.png`：角色参考与特效草图合并，背景保持黑色或透明。
3. 导出 `input/effect_mask.png`：黑底白形，白色是允许 AI 重绘的特效区域。
4. 在 ComfyUI 打开 `workflows/01_ps_mask_inpaint_sd15.json`，分别载入两张图片。
5. 选择 SD 1.5 inpainting checkpoint，点击 Queue。
6. 结果从 ComfyUI output 保存到 `output/generated`，再回 PS 清边、统一颜色和拆逐帧。

## Photoshop 图层

- `GUIDE_character`：角色参考，50% 不透明度，只用来确认位置。
- `VFX_sketch`：白色硬边画笔画特效轮廓和运动方向。
- `MASK_white`：纯黑底，允许生成的区域为纯白。
- `NOTES`：箭头、文字，仅保留在 PSD，导出时隐藏。

## 3060 Ti 建议参数

- 画布：先用 512×512 或 768×768。
- Steps：24。
- CFG：6。
- Denoise：0.45（严格遵守草图）到 0.65（允许扩展细节）。
- Sampler：DPM++ 2M；Scheduler：Karras。
- 固定 seed，在同一套关键帧中只改草图，减少风格跳变。

## 小光特效提示词

正向：

`2D anime side-scrolling game VFX, crescent sword slash, brilliant white hot core, saturated crimson red outer energy, sharp tapered silhouette, flowing motion streaks, high contrast, isolated effect, clean edges, no background`

反向：

`character, person, body, face, weapon, scenery, ground, text, watermark, logo, interface, photorealistic, muddy colors, green background, black rectangle, blurry`

## 逐帧策略

不要让 AI 独立生成全部帧。先做出现、扩张、最大、破碎、消散五张关键帧；固定模型、提示词和 seed，再在 PS 中补中间帧。最终导出相同画布的透明 PNG。
