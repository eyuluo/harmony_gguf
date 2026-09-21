import { AppState, Session, SESSION_RUNNING, SESSION_QUEUED, SESSION_FAILED, SESSION_STOPPED } from '../../service/AppState';
import { InferenceService } from '../../service/InferenceService';
import { ConfirmDialog } from './ConfirmDialog';

@Component
export struct SessionList {
  @ObjectLink appState: AppState;
  onSelect: (id: number) => void = (id: number) => {};
  private inference: InferenceService = InferenceService.getInstance();
  @State expandedId: number = 0;
  @State pendingDeleteId: number = 0;
  @State renameId: number = 0;
  @State renameText: string = '';

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row() {
          Column() {
            Text('对话')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
            Text(`${this.appState.sessions.length} 个会话`)
              .fontSize(12)
              .fontColor('#6C6C6C')
              .margin({ top: 3 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Button('+  新建')
            .enabled(!this.appState.loading)
            .onClick(() => this.createAndSelect())
            .height(40)
            .backgroundColor(this.appState.loading ? '#35343F' : '#6C5CE7')
            .fontColor(this.appState.loading ? '#8F8D98' : '#FFFFFF')
            .borderRadius(12)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 20, bottom: 14 })
        .alignItems(VerticalAlign.Center)

        List() {
          if (this.appState.sessions.length === 0) {
            ListItem() {
              Column() {
                Text('暂无对话')
                  .fontSize(14)
                  .fontColor('#6C6C6C')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 28, bottom: 20 })
            }
          }
          ForEach(this.sortedSessions(), (session: Session) => {
            ListItem() {
              this.sessionItem(session)
            }
          }, (session: Session) => `${session.id}:${session.title}:${session.status}:${session.updatedAt}:${session.pinned}:${session.persistent}`)
        }
        .layoutWeight(1)
        .width('100%')
        .alignListItem(ListItemAlign.Start)
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)

      if (this.pendingDeleteId !== 0) {
        ConfirmDialog({
          title: '删除会话',
          message: '将停止该会话推理，是否删除？',
          confirmText: '删除',
          onCancel: () => { this.pendingDeleteId = 0; },
          onConfirm: () => {
            this.inference.deleteSession(this.pendingDeleteId);
            this.pendingDeleteId = 0;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  sessionItem(session: Session) {
    Row() {
      Column()
        .width(3)
        .height(36)
        .backgroundColor(this.appState.activeSessionId === session.id ? '#7B61FF' : '#00000000')
        .borderRadius(2)
      Column() {
        Row() {
          Text(session.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.appState.activeSessionId === session.id ? '#FFFFFF' : '#C2C2C8')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (session.status !== 'idle') {
            Text(this.statusLabel(session.status))
              .fontSize(10)
              .fontColor(this.statusColor(session.status))
              .backgroundColor('#25262B')
              .borderRadius(6)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .margin({ left: 8 })
          }
          Button(this.expandedId === session.id ? '收起' : '...')
            .onClick(() => this.toggleExpand(session.id))
            .width(30)
            .height(26)
            .fontSize(14)
            .backgroundColor('#00000000')
            .fontColor('#A0A0A0')
            .margin({ left: 6 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row() {
          Text(this.summary(session))
            .fontSize(12)
            .fontColor('#6C6C6C')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.formatTime(session.updatedAt))
            .fontSize(11)
            .fontColor('#5F6068')
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 4 })

          if (this.expandedId === session.id) {
            Flex({ wrap: FlexWrap.Wrap }) {
            if (session.status === SESSION_RUNNING || session.status === SESSION_QUEUED) {
              Button('停止推理')
                .onClick(() => this.inference.stopGeneration(session.id))
                .backgroundColor('#2C2D33')
                .fontColor('#B9B1FF')
                .borderRadius(10)
                .fontSize(12)
            }
            Button(session.persistent ? '取消持久化' : '持久化')
              .onClick(() => this.inference.setPersistent(session.id, !session.persistent))
              .margin({ left: 8 })
              .backgroundColor('#2C2D33')
              .fontColor(session.persistent ? '#B9B1FF' : '#A0A0A0')
              .borderRadius(10)
              .fontSize(12)
            Button('重命名')
              .onClick(() => this.startRename(session))
              .margin({ left: 8 })
              .backgroundColor('#2C2D33')
              .fontColor('#A0A0A0')
              .borderRadius(10)
              .fontSize(12)
            Button(session.pinned ? '取消置顶' : '置顶')
              .onClick(() => this.inference.togglePin(session.id))
              .margin({ left: 8 })
              .backgroundColor('#2C2D33')
              .fontColor('#A0A0A0')
              .borderRadius(10)
              .fontSize(12)
            Button('删除')
              .onClick(() => { this.pendingDeleteId = session.id; })
              .margin({ left: 8 })
              .backgroundColor('#2C2D33')
            .fontColor('#E58C8C')
            .borderRadius(10)
            .fontSize(12)
          }
            .width('100%')
            .margin({ top: 8 })
          if (this.renameId === session.id) {
            Flex({ wrap: FlexWrap.Wrap }) {
              TextInput({ placeholder: '输入会话名称', text: this.renameText })
                .layoutWeight(1)
                .height(36)
                .onChange((value: string) => this.renameText = value)
                .backgroundColor('#1E1F24')
                .fontColor('#FFFFFF')
                .borderRadius(8)
              Button('保存')
                .onClick(() => this.confirmRename(session.id))
                .margin({ left: 8 })
                .height(36)
                .backgroundColor('#6C5CE7')
                .fontColor('#FFFFFF')
                .borderRadius(8)
              Button('取消')
                .onClick(() => this.cancelRename())
                .margin({ left: 8 })
                .height(36)
                .backgroundColor('#2C2D33')
                .fontColor('#A0A0A0')
                .borderRadius(8)
            }
            .width('100%')
            .margin({ top: 8 })
          }
        }
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.appState.activeSessionId === session.id ? '#25262B' : '#00000000')
    .borderRadius(10)
    .onClick(() => this.onSelect(session.id))
  }

  private sortedSessions(): Session[] {
    const list = this.appState.sessions.slice();
    list.sort((a: Session, b: Session) => {
      if (a.pinned !== b.pinned) {
        return a.pinned ? -1 : 1;
      }
      return b.updatedAt - a.updatedAt;
    });
    return list;
  }

  private createAndSelect(): void {
    const id = this.inference.newSession();
    this.onSelect(id);
  }

  private toggleExpand(id: number): void {
    this.expandedId = this.expandedId === id ? 0 : id;
    if (this.expandedId !== id) {
      this.cancelRename();
    }
  }

  private startRename(session: Session): void {
    this.expandedId = session.id;
    this.renameId = session.id;
    this.renameText = session.title;
  }

  private confirmRename(sessionId: number): void {
    const title = this.renameText.trim();
    if (title.length === 0) {
      return;
    }
    this.inference.renameSession(sessionId, title);
    this.cancelRename();
  }

  private cancelRename(): void {
    this.renameId = 0;
    this.renameText = '';
  }

  private statusLabel(status: string): string {
    if (status === SESSION_RUNNING) {
      return '推理中';
    }
    if (status === SESSION_QUEUED) {
      return '排队中';
    }
    if (status === SESSION_FAILED) {
      return '失败';
    }
    if (status === SESSION_STOPPED) {
      return '已停止';
    }
    return '';
  }

  private statusColor(status: string): string {
    if (status === SESSION_RUNNING) {
      return '#B9B1FF';
    }
    if (status === SESSION_QUEUED) {
      return '#E5C07B';
    }
    if (status === SESSION_FAILED) {
      return '#E05858';
    }
    if (status === SESSION_STOPPED) {
      return '#85858D';
    }
    return '#6C6C6C';
  }

  private summary(session: Session): string {
    if (session.messages.length === 0) {
      return '暂无消息';
    }
    const last = session.messages[session.messages.length - 1];
    return last.content.length > 0 ? last.content : '（推理中）';
  }

  private formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const hh = date.getHours() < 10 ? '0' + date.getHours() : String(date.getHours());
    const mm = date.getMinutes() < 10 ? '0' + date.getMinutes() : String(date.getMinutes());
    return hh + ':' + mm;
  }
}
