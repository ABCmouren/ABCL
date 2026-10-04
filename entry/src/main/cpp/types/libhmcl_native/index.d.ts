/**
 * Type declarations for the hmcl_native NAPI module.
 * This module is the native JVM bridge compiled from cpp/ source.
 * At runtime, it's loaded as libhmcl_native.so.
 */

// Direct export form for import { jvmInit } from 'hmcl_native'
export function jvmInit(javaHome: string): boolean;
export function jvmCheckJitAvailable(): boolean;
export function getGpuInfo(): GpuInfo;
export function mcLaunch(configJson: string): number;
export function mcGetStatus(): number;
export function mcIsRunning(): boolean;
export function mcForceExit(): void;
export function mcReadLog(): string;
export function setFilesDir(dir: string): void;
export function registerXComponent(xComponentId: string): boolean;
export function inputSendCursorPos(x: number, y: number): void;
export function inputSendMouseButton(button: number, action: number, mods: number): void;
export function inputSendKey(key: number, scancode: number, action: number, mods: number): void;
export function inputSendScroll(x: number, y: number): void;
/** 在独立子进程里运行一个 Java 主类（Forge/NeoForge 安装期的 processors）。返回子进程退出码。 */
export function runJavaProcessor(javaHome: string, classpath: string, mainClass: string, args: string[], workDir: string, logFile: string, xmxMb: number): Promise<number>;

export interface GpuInfo {
  name: string;
  vendor: string;
  version: string;
  glVersion: string;
  supportsVulkan: boolean;
}

// Also declare as module for import native from 'libhmcl_native.so'
declare module 'libhmcl_native.so' {
  export function jvmInit(javaHome: string): boolean;
  export function jvmCheckJitAvailable(): boolean;
  export function getGpuInfo(): GpuInfo;
  export function mcLaunch(configJson: string): number;
  export function mcGetStatus(): number;
  export function mcIsRunning(): boolean;
  export function mcForceExit(): void;
  export function mcReadLog(): string;
  export function setFilesDir(dir: string): void;
export function registerXComponent(xComponentId: string): boolean;
  export function inputSendCursorPos(x: number, y: number): void;
  export function inputSendMouseButton(button: number, action: number, mods: number): void;
  export function inputSendKey(key: number, scancode: number, action: number, mods: number): void;
  export function inputSendScroll(x: number, y: number): void;
/** 在独立子进程里运行一个 Java 主类（Forge/NeoForge 安装期的 processors）。返回子进程退出码。 */
export function runJavaProcessor(javaHome: string, classpath: string, mainClass: string, args: string[], workDir: string, logFile: string, xmxMb: number): Promise<number>;

  export interface GpuInfo {
    name: string;
    vendor: string;
    version: string;
    glVersion: string;
    supportsVulkan: boolean;
  }
}
