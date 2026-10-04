// Settings page for ABCL
import { LauncherConfig, DefaultConfig, ThemeMode } from '../../model/LauncherConfig';
import { DownloadSource } from '../../model/GameVersion';
import { AppStore } from '../../core/AppStore';
import { SectionHeader, Card } from '../../components/common/CommonComponents';
import { I18n } from '../../core/i18n/I18n';
import { ModLoaderInstaller } from '../../core/game/ModLoaderInstaller';
import { DownloadSettings } from '../../core/download/DownloadSettings';

@Component
export default struct SettingsPage {
  @State config: LauncherConfig = DefaultConfig;
  @State currentTheme: string = 'system';
  @State customJavaPath: string = '';
  @State minMemory: number = 1024;
  @State maxMemory: number = 4096;
  @State jvmArgs: string = '';
  @State downloadSource: string = 'bmclapi';
  @State downloadThreads: number = 4;
  @State closeOnLaunch: boolean = false;
  @State showGameLog: boolean = true;
  @State locale: string = 'zh-CN';
  @State proxy: string = '';
  @State isolationType: string = 'modded';

  private store = AppStore.getInstance();

  aboutToAppear(): void {
    this.config = this.store.config;
    this.currentTheme = this.config.theme;
    this.customJavaPath = this.config.javaPath;
    this.minMemory = this.config.defaultMinMemory;
    this.maxMemory = this.config.defaultMaxMemory;
    this.jvmArgs = this.config.javaArgs;
    this.downloadSource = this.config.downloadSource;
    this.downloadThreads = this.config.downloadThreads;
    this.closeOnLaunch = this.config.closeLauncherOnLaunch;
    this.showGameLog = this.config.showGameLog;
    this.locale = this.config.language;
    this.proxy = this.config.proxy;
    this.isolationType = this.config.isolationType;
  }

  saveConfig(): void {
    this.store.updateConfig({
      theme: this.currentTheme === 'light' ? ThemeMode.LIGHT : this.currentTheme === 'dark' ? ThemeMode.DARK : ThemeMode.SYSTEM,
      javaPath: this.customJavaPath,
      defaultMinMemory: this.minMemory,
      defaultMaxMemory: this.maxMemory,
      javaArgs: this.jvmArgs,
      downloadSource: this.downloadSource === 'mojang' ? DownloadSource.MOJANG : this.downloadSource === 'mcbbs' ? DownloadSource.MCBBS : DownloadSource.BMCLAPI,
      downloadThreads: this.downloadThreads,
      closeLauncherOnLaunch: this.closeOnLaunch,
      showGameLog: this.showGameLog,
      language: this.locale,
      proxy: this.proxy,
      isolationType: this.isolationType
    });
    // 语言切了要立刻生效
    I18n.setLocale(this.locale === 'en-US' ? 'en-US' : 'zh-CN');
    // 下载相关设置改完同步给安装器与下载引擎
    ModLoaderInstaller.getInstance().syncDownloadSettings();
    DownloadSettings.sync();
    this.showApplyNote = true;
  }

  @State showApplyNote: boolean = false;

  private isolationTypeLabel(): string {
    if (this.isolationType === 'always') {
      return '总是隔离';
    }
    if (this.isolationType === 'never') {
      return '从不隔离';
    }
    return '仅模组实例（默认）';
  }

  private currentDownloadSummary(): string {
    return DownloadSettings.describe();
  }

  build() {
    Column() {
      Text('Settings')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 8 });

      Scroll() {
        Column() {
          // Launcher settings
          SectionHeader({ title: 'Launcher' });
          Card() {
            Column() {
              // 语言
              this.SettingRow('语言 / Language', '');
              Row({ space: 8 }) {
                this.LocaleOption('简体中文', 'zh-CN');
                this.LocaleOption('English', 'en-US');
              }
              .width('100%')

              // 主题
              this.SettingRow('主题 / Theme', '');
              Row({ space: 8 }) {
                this.ThemeOption('浅色', 'light');
                this.ThemeOption('深色', 'dark');
                this.ThemeOption('跟随系统', 'system');
              }
              .width('100%')

              // 版本隔离
              this.SettingRow('版本隔离 / Version Isolation', this.isolationTypeLabel());
              Row({ space: 8 }) {
                this.IsolationOption('总是隔离', 'always');
                this.IsolationOption('仅模组实例', 'modded');
                this.IsolationOption('从不隔离', 'never');
              }
              .width('100%')
              Text('「仅模组实例」= HMCL 默认：装了 Forge/Fabric 的实例独立目录，原版共享，' +
                '避免原版重复占几 GB。切换后对之后新建的实例生效。')
                .fontSize(10)
                .fontColor('#888888')
                .width('100%')
                .margin({ top: 4 })
              .margin({ top: 8 });

              Divider().height(1).color('#E0E0E0').margin({ top: 12, bottom: 12 });

              // Download source
              this.SettingRow('Download Source', '');
              Row({ space: 8 }) {
                this.DownloadSourceOption('Mojang', 'mojang');
                this.DownloadSourceOption('BMCLAPI', 'bmclapi');
                this.DownloadSourceOption('MCBBS', 'mcbbs');
              }
              .width('100%')
              .margin({ top: 8 });

              Divider().height(1).color('#E0E0E0').margin({ top: 12, bottom: 12 });

              // Download threads
              this.SettingRow('Download Threads', `${this.downloadThreads}`);
              Slider({
                value: this.downloadThreads,
                min: 1,
                max: 16,
                step: 1,
                style: SliderStyle.OutSet
              })
              .width('100%')
              .blockColor('#5C6BC0')
              .trackColor('#E0E0E0')
              .selectedColor('#5C6BC0')
              .onChange((value: number) => {
                this.downloadThreads = value;
                this.saveConfig();
              });

              Divider().height(1).color('#E0E0E0').margin({ top: 12, bottom: 12 });

              // Close on launch
              Row() {
                Text('Close launcher on game start')
                  .fontSize(14)
                  .fontColor('#1A1A1A');
                Blank();
                Toggle({ type: ToggleType.Switch, isOn: this.closeOnLaunch })
                  .selectedColor('#5C6BC0')
                  .onChange((value: boolean) => {
                    this.closeOnLaunch = value;
                    this.saveConfig();
                  });
              }
              .width('100%');

              Divider().height(1).color('#E0E0E0').margin({ top: 12, bottom: 12 });

              // Show game log
              Row() {
                Text('Show game log')
                  .fontSize(14)
                  .fontColor('#1A1A1A');
                Blank();
                Toggle({ type: ToggleType.Switch, isOn: this.showGameLog })
                  .selectedColor('#5C6BC0')
                  .onChange((value: boolean) => {
                    this.showGameLog = value;
                    this.saveConfig();
                  });
              }
              .width('100%');
            }
            .width('100%');
          };

          // Java settings
          SectionHeader({ title: 'Java' });
          Card() {
            Column() {
              this.SettingRow('Java Path', '');
              TextInput({ placeholder: 'Auto-detect or enter path', text: this.customJavaPath })
                .width('100%')
                .height(36)
                .fontSize(14)
                .backgroundColor('#FBF8FF')
                .borderRadius(6)
                .padding({ left: 12 })
                .onChange((value: string) => {
                  this.customJavaPath = value;
                  this.saveConfig();
                });

              Divider().height(1).color('#E0E0E0').margin({ top: 12, bottom: 12 });

              this.SettingRow('Min Memory', `${this.minMemory} MB`);
              Slider({
                value: this.minMemory,
                min: 256,
                max: 8192,
                step: 256,
                style: SliderStyle.OutSet
              })
              .width('100%')
              .blockColor('#5C6BC0')
              .trackColor('#E0E0E0')
              .selectedColor('#5C6BC0')
              .onChange((value: number) => {
                this.minMemory = value;
                this.saveConfig();
              });

              Divider().height(1).color('#E0E0E0').margin({ top: 12, bottom: 12 });

              this.SettingRow('Max Memory', `${this.maxMemory} MB`);
              Slider({
                value: this.maxMemory,
                min: 512,
                max: 16384,
                step: 512,
                style: SliderStyle.OutSet
              })
              .width('100%')
              .blockColor('#5C6BC0')
              .trackColor('#E0E0E0')
              .selectedColor('#5C6BC0')
              .onChange((value: number) => {
                this.maxMemory = value;
                this.saveConfig();
              });

              Divider().height(1).color('#E0E0E0').margin({ top: 12, bottom: 12 });

              this.SettingRow('JVM Arguments', '');
              TextArea({ placeholder: 'Additional JVM arguments', text: this.jvmArgs })
                .width('100%')
                .height(60)
                .fontSize(13)
                .backgroundColor('#FBF8FF')
                .borderRadius(6)
                .padding({ left: 12 })
                .onChange((value: string) => {
                  this.jvmArgs = value;
                  this.saveConfig();
                });
            }
            .width('100%');
          };

          // About section
          SectionHeader({ title: 'About' });
          Card() {
            Column() {
              this.InfoRowStatic('ABCL', 'v2.0.0');
              this.InfoRowStatic('Developer', 'Ported from HMCL');
              this.InfoRowStatic('License', 'GPL-3.0');
              this.InfoRowStatic('Source', 'github.com/ABCmouren/ABCL');
            }
            .width('100%');
          };

          // Bottom padding
          Row().height(40);
        }
        .width('100%')
        .padding({ left: 16, right: 16 });
      }
      .layoutWeight(1);
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FBF8FF');
  }

  @Builder
  SettingRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#1A1A1A');
      Blank();
      if (value) {
        Text(value)
          .fontSize(13)
          .fontColor('#666666');
      }
    }
    .width('100%');
  }

  @Builder
  InfoRowStatic(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#666666');
      Blank();
      Text(value)
        .fontSize(14)
        .fontColor('#1A1A1A')
        .fontWeight(FontWeight.Medium);
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 });
  }

  @Builder
  @Builder
  LocaleOption(label: string, code: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.locale === code ? Color.White : '#666666')
      .backgroundColor(this.locale === code ? '#5C6BC0' : '#E8E8E8')
      .borderRadius(6)
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .onClick(() => {
        this.locale = code;
        this.saveConfig();
      });
  }

  @Builder
  IsolationOption(label: string, type: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.isolationType === type ? Color.White : '#666666')
      .backgroundColor(this.isolationType === type ? '#5C6BC0' : '#E8E8E8')
      .borderRadius(6)
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .onClick(() => {
        this.isolationType = type;
        this.saveConfig();
      });
  }

  @Builder
  ThemeOption(label: string, type: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.currentTheme === type ? Color.White : '#666666')
      .backgroundColor(this.currentTheme === type ? '#5C6BC0' : '#E8E8E8')
      .borderRadius(6)
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .onClick(() => {
        this.currentTheme = type;
        this.saveConfig();
      });
  }

  @Builder
  DownloadSourceOption(label: string, type: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.downloadSource === type ? Color.White : '#666666')
      .backgroundColor(this.downloadSource === type ? '#5C6BC0' : '#E8E8E8')
      .borderRadius(6)
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .onClick(() => {
        this.downloadSource = type;
        this.saveConfig();
      });
  }
}