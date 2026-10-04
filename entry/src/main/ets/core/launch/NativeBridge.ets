/**
 * Native JVM Bridge - hmcl_native NAPI 模块的薄封装。
 *
 * 2026-10 修复：原来用 `requireNapi('hmcl_native')` 在模块顶层加载 native 模块。
 * 实测在 HarmonyOS 6.1.1 上 `requireNapi` 返回的是空对象（hilog 里看不到任何来自
 * libhmcl_native.so 的日志），于是 NativeBridge 里所有调用都抛 TypeError，
 * 被 LaunchEngine 的 try/catch 吞掉 —— 结果是 native JVM 通道从来没生效过，
 * Forge 的 processors 也拿不到 runJavaProcessor。
 *
 * 现在改用 DevEco 规范的 ES 导入形式（对应 cpp/types/libhmcl_native/package.json）。
 */
import {
  jvmInit as nativeJvmInit,
  jvmCheckJitAvailable as nativeCheckJit,
  mcLaunch as nativeMcLaunch,
  mcGetStatus as nativeMcGetStatus,
  mcIsRunning as nativeMcIsRunning,
  mcForceExit as nativeMcForceExit,
  mcReadLog as nativeMcReadLog,
  setFilesDir as nativeSetFilesDir,
  registerXComponent as nativeRegisterXComponent,
  inputSendCursorPos as nativeInputCursorPos,
  inputSendMouseButton as nativeInputMouseButton,
  inputSendKey as nativeInputKey,
  inputSendScroll as nativeInputScroll,
  runJavaProcessor as nativeRunJavaProcessor
} from 'libhmcl_native.so';

export interface GpuInfo {
  name: string;
  vendor: string;
  version: string;
  glVersion: string;
  supportsVulkan: boolean;
}

export function jvmInit(javaHome: string): boolean {
  return nativeJvmInit(javaHome);
}

export function jvmCheckJitAvailable(): boolean {
  return nativeCheckJit();
}

export function mcLaunch(configJson: string): number {
  return nativeMcLaunch(configJson);
}

export function mcGetStatus(): number {
  return nativeMcGetStatus();
}

export function mcIsRunning(): boolean {
  return nativeMcIsRunning();
}

export function mcForceExit(): void {
  nativeMcForceExit();
}

export function mcReadLog(): string {
  return nativeMcReadLog();
}

export function setFilesDir(dir: string): void {
  nativeSetFilesDir(dir);
}

export function registerXComponent(xComponentId: string): boolean {
  return nativeRegisterXComponent(xComponentId);
}

export function inputSendCursorPos(x: number, y: number): void {
  nativeInputCursorPos(x, y);
}

export function inputSendMouseButton(button: number, action: number, mods: number): void {
  nativeInputMouseButton(button, action, mods);
}

export function inputSendKey(key: number, scancode: number, action: number, mods: number): void {
  nativeInputKey(key, scancode, action, mods);
}

export function inputSendScroll(x: number, y: number): void {
  nativeInputScroll(x, y);
}

export function runJavaProcessor(
  javaHome: string,
  classpath: string,
  mainClass: string,
  args: string[],
  workDir: string,
  logFile: string,
  xmxMb: number
): Promise<number> {
  return nativeRunJavaProcessor(javaHome, classpath, mainClass, args, workDir, logFile, xmxMb);
}

/**
 * GPU 信息（诊断用，不在启动关键路径上）。
 * native 的 getGpuInfo 返回的是 .so 自己声明的结构体类型，ArkTS 侧直接映射会踩
 * arkts-no-any-unknown，这里保留占位实现，避免为了诊断信息拖垮主链路。
 */
export function getGpuInfo(): GpuInfo {
  const info: GpuInfo = {
    name: 'unknown',
    vendor: 'unknown',
    version: 'unknown',
    glVersion: 'unknown',
    supportsVulkan: false
  };
  return info;
}
