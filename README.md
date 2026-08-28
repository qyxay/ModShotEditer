# OneShot Mod 工作台 (ModShot)

基于 ModShot(mkxp-z) 的 OneShot 自编译 mod 工作环境。

## 目录结构

```
ModShot-mkxp-z/
├── build/        # 游戏运行器: modshot.exe + modshot.json + 4个DLL (自包含)
├── rmtools/      # mod 编辑工具 (Ruby 脚本)
│   ├── map_tool.rb    # 地图/NPC 编辑工具
│   ├── rxdata_stub.rb # RPG 类桩 (Marshal 读写 .rxdata)
│   ├── verify.rb      # 瓦片完整性/往返验证
│   ├── run_ruby.cmd   # Ruby 启动器 (自动配置 PATH)
│   └── backup/        # 编辑前自动备份
├── runtime/      # Ruby 3.1 运行时 (工具依赖)
│   ├── bin/           # ruby.exe + 动态库
│   └── lib/ruby/      # 标准库
├── engine/       # 引擎源码 + 编译环境 (做 mod 不需要, 可整个删除)
└── modshot.json  # 引擎配置模板 (注释版)
```

## 怎么运行带 mod 的游戏

双击 `build\modshot.exe`。配置在 `build\modshot.json`:
```json
{
    "gameFolder": "C:/Program Files (x86)/Steam/steamapps/common/OneShot",
    "patches": ["mods/MyMod"],
    "preloadScript": ["mods/MyMod/Scripts/mod.rb"]
}
```
mod 文件放在游戏目录 `...\OneShot\mods\MyMod\`, `patches` 使其覆盖原版(最高优先级)。

## 怎么编辑地图/NPC (不用 RMXP)

```
rmtools\run_ruby.cmd map_tool.rb list              # 列出263张地图
rmtools\run_ruby.cmd map_tool.rb dump 4            # 查看地图4的NPC
rmtools\run_ruby.cmd map_tool.rb pull 4            # 复制地图到mod目录
rmtools\run_ruby.cmd map_tool.rb addnpc 4 12 12 新NPC niko "对话"
rmtools\run_ruby.cmd map_tool.rb addmap 新地图 30 20 8
rmtools\run_ruby.cmd map_tool.rb export 4 map.json # 导出JSON任意编辑器改
rmtools\run_ruby.cmd map_tool.rb import 4 map.json
```
默认只写 mod 目录(不碰真实游戏文件); 加 `--game` 才直接改游戏(自动备份)。

## 说明

- 做 mod 只依赖 `build/` `rmtools/` `runtime/`, 其余可删
- `engine/` 是源码归档, 需要重编引擎时再取用或重新 clone
- 参考: modshot.json 注释版在 `engine/` 目录? 否, 顶层就是 (见上)
