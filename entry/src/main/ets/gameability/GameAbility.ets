/**
 * GameAbility - Renders Minecraft game view via XComponent
 *
 * Started when user clicks Launch. Receives game installation params
 * via Want, creates the XComponent surface, and triggers JVM launch.
 *
 * Flow: onWindowStageCreate → store params in AppStorage → load GameView
 * GameView captures surfaceId → launches JVM → Minecraft renders here
 */

import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { BusinessError } from '@ohos.base';
import { Logger } from '../core/util/Utils';

export default class GameAbility extends UIAbility {
  private static readonly TAG = 'GameAbility';

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Logger.info(GameAbility.TAG, 'GameAbility onCreate');

    // Store launch parameters where GameView can pick them up
    // GameView reads AppStorage('gameLaunchParams') to know what to launch
    try {
      const params: Record<string, Object> = want.parameters as Record<string, Object>;
      if (params) {
        AppStorage.setOrCreate('gameLaunchParams', JSON.stringify(params));
        Logger.info(GameAbility.TAG, 'Launch params stored in AppStorage');
      }

      // Also read the full launch config set by GameListPage (via pendingGameLaunch)
      // This contains the complete GameInstallation + Account JSON
      const pendingLaunch: string | undefined = AppStorage.get('pendingGameLaunch') as string;
      if (pendingLaunch) {
        AppStorage.setOrCreate('gameLaunchParams', pendingLaunch);
        AppStorage.setOrCreate('pendingGameLaunch', '');
        Logger.info(GameAbility.TAG, 'Full launch config forwarded from pendingGameLaunch');
      }
    } catch (e) {
      Logger.error(GameAbility.TAG, 'Failed to store launch params: ' + (e as Error).message);
    }
  }

  onDestroy(): void {
    Logger.info(GameAbility.TAG, 'GameAbility onDestroy');
    // Clean up AppStorage
    AppStorage.delete('gameLaunchParams');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    Logger.info(GameAbility.TAG, 'GameAbility onWindowStageCreate');

    // Set window to fullscreen landscape for game
    windowStage.getMainWindow().then((win: window.Window) => {
      win.setWindowLayoutFullScreen(true);
      win.setPreferredOrientation(window.Orientation.LANDSCAPE);
      Logger.info(GameAbility.TAG, 'Window set to fullscreen landscape');
    }).catch((err: BusinessError) => {
      Logger.error(GameAbility.TAG, 'Failed to configure window: ' + JSON.stringify(err));
    });

    // Load the game UI page which contains the XComponent render surface
    windowStage.loadContent('pages/game/GameView', (err: BusinessError) => {
      if (err.code) {
        Logger.error(GameAbility.TAG, 'Failed to load GameView: ' + JSON.stringify(err));
      } else {
        Logger.info(GameAbility.TAG, 'GameView loaded successfully');
      }
    });
  }

  onWindowStageDestroy(): void {
    Logger.info(GameAbility.TAG, 'GameAbility onWindowStageDestroy');
  }

  onForeground(): void {
    Logger.info(GameAbility.TAG, 'GameAbility onForeground');
  }

  onBackground(): void {
    Logger.info(GameAbility.TAG, 'GameAbility onBackground');
  }
}
