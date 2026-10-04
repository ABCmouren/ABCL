/**
 * java_tool.h — 在 fork 出的子进程里运行任意 Java 主类
 *
 * 用途：Forge / NeoForge 安装期必须执行的 processors
 * （installertools / jarsplitter / ForgeAutoRenamingTool / binarypatcher …）。
 * 每个 processor 用**只含自己声明的 jar**的干净 classpath 起一个独立 JVM，
 * 避免 installer.jar 里 shaded 的库污染（FCL / HMCL 同款做法，对应 AMCL 的 fork_run_java）。
 */
#ifndef HMCL_JAVA_TOOL_H
#define HMCL_JAVA_TOOL_H

#include <string>
#include <vector>

namespace hmcl {

/**
 * fork 子进程 → dlopen libjvm.so → JNI_CreateJavaVM → 调用 mainClass.main(args)
 *
 * @param javaHome   JDK 根目录（含 lib/server/libjvm.so）
 * @param classpath  Java classpath（':' 分隔）
 * @param mainClass  主类名（点号分隔）
 * @param args       main 的参数
 * @param workDir    子进程 chdir 的目标（空则不改）
 * @param logFile    子进程 stdout/stderr 重定向到的文件（空则继承）
 * @param xmxMb      最大堆
 * @return 子进程退出码；-1 = fork 失败；-2 = 子进程未正常退出
 */
int runJavaTool(const std::string &javaHome,
                const std::string &classpath,
                const std::string &mainClass,
                const std::vector<std::string> &args,
                const std::string &workDir,
                const std::string &logFile,
                int xmxMb);

} // namespace hmcl

#endif // HMCL_JAVA_TOOL_H
