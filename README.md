# skidware split build

功能层（core）与面板层（ui）彻底分开：**core 只跑功能，面板从 GitHub 拉下来后 `mount(core)` 渲染模块设置。**

```
skid-core.lua   本地执行（功能 + 模块注册表 + UI 加载器）
skid-ui.lua     放 GitHub（面板壳，纯 UI，无战斗逻辑）
```

---

## 1. 部署（两步）

### 第一步：把 `skid-ui.lua` 传到仓库

```
你的仓库/
└── skid-ui.lua
```

拿到它的 **raw 链接**（三选一，推荐 raw 或 jsDelivr）：

| 用途 | 链接形态 |
|---|---|
| GitHub raw | `https://raw.githubusercontent.com/<用户名>/<仓库>/main/skid-ui.lua` |
| jsDelivr（国内快、带 CDN） | `https://cdn.jsdelivr.net/gh/<用户名>/<仓库>@main/skid-ui.lua` |
| raw.githack（备用） | `https://raw.githack.com/<用户名>/<仓库>/main/skid-ui.lua` |

> 仓库必须 **public**：raw / jsDelivr 读私有库都要 token，执行器里放 token 等于泄露。

### 第二步：改 `skid-core.lua` 顶部这一处

```lua
local UI_CONFIG = {
    url = "https://raw.githubusercontent.com/USER/REPO/main/skid-ui.lua",
    mirrors = {
        "https://cdn.jsdelivr.net/gh/USER/REPO@main/skid-ui.lua",
        "https://raw.githack.com/USER/REPO/main/skid-ui.lua",
    },
    cache = "skid-ui-cache.lua",
    pin = "",              -- 可选 sha256，防篡改
    preferCache = true,    -- 先挂缓存秒开
    autoUpdate = true,     -- 后台拉新版，版本变了热替换
    retryDelay = 20,
    maxRetries = 3,
    minBytes = 512,
}
```

把 `USER/REPO` 全部替换成你的。**不改也不会崩**：加载器识别到占位地址会直接跳过联网并 warn，功能照常跑（只是没有面板）。

也可以在加载 core 之前用全局变量覆盖，免改文件：

```lua
_G.SKID_UI_URL   = "https://raw.githubusercontent.com/you/repo/main/skid-ui.lua"
_G.SKID_UI_PIN   = "<sha256 十六进制>"     -- 可选
_G.SKID_UI_CACHE = "my-ui-cache.lua"       -- 可选
loadstring(game:HttpGet("https://raw.githubusercontent.com/you/repo/main/skid-core.lua"))()
```

### 运行

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/you/repo/main/skid-core.lua"))()
```

本地有 core 文件时直接执行也行：`autoexec` / 拖进执行器 / `dofile`。

---

## 2. 加载器行为

```
启动 core
 ├─ 读 skid-ui-cache.lua ──有──► 编译并 mount（秒开，离线可用）
 │                                   └─ 后台 pullRemote：版本不同 → unmount 旧壳 + mount 新壳
 ├─ 无缓存 ──► 依次尝试 url / mirrors（HttpGet → httpget → request → GetAsync）
 │              ├─ 成功 → 编译 → mount → 写缓存
 │              └─ 失败 → warn，功能继续跑，后台重试 maxRetries 次
 └─ 全程功能模块不受影响（combat/noclip/cooldown/hud 都在 core 里）
```

要点：

- **UI 挂了不影响功能**：core 不 `Instance.new` 任何 ScreenGui，面板只是可选表现层。
- **缓存优先**：第二次启动不受网络影响；远端更新时热替换，功能状态（配置、冷却、角色）不丢。
- **完整性**：填了 `pin` 且执行器带 `syn.crypt.hash` / `crypt.hash` 时校验 sha256，不匹配就拒绝远端、继续用缓存。
- **坏壳回退**：远端新版本 mount 抛错时，自动退回上一次缓存里的壳并 warn，不会把人晾在无面板状态。
- **版本号**：改完 UI 记得把 `Shell.version` 加 1（如 `1.0.1`），否则同版本不会热替换（只刷新缓存）。
- **缓存刷新**：jsDelivr 对 `@main` 有分钟级缓存，急更就用 `@v1.0.1` 标签或换 raw 链接。

---

## 3. 契约

### 3.1 UI 壳 → core

`skid-ui.lua` 必须 `return` 一张表：

```lua
return {
    version = "1.0.0",
    mount   = function(core) end,   -- 建界面 + 接管 core.api + 订阅总线
    unmount = function() end,       -- 销毁界面 / 断开连接 / core.resetApi()
    refresh = function() end,       -- 按当前配置重画所有控件
}
```

壳只能通过 `core` 拿东西：

| 字段 | 说明 |
|---|---|
| `core.registry.list / byId / get()` | 模块注册表（渲染卡片用） |
| `core.modules` | `byId` 快捷方式 |
| `core.bus` | `on(evt, fn)` / `emit(evt, ...)` |
| `core.store` | `mark()` / `flush()` / `resetAll()` |
| `core.theme` | 配色表 |
| `core.util` | `new/round/stroke/tween/clamp/fmt/deep/getPath/setPath/merge` |
| `core.layout` | 窗口与头顶几何（持久化在 `store.ui`） |
| `core.pill` | 头顶胶囊原语 `build/setScale/alpha/reset` |
| `core.const` | `PILL_W` / `PILL_H` |
| `core.api` | **能力槽**：`toast / setEditMode / toggleEditMode / resetLayout / styleGhost / refresh` |

### 3.2 core → UI 的能力槽

功能模块要“提示/进入编辑模式/刷新面板”时只调 `core.api.*`，没挂 UI 时是空实现：

```lua
core.api.toast("...")         -- 面板不存在时什么都不做
core.api.toggleEditMode()
core.api.styleGhost()
```

壳在 `mount` 里覆盖它们，`unmount` 时 `core.resetApi()` 恢复空实现。

### 3.3 总线事件

| 事件 | 参数 | 谁发 |
|---|---|---|
| `anim` | `animId, track` | CharSvc（唯一监听 AnimationPlayed） |
| `character` | `char` 或 `nil` | CharSvc |
| `cooldown:start` | `duration` | cooldown |
| `module` | `id, enabled` | registry |
| `config` | `id, key, value` | 模块 set |
| `ui:refresh` | — | registry / 功能模块 |
| `store:reset` | — | store.resetAll |
| `layout:reset` | — | core.resetLayoutData |
| `input:resetPos` | — | input 模块 |
| `hud:style` | — | hud 模块 |

---

## 4. 加一个新功能模块

功能层里加一段 `Modules.define`（放在 core 的模块区、启动之前），面板自动出现卡片、开关、持久化、热启用：

```lua
local speed = Modules.define({
    id = "speed",
    title = "Walk speed",
    tab = "Combat",              -- 现有标签，或写新名字（会自动多一个标签页）
    order = 40,
    defaults = { enabled = false, walk = 22 },
    settings = {
        { type = "slider", key = "walk", label = "WalkSpeed", min = 16, max = 80, step = 1, decimals = 0 },
        { type = "button", label = "Apply now", action = "apply" },
    },
})
speed.onEnable = function(self)
    local hum = CharSvc.hum
    if hum then hum.WalkSpeed = self.C.walk end
end
speed.actions.apply = function(self)
    local hum = CharSvc.hum
    if hum then hum.WalkSpeed = self.C.walk end
    Bus.emit("ui:refresh")
end
```

支持的 `settings` 类型：`toggle` / `slider` / `segment` / `keybind` / `button` / `note` / `divider` / `custom`。键名支持点路径（`trigger.delay`），也能用 `get` / `set` 直接绑外部表。

钩子既可以直接写在 `define{}` 里，也可以 define 之后挂到模块对象上（两种都支持）：

```lua
onEnable / onDisable / onChange(key, value) / onTick(dt) / onRender(dt) / init
```

---

## 5. 调试句柄

```lua
_G.SkidwareCore.version
_G.SkidwareCore.uiShell / .uiVersion     -- 当前挂载的壳
_G.SkidwareCore.modules.combat.C         -- 读配置
_G.SkidwareCore.modules.combat.api       -- 调行为
_G.SkidwareCore.bus                      -- on / emit
_G.SkidwareCore.store / .layout
_G.SkidwareCore.pullRemoteUI()           -- 手动拉一次 UI
_G.SkidwareCore.uiConfig                 -- 改运行时 URL / pin
_G.SkidwareDestroy()                     -- 卸载壳 + 停模块 + 断开连接
```

---

## 6. 本地验证

`work/harness_split.lua` 用一套 Roblox API 仿真台（Instance / Signal / UDim2 / Tween / task 调度）真跑两个文件，覆盖四个场景：

| 场景 | 内容 |
|---|---|
| A 正常联网 | 拉取 UI → 编译 → mount → 写缓存；v3 配置迁移；标签/卡片由模块生成；开关、滑块、按键、编辑、缩放、最小化、确认框、恢复默认、落盘 |
| B 断网且无缓存 | UI 不挂载、无 ScreenGui；7 个模块照常跑；头顶计时器（功能层）仍工作 |
| C 只有缓存 | 离线从缓存挂载，面板完整重建 |
| D 占位 URL | 识别 `USER/REPO` → 不发起请求、不误挂载，功能照常 |

```
lua work/harness_split.lua     # 全部 ok 结尾
luac -p skid-core.lua skid-ui.lua
```

---

## 7. 安全提醒

UI 是从网络拉下来 **直接执行** 的代码，等价于把执行权限交给那个链接：

- 只指向**你自己**的仓库；别用别人的 raw 链接、别用短链。
- 公开仓库任何人都能看，但也能被 fork 冒充——认准仓库路径，或填 `pin` 做 sha256 校验。
- 拿到别人的 UI 先读一遍再跑；`pin` 换了内容就必须改，这本身也是一道提醒。
- 本地缓存文件同样会被执行，别手动把它换成来源不明的内容。
