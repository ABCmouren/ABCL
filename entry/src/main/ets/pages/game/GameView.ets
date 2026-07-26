/**
 * GameView - Minecraft Game Rendering Surface
 *
 * Provides the XComponent surface that LWJGL renders to.
 * Flow:
 *   1. XComponent creates native surface → loads hmcl_native library
 *   2. After surface is ready, get surfaceId from controller
 *   3. Register surfaceId with LaunchEngine (passes to native/AmclLauncher)
 *   4. LaunchEngine reads pending launch params (set by GameListPage)
 *   5. JVM starts, AmclLauncher binds LWJGL to this surface via OH_NativeWindow
 */

import { LaunchEngine } from '../../core/launch/LaunchEngine';
import { Logger } from '../../core/util/Utils';

const TAG = 'GameView';

@Entry
@Component
struct GameView {
  private xcCtrl: XComponentController = new XComponentController();
  private launchEngine: LaunchEngine = LaunchEngine.getInstance();

  @State private statusText: string = 'Preparing render surface...';
  @State private showLoading: boolean = true;

  aboutToAppear(): void {
    Logger.info(TAG, 'aboutToAppear - GameView starting');
    // Wait for XComponent to be laid out and surface to be created
    this.waitForSurface();
  }

  /**
   * Poll for XComponent surfaceId, then trigger game launch.
   * Surface becomes available after the component is laid out
   * and the native library (hmcl_native) has been loaded.
   */
  private waitForSurface(): void {
    let attempts = 0;
    const maxAttempts = 30; // 30 * 300ms ≈ 9 seconds max wait

    const check = (): void => {
      attempts++;
      try {
        const surfaceId: string = this.xcCtrl.getXComponentSurfaceId();
        if (surfaceId && surfaceId.length > 0) {
          Logger.info(TAG, `XComponent surface ready: ${surfaceId.substring(0, 16)}...`);
          this.statusText = 'Render surface ready, launching game...';
          this.onSurfaceReady(surfaceId);
          return;
        }
      } catch (e) {
        Logger.warn(TAG, `Surface check attempt ${attempts} failed: ${(e as Error).message}`);
      }

      if (attempts < maxAttempts) {
        setTimeout(check, 300);
      } else {
        Logger.error(TAG, 'Surface not ready after max attempts, launching anyway');
        this.statusText = 'Surface timeout, attempting launch...';
        this.onSurfaceReady('');
      }
    };

    setTimeout(check, 200); // First check after 200ms (allow layout to happen)
  }

  private onSurfaceReady(surfaceId: string): void {
    // Register XComponent surface with native layer
    if (surfaceId.length > 0) {
      this.launchEngine.registerXComponent(surfaceId);
    }

    // Read pending launch config from AppStorage
    // Set by GameListPage via pendingGameLaunch, forwarded by GameAbility to gameLaunchParams
    const pendingJson: string | undefined = AppStorage.get('gameLaunchParams') as string;
    if (!pendingJson || pendingJson.length === 0) {
      Logger.error(TAG, 'No game launch config found in AppStorage');
      this.statusText = 'Error: No launch configuration';
      return;
    }

    // Offload launch to next tick (don't block rendering)
    setTimeout(() => {
      this.launchEngine.launchFromPending(pendingJson);
      this.showLoading = false;
    }, 100);
  }

  build() {
    Stack() {
      // The rendering surface - LWJGL renders to this via OH_NativeWindow
      XComponent({
        id: 'gs',
        type: XComponentType.SURFACE,
        libraryname: 'hmcl_native',
        controller: this.xcCtrl,
      })
        .width('100%')
        .height('100%');

      // Loading overlay shown until game window takes over
      if (this.showLoading) {
        Column() {
          Text('Starting Minecraft...')
            .fontSize(18)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold);
          Text(this.statusText)
            .fontSize(14)
            .fontColor('#CCCCCC')
            .margin({ top: 12 });
          LoadingProgress()
            .width(48)
            .height(48)
            .color(Color.White)
            .margin({ top: 24 });
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#1A1A1A')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      }
    }
    .width('100%')
    .height('100%');
  }
}
