import { AppState, Session, SESSION_RUNNING, SESSION_QUEUED, SESSION_FAILED, SESSION_STOPPED } from '../../service/AppState';
import { InferenceService } from '../../service/InferenceService';
import { ConfirmDialog } from './ConfirmDialog';

@Component
export struct SessionList {
  @ObjectLink appState: AppState;
  onSelect: (id: number) => void = (id: number) => {};
  private inference: InferenceService = InferenceService.getInstance();
  @State renamingId: number = 0;
  @State renameText: string = '';
  @State pendingDeleteId: number = 0;

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
          }, (session: Session) => `${session.id}:${session.status}:${session.updatedAt}:${session.pinned}`)
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
          if (this.renamingId === session.id) {
            TextInput({ text: this.renameText })
              .layoutWeight(1)
              .height(32)
              .fontSize(15)
              .fontColor('#FFFFFF')
              .backgroundColor('#2C2D33')
              .borderRadius(8)
              .padding({ left: 8, right: 8 })
              .onChange((value: string) => { this.renameText = value; })
              .onSubmit(() => this.commitRename(session.id))
              .defaultFocus(true)
          } else {
            Text(session.title)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.appState.activeSessionId === session.id ? '#FFFFFF' : '#C2C2C8')
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (session.status !== 'idle') {
            Text(this.statusLabel(session.status))
              .fontSize(10)
              .fontColor(this.statusColor(session.status))
              .backgroundColor('#25262B')
              .borderRadius(6)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .margin({ left: 8 })
          }
          Button('···')
            .bindMenu([
              { value: '持久化', action: () => this.persist(session) },
              { value: '重命名', action: () => this.beginRename(session) },
              { value: session.pinned ? '取消置顶' : '置顶', action: () => this.inference.togglePin(session.id) },
              { value: '删除', action: () => { this.pendingDeleteId = session.id; } }
            ])
            .width(34)
            .height(28)
            .fontSize(16)
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

  private beginRename(session: Session): void {
    this.renamingId = session.id;
    this.renameText = session.title;
  }

  private commitRename(id: number): void {
    const title = this.renameText.trim();
    if (title.length > 0) {
      this.inference.renameSession(id, title);
    }
    this.renamingId = 0;
  }

  private persist(session: Session): void {
    this.inference.persistSession(session.id);
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
