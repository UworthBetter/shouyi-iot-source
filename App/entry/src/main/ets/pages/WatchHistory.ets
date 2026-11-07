import { AppColor, AppSize } from '../common/constants/ThemeColors';
import { WatchHistoryApi, WatchLogin, WatchRecord } from '../cloud/WatchHistoryApi';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';

@Entry
@Component
struct WatchHistory {
  private readonly metrics: string[] = ['rate', 'spo2', 'temp', 'blood', 'steps'];
  private readonly labels: string[] = ['心率', '血氧', '体温', '血压', '步数'];
  private readonly units: string[] = [' 次/分', '%', ' °C', ' mmHg', ' 步'];
  private captchaId: string = '';
  @State signedIn: boolean = false;
  @State username: string = '';
  @State password: string = '';
  @State captchaCode: string = '';
  @State captchaImage: PixelMap | undefined = undefined;
  @State captchaRequired: boolean = true;
  @State metricIndex: number = 0;
  @State page: number = 1;
  @State total: number = 0;
  @State rows: WatchRecord[] = [];
  @State busy: boolean = false;
  @State error: string = '';

  aboutToAppear(): void {
    this.signedIn = WatchHistoryApi.isSignedIn();
    if (this.signedIn) {
      this.loadPage(1);
    } else {
      this.refreshCaptcha();
    }
  }

  private async refreshCaptcha(): Promise<void> {
    this.busy = true;
    this.captchaId = '';
    this.captchaImage = undefined;
    this.captchaCode = '';
    try {
      const captcha = await WatchHistoryApi.captcha();
      this.captchaRequired = captcha.captchaEnabled;
      if (captcha.captchaEnabled && captcha.img && captcha.uuid) {
        const bytes = new util.Base64Helper().decodeSync(captcha.img);
        const source = image.createImageSource(bytes.buffer);
        try {
          this.captchaImage = await source.createPixelMap();
          this.captchaId = captcha.uuid;
        } finally {
          await source.release();
        }
      }
    } catch (_) {
      this.error = '验证码加载失败，请点刷新重试';
    } finally {
      this.busy = false;
    }
  }

  private async signIn(): Promise<void> {
    this.busy = true;
    this.error = '';
    const credentials: WatchLogin = {
      username: this.username.trim(),
      password: this.password,
      code: this.captchaCode.trim(),
      uuid: this.captchaId
    };
    try {
      await WatchHistoryApi.login(credentials);
      this.signedIn = true;
    } catch (err) {
      this.error = (err as Error).message;
    } finally {
      this.password = '';
      this.busy = false;
    }
    if (this.signedIn) {
      await this.loadPage(1);
    } else {
      await this.refreshCaptcha();
    }
  }

  private async loadPage(page: number): Promise<void> {
    this.busy = true;
    this.error = '';
    this.rows = [];
    this.total = 0;
    try {
      const data = await WatchHistoryApi.history(this.metrics[this.metricIndex], page);
      this.rows = data.rows;
      this.total = data.total;
      this.page = page;
    } catch (err) {
      this.error = (err as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private recordValue(row: WatchRecord): string {
    if (this.metricIndex === 3) {
      return row.systolic != null && row.diastolic != null ? `${row.systolic}/${row.diastolic} mmHg` : '—';
    }
    return row.value != null ? `${row.value}${this.units[this.metricIndex]}` : '—';
  }

  private recordTime(row: WatchRecord): string {
    if (this.metricIndex === 4) {
      return (row.date ?? row.dateTime ?? '日期未知').slice(0, 10);
    }
    return row.createTime ?? '记录时间未知';
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Button('返回', { type: ButtonType.Normal })
          .backgroundColor(AppColor.SURFACE).fontColor(AppColor.PRIMARY)
          .onClick(() => this.getUIContext().getRouter().back())
        Text('手表历史')
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(AppColor.TEXT)
          .layoutWeight(1).margin({ left: 12 })
        if (this.signedIn) {
          Button('退出登录', { type: ButtonType.Normal })
            .backgroundColor(AppColor.SURFACE).fontColor(AppColor.PRIMARY).enabled(!this.busy)
            .onClick(() => {
              WatchHistoryApi.signOut();
              this.signedIn = false;
              this.rows = [];
              this.total = 0;
              this.error = '';
              this.refreshCaptcha();
            })
        }
      }.width('100%')
      Text('数据来源：耆康云盾 · 手表尾号 1265')
        .width('100%').fontSize(14).fontColor(AppColor.TEXT_2)
      if (!this.signedIn) {
        this.loginForm()
      } else {
        this.historyList()
      }
      if (this.error.length > 0) {
        Text(this.error).width('100%').fontSize(14).fontColor(AppColor.DANGER)
      }
    }
    .width('100%').height('100%').alignItems(HorizontalAlign.Start)
    .padding(AppSize.PAGE_PADDING).backgroundColor(AppColor.BG)
  }

  @Builder
  loginForm() {
    Column({ space: 12 }) {
      Text('使用有体征历史查看权限的耆康云盾账号登录')
        .fontSize(14).fontColor(AppColor.TEXT_2).width('100%')
      TextInput({ placeholder: '耆康云盾账号', text: this.username })
        .enabled(!this.busy).onChange((value: string) => this.username = value)
      TextInput({ placeholder: '密码', text: this.password })
        .type(InputType.Password).enabled(!this.busy).onChange((value: string) => this.password = value)
      if (this.captchaRequired) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '验证码', text: this.captchaCode })
            .layoutWeight(1).enabled(!this.busy).onChange((value: string) => this.captchaCode = value)
          if (this.captchaImage !== undefined) {
            Image(this.captchaImage).width(100).height(38).objectFit(ImageFit.Contain)
          }
          Button('刷新').enabled(!this.busy).onClick(() => {
            this.error = '';
            this.refreshCaptcha();
          })
        }.width('100%')
      }
      Button(this.busy ? '处理中…' : '登录并查看')
        .width('100%').backgroundColor(AppColor.PRIMARY)
        .enabled(!this.busy && this.username.trim().length > 0 && this.password.length > 0 &&
          (!this.captchaRequired || (this.captchaId.length > 0 && this.captchaCode.trim().length > 0)))
        .onClick(() => this.signIn())
    }.width('100%').padding(16).backgroundColor(AppColor.CARD).borderRadius(AppSize.CARD_RADIUS)
      .shadow({
        radius: AppSize.SHADOW_RADIUS,
        color: AppSize.SHADOW_COLOR,
        offsetY: AppSize.SHADOW_OFFSET_Y
      })
  }

  @Builder
  historyList() {
    Row({ space: 8 }) {
      Select([{ value: '心率' }, { value: '血氧' }, { value: '体温' }, { value: '血压' }, { value: '步数' }])
        .selected(this.metricIndex).value(this.labels[this.metricIndex]).enabled(!this.busy)
        .onSelect((index: number) => {
          this.metricIndex = index;
          this.loadPage(1);
        })
      Button('刷新记录').enabled(!this.busy).onClick(() => this.loadPage(1))
    }.width('100%').justifyContent(FlexAlign.SpaceBetween)
    Text(this.busy ? '正在读取历史…' : this.metricIndex === 4 ? `按日统计 · 共 ${this.total} 条` :
      `按后台记录时间显示 · 共 ${this.total} 条`)
      .fontSize(13).fontColor(AppColor.TEXT_2)
    if (!this.busy && this.error.length === 0 && this.rows.length === 0) {
      Text('该设备暂无此项历史记录').fontSize(14).fontColor(AppColor.TEXT_2)
    }
    List({ space: 6 }) {
      ForEach(this.rows, (row: WatchRecord) => {
        ListItem() {
          Row() {
            Text(this.recordTime(row)).fontSize(14).fontColor(AppColor.TEXT_2).layoutWeight(1)
            Text(this.recordValue(row)).fontSize(16).fontWeight(FontWeight.Medium).fontColor(AppColor.TEXT)
          }.width('100%').padding(12).backgroundColor(AppColor.CARD).borderRadius(12)
            .shadow({
              radius: AppSize.SHADOW_RADIUS,
              color: AppSize.SHADOW_COLOR,
              offsetY: AppSize.SHADOW_OFFSET_Y
            })
        }
      }, (row: WatchRecord) => `${this.metricIndex}-${row.id}`)
    }.width('100%').layoutWeight(1)
    if (this.total > WatchHistoryApi.PAGE_SIZE) {
      Row({ space: 12 }) {
        Button('上一页').enabled(!this.busy && this.page > 1).onClick(() => this.loadPage(this.page - 1))
        Text(`${this.page} / ${Math.ceil(this.total / WatchHistoryApi.PAGE_SIZE)}`)
          .fontColor(AppColor.TEXT_2)
        Button('下一页').enabled(!this.busy && this.page * WatchHistoryApi.PAGE_SIZE < this.total)
          .onClick(() => this.loadPage(this.page + 1))
      }.width('100%').justifyContent(FlexAlign.Center)
    }
  }
}
