/**
 * Native JVM Bridge - thin wrapper for the hmcl_native NAPI module.
 * Uses requireNapi() for runtime loading, with explicit typed wrappers
 * to avoid ArkTS strict mode issues.
 */

declare function requireNapi(name: string): object;
const nativeModule: object = requireNapi('hmcl_native');

interface NativeApi {
  jvmInit(javaHome: string): boolean;
  jvmCheckJitAvailable(): boolean;
  mcLaunch(configJson: string): number;
  mcGetStatus(): number;
  mcIsRunning(): boolean;
  mcForceExit(): void;
  mcReadLog(): string;
  setFilesDir(dir: string): void;
  registerXComponent(xComponentId: string): boolean;
  inputSendCursorPos(x: number, y: number): void;
  inputSendMouseButton(button: number, action: number, mods: number): void;
  inputSendKey(key: number, scancode: number, action: number, mods: number): void;
  inputSendScroll(x: number, y: number): void;
  getGpuInfo(): GpuInfo;
}

const api: NativeApi = nativeModule as NativeApi;

export function jvmInit(javaHome: string): boolean {
  return api.jvmInit(javaHome);
}
export function jvmCheckJitAvailable(): boolean {
  return api.jvmCheckJitAvailable();
}
export function mcLaunch(configJson: string): number {
  return api.mcLaunch(configJson);
}
export function mcGetStatus(): number {
  return api.mcGetStatus();
}
export function mcIsRunning(): boolean {
  return api.mcIsRunning();
}
export function mcForceExit(): void {
  api.mcForceExit();
}
export function mcReadLog(): string {
  return api.mcReadLog();
}
export function setFilesDir(dir: string): void {
  api.setFilesDir(dir);
}
export function registerXComponent(xComponentId: string): boolean {
  return api.registerXComponent(xComponentId);
}
export function inputSendCursorPos(x: number, y: number): void {
  api.inputSendCursorPos(x, y);
}
export function inputSendMouseButton(button: number, action: number, mods: number): void {
  api.inputSendMouseButton(button, action, mods);
}
export function inputSendKey(key: number, scancode: number, action: number, mods: number): void {
  api.inputSendKey(key, scancode, action, mods);
}
export function inputSendScroll(x: number, y: number): void {
  api.inputSendScroll(x, y);
}
export interface GpuInfo {
  name: string;
  vendor: string;
  version: string;
  glVersion: string;
  supportsVulkan: boolean;
}
export function getGpuInfo(): GpuInfo {
  return api.getGpuInfo();
}
