# 素材管理

素材按 `characters/`、`enemies/`、`environment/`、`items/`、`ui/`、`audio/` 分类。

每个外部素材包在 `assets/licenses/` 记录：作者、原始页面、下载链接、许可名称、许可原文、取得时间、修改内容、游戏内用途与署名要求。可用性须从作者原始发布页面核实。

当前使用项目生成的Q版西幻美术：`characters/` 为营地立绘，`animations/` 为12套动作图及帧区域数据，`environment/world-floor.png` 为大地图地面，`field-atlas.png` 为八种场地效果的共享图集。角色与地面运行时限制512像素，场地图集限制1024像素（4×2格）；图集由表现层共享，角色脚底基准一致。原庭院图片保留为早期资源档案。

`licenses/asset-inventory.json` 记录当前28个主要素材的用途、来源、字节数及SHA256；`generated-art.json` 保留已存下的原始生成提示词。部分角色图集随后修订过留白，库存清单与动画元数据中的哈希对应当前最终文件，不把旧提示词视为修订后的完整记录。0.6的地面与场地图集完整提示词、原图路径、格序和运行时尺寸记录在`licenses/world-art-0.6.json`。

0.7装备与药剂采用生成的 `items/loot-atlas.png`，4×2透明图集，运行时1024×512并由 `loot_sprites.gd` 共享。剑、杖、弓、锁甲、饰品、靴子和药剂用于真实掉落和装备比较，提示词及原图记录见 `licenses/loot-art-0.7.json`。

中文字体为Google Fonts的Noto Sans SC，完整OFL许可见 `licenses/NotoSansSC-OFL.txt`。音效和32秒配乐由 `tools/compose_audio.py` 原创合成。下载的Kenney Tiny Dungeon素材包作为未使用的资源档案保留，含原许可，已通过 `.gdignore` 和导出过滤排除出游戏。
