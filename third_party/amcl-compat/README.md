# amcl-compat — 设备兼容层（第三方源码）

鸿蒙设备上的图形兼容层，是 Minecraft 在 HarmonyOS 上正常渲染的关键。
本目录保存其**源码**，编译产物不进版本库。

## 来源与许可

| 项 | 值 |
|---|---|
| 上游 | [`LZZLHY/amcl`](https://github.com/LZZLHY/amcl) |
| commit | `19bf1b3ec9df5006d1dee03e25a94507ed08f5a5` |
| 许可 | GPL-3.0 |
| 源码 | `lib/com/amcl/launcher/*.java`（18 个文件） |

包名保留 `com.amcl.launcher`，便于与上游逐字对照。
本层为 GPL-3.0 第三方代码，许可全文见项目根目录 `LICENSE`。

## 它做什么

1. **替换系统类加载器**（`-Djava.system.class.loader`）：
   `AmclClassLoader` 在 `findClass` 时对特定类做字节码改写。
2. **地形渲染适配**：补丁器只有两个原语 ——
   `patchInvocation`（把对 `Owner.name(desc)` 的调用重定向到本层 helper）、
   `patchLongConstantLoads`（改写方法内的 `ldc2_w` / `iconst_N` 常量）。
   据此做的修正例如：地形上传从「帧末」挪到「下一帧起始」
   （`uploadTerrainBuffersToGpu` → `deferFrameEndUpload`），
   以及提交缓冲深度 2 → 4（缓解鸿蒙驱动延迟）。
3. **Forge 预处理**：`fml.toml` / `splash.properties`，并设置 context ClassLoader。
4. 辅助组件：区块包配额、渲染档位判定、若干诊断探针。

### 补丁按构建门控（安全设计）

补丁前先校验目标类，不匹配则原样放行：

- `isExpectedClass(className, classBytes)` —— SHA-256 比对
- `probeStructuralCriteria(...)` —— 结构判据（调用点数量、字段读取、容量守卫）

宁可少修，也不在没把握的构建上动手；因此只对已审定的 Minecraft 构建生效，
其它版本自动退化为原版行为。

## 编译

```bash
JAVA_HOME=/path/to/jdk ./third_party/amcl-compat/build.sh
```

产出 `entry/src/main/resources/rawfile/amcl-launcher.jar`（已在 `.gitignore` 中忽略）。
构建 HAP 前跑一次即可；该 jar 完全从上面的源码重建。

## 本项目如何使用它

**它不参与启动核心。** 启动流程由本项目自己实现：

- classpath 由本项目从版本清单解析，入口类沿 `inheritsFrom` 链确定
- 本项目经 JNI 调用 `<mainClass>.main(String[])`

兼容层只被调用 `prepare(json)`（完成类加载器接管与上述预处理），
它的 `main()` **不会被调用**。

未找到该 jar 时，native 侧自动禁用本层并以原版行为启动（日志会标注）。