import GameListPage from './main/GameListPage';
import DownloadPage from './download/DownloadPage';
import AccountPage from './account/AccountPage';
import SettingsPage from './settings/SettingsPage';
import ModPage from './mod/ModPage';
import WorldPage from './world/WorldPage';
import ModpackPage from './modpack/ModpackPage';
import { TabConfig } from '../model/TabConfig';

@Entry
@Component
struct Index {
  @State currentTabIndex: number = 0;

  private tabs: TabConfig[] = [
    { title: 'Games', icon: '' },
    { title: 'Download', icon: '' },
    { title: 'Accounts', icon: '' },
    { title: 'Mods', icon: '' },
    { title: 'Worlds', icon: '' },
    { title: 'Modpacks', icon: '' },
    { title: 'Settings', icon: '' }
  ];

  build() {
    Column() {
      // Top title bar
      Row() {
        Text('HMCL')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF');
        Text(' - Hello Minecraft! Launcher')
          .fontSize(13)
          .fontColor('#B0B0B0')
          .margin({ left: 8 });
      }
      .width('100%')
      .height(48)
      .backgroundColor('#1E1E2E')
      .padding({ left: 20 });

      // Tab content area
      Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
        TabContent() {
          GameListPage()
        }
        .tabBar('Games')

        TabContent() {
          DownloadPage()
        }
        .tabBar('Download')

        TabContent() {
          AccountPage()
        }
        .tabBar('Accounts')

        TabContent() {
          ModPage()
        }
        .tabBar('Mods')

        TabContent() {
          WorldPage()
        }
        .tabBar('Worlds')

        TabContent() {
          ModpackPage()
        }
        .tabBar('Modpacks')

        TabContent() {
          SettingsPage()
        }
        .tabBar('Settings')
      }
      .onChange((index: number) => {
        this.currentTabIndex = index;
      })
      .width('100%')
      .height('100%')
      .backgroundColor('#F5F5F5')
      .barWidth('100%')
      .barHeight(48)
      .barMode(BarMode.Fixed)
      .animationDuration(200);
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5');
  }
}