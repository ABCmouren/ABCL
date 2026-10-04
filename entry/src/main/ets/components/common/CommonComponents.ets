// Common UI components for ABCL

// Version type badge component
@Component
export struct VersionBadge {
  @Prop type: string = 'release';

  build() {
    Text(this.getBadgeText())
      .fontSize(10)
      .fontColor(Color.White)
      .backgroundColor(this.getBadgeColor())
      .borderRadius(4)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .margin({ left: 4 });
  }

  getBadgeText(): string {
    switch (this.type) {
      case 'release': return 'Release';
      case 'snapshot': return 'Snapshot';
      case 'old_alpha': return 'Alpha';
      case 'old_beta': return 'Beta';
      default: return this.type;
    }
  }

  getBadgeColor(): ResourceColor {
    switch (this.type) {
      case 'release': return '#107C10';
      case 'snapshot': return '#D83B01';
      case 'old_alpha': return '#881798';
      case 'old_beta': return '#5C6BC0';
      default: return '#666666';
    }
  }
}

// Account type badge component
@Component
export struct AccountTypeBadge {
  @Prop accountType: string = 'offline';

  build() {
    Text(this.getBadgeText())
      .fontSize(10)
      .fontColor(Color.White)
      .backgroundColor(this.getBadgeColor())
      .borderRadius(4)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 });
  }

  getBadgeText(): string {
    switch (this.accountType) {
      case 'microsoft': return 'Microsoft';
      case 'authlib_injector': return 'Authlib';
      case 'offline': return 'Offline';
      default: return this.accountType;
    }
  }

  getBadgeColor(): ResourceColor {
    switch (this.accountType) {
      case 'microsoft': return '#5C6BC0';
      case 'authlib_injector': return '#D83B01';
      case 'offline': return '#666666';
      default: return '#666666';
    }
  }
}

// Loading indicator component
@Component
export struct LoadingView {
  @Prop message: string = 'Loading...';

  build() {
    Column() {
      LoadingProgress()
        .width(32)
        .height(32)
        .color('#5C6BC0');
      Text(this.message)
        .fontSize(14)
        .fontColor('#666666')
        .margin({ top: 12 });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }
}

// Empty state component
@Component
export struct EmptyView {
  @Prop icon: string = '';
  @Prop message: string = 'No items';
  @Prop actionText: string = '';

  build() {
    Column() {
      Image($r('app.media.icon'))
        .width(64)
        .height(64)
        .opacity(0.3);
      Text(this.message)
        .fontSize(16)
        .fontColor('#999999')
        .margin({ top: 16 });
      if (this.actionText.length > 0) {
        Button(this.actionText)
          .margin({ top: 16 })
          .backgroundColor('#5C6BC0')
          .fontColor(Color.White)
          .borderRadius(6);
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }
}

// Progress bar component
@Component
export struct ProgressBar {
  @Prop progress: number = 0;
  @Prop showLabel: boolean = true;

  build() {
    Column() {
      if (this.showLabel) {
        Text(`${Math.round(this.progress * 100)}%`)
          .fontSize(12)
          .fontColor('#666666')
          .margin({ bottom: 4 });
      }
      Stack() {
        // Background track
        Row()
          .width('100%')
          .height(6)
          .backgroundColor('#E0E0E0')
          .borderRadius(3);
        // Foreground fill
        Row()
          .width(`${this.progress * 100}%`)
          .height(6)
          .backgroundColor('#5C6BC0')
          .borderRadius(3);
      }
      .width('100%');
    }
    .width('100%');
  }
}

// Card component
@Component
export struct Card {
  @Prop cardPadding: number = 12;
  @BuilderParam content: () => void = this.emptyBuilder;

  @Builder
  emptyBuilder() {}

  build() {
    Column() {
      this.content();
    }
    .width('100%')
    .backgroundColor(Color.White)
    .borderRadius(8)
    .padding(this.cardPadding)
    .shadow({
      radius: 4,
      color: '#1A000000',
      offsetX: 0,
      offsetY: 2
    });
  }
}

// Section header component
@Component
export struct SectionHeader {
  @Prop title: string = '';
  @Prop actionText: string = '';
  onActionClick: () => void = () => {};

  build() {
    Row() {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A');
      Blank();
      if (this.actionText.length > 0) {
        Text(this.actionText)
          .fontSize(13)
          .fontColor('#5C6BC0')
          .onClick(() => {
            this.onActionClick();
          });
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 });
  }
}

// Search bar component
@Component
export struct SearchBar {
  @State searchText: string = '';
  onSearch: (text: string) => void = (text: string) => {};

  build() {
    Row() {
      Image($r('app.media.icon'))
        .width(16)
        .height(16)
        .opacity(0.4)
        .margin({ left: 8 });
      TextInput({ placeholder: 'Search...', text: this.searchText })
        .layoutWeight(1)
        .fontSize(14)
        .backgroundColor(Color.Transparent)
        .onChange((value: string) => {
          this.searchText = value;
          this.onSearch(value);
        });
    }
    .width('100%')
    .height(36)
    .backgroundColor('#F0F0F0')
    .borderRadius(8)
    .padding({ right: 8 });
  }
}