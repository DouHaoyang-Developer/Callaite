import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { AppState } from '../../state/AppState';
import { PropertyEngine, PropertyType } from '../../core/engine/PropertyEngine';

/**
 * 属性类型选项（用于添加属性对话框中的类型选择按钮）。
 */
interface TypeOption {
  type: PropertyType;
  label: string;
}

/**
 * PropertyEditor — 属性编辑器面板。
 *
 * 对应 Logseq 的属性编辑面板。
 * 支持 6 种属性类型：TEXT / NUMBER / CHECKBOX / DATE / TAGS / LIST。
 * 通过 PropertyEngine 进行属性的 CRUD 操作。
 */
@Component
export struct PropertyEditor {
  @Prop @Watch('onBlockChanged') blockUuid: string = '';
  @State properties: Map<string, string> = new Map<string, string>();
  @State propertyKeys: string[] = [];
  @State showAddDialog: boolean = false;
  @State newPropName: string = '';
  @State newPropType: PropertyType = PropertyType.TEXT;

  aboutToAppear(): void {
    this.refreshProperties();
  }

  /**
   * blockUuid 变化时重新加载属性。
   */
  onBlockChanged(): void {
    this.refreshProperties();
  }

  /**
   * 从 PropertyEngine 加载当前 Block 的所有属性。
   */
  refreshProperties(): void {
    const engine = PropertyEngine.getInstance();
    this.properties = engine.getAllProperties(this.blockUuid);
    const keys: string[] = [];
    this.properties.forEach((value: string, key: string) => {
      keys.push(key);
    });
    this.propertyKeys = keys;
  }

  getPropertyValue(key: string): string {
    return this.properties.get(key) ?? '';
  }

  /**
   * 获取属性类型。若已注册 Schema 则返回 Schema 类型，否则默认 TEXT。
   */
  getPropertyType(key: string): PropertyType {
    const schema = PropertyEngine.getInstance().getSchema(key);
    if (schema) {
      return schema.type;
    }
    return PropertyType.TEXT;
  }

  /**
   * 更新属性值（不刷新列表，避免 TextInput 失焦）。
   */
  updateProperty(key: string, value: string): void {
    PropertyEngine.getInstance().setProperty(this.blockUuid, key, value);
    AppState.bumpBlocksVersion();
  }

  /**
   * 更新属性值并刷新列表（用于 Toggle / DatePicker 等离散操作）。
   */
  updatePropertyAndRefresh(key: string, value: string): void {
    PropertyEngine.getInstance().setProperty(this.blockUuid, key, value);
    AppState.bumpBlocksVersion();
    this.refreshProperties();
  }

  removeProperty(key: string): void {
    PropertyEngine.getInstance().removeProperty(this.blockUuid, key);
    AppState.bumpBlocksVersion();
    this.refreshProperties();
  }

  getTypeOptions(): TypeOption[] {
    const options: TypeOption[] = [];
    options[0] = { type: PropertyType.TEXT, label: '文本' };
    options[1] = { type: PropertyType.NUMBER, label: '数字' };
    options[2] = { type: PropertyType.CHECKBOX, label: '勾选' };
    options[3] = { type: PropertyType.DATE, label: '日期' };
    options[4] = { type: PropertyType.TAGS, label: '标签' };
    options[5] = { type: PropertyType.LIST, label: '列表' };
    return options;
  }

  getDefaultForType(type: PropertyType): string {
    if (type === PropertyType.CHECKBOX) {
      return 'false';
    }
    return '';
  }

  confirmAddProperty(): void {
    if (this.newPropName !== '') {
      const engine = PropertyEngine.getInstance();
      if (this.newPropType !== PropertyType.TEXT) {
        engine.registerSchema(this.newPropName, this.newPropType, '', []);
      }
      const defaultValue = this.getDefaultForType(this.newPropType);
      engine.setProperty(this.blockUuid, this.newPropName, defaultValue);
      AppState.bumpBlocksVersion();
      this.refreshProperties();
    }
    this.showAddDialog = false;
    this.newPropName = '';
    this.newPropType = PropertyType.TEXT;
  }

  cancelAddProperty(): void {
    this.showAddDialog = false;
    this.newPropName = '';
    this.newPropType = PropertyType.TEXT;
  }

  parseDate(dateStr: string): Date {
    if (dateStr === '') {
      return new Date();
    }
    const parts = dateStr.split('-');
    if (parts.length === 3) {
      return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    }
    return new Date();
  }

  formatDatePickerResult(year: number, month: number, day: number): string {
    const m = month + 1;
    const monthStr = m < 10 ? '0' + m : '' + m;
    const dayStr = day < 10 ? '0' + day : '' + day;
    return year + '-' + monthStr + '-' + dayStr;
  }

  openDatePicker(key: string): void {
    const currentValue = this.getPropertyValue(key);
    DatePickerDialog.show({
      start: new Date(2000, 0, 1),
      end: new Date(2050, 11, 31),
      selected: this.parseDate(currentValue),
      onAccept: (value: DatePickerResult) => {
        const dateStr = this.formatDatePickerResult(value.year, value.month, value.day);
        this.updatePropertyAndRefresh(key, dateStr);
      }
    });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // ─── 主内容 ───
      Column({ space: 0 }) {
        // 标题栏
        Row({ space: 8 }) {
          TablerIcon('adjustments', 16, $r('app.color.muted_text'))
          Text(t('properties'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text'))
            .layoutWeight(1)

          Row() {
            TablerIcon('plus', 16, $r('app.color.primary'))
          }
          .width(28)
          .height(28)
          .justifyContent(FlexAlign.Center)
          .borderRadius(4)
          .onClick(() => {
            this.newPropName = '';
            this.newPropType = PropertyType.TEXT;
            this.showAddDialog = true;
          })
        }
        .width('100%')
        .padding({ left: 14, right: 10, top: 10, bottom: 10 })

        Divider().color($r('app.color.border')).width('100%')

        // 属性列表 / 空状态
        if (this.blockUuid === '') {
          Column({ space: 8 }) {
            TablerIcon('mouse', 28, $r('app.color.muted_text'))
            Text('选择一个块以编辑属性')
              .fontSize(12)
              .fontColor($r('app.color.muted_text'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.propertyKeys.length === 0) {
          Column({ space: 10 }) {
            TablerIcon('adjustments-off', 28, $r('app.color.muted_text'))
            Text(t('no_properties'))
              .fontSize(12)
              .fontColor($r('app.color.muted_text'))
            Row({ space: 4 }) {
              TablerIcon('plus', 14, $r('app.color.primary'))
              Text('添加属性')
                .fontSize(12)
                .fontColor($r('app.color.primary'))
            }
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(4)
            .backgroundColor($r('app.color.surface2'))
            .onClick(() => {
              this.newPropName = '';
              this.newPropType = PropertyType.TEXT;
              this.showAddDialog = true;
            })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 0 }) {
              ForEach(this.propertyKeys, (key: string) => {
                this.PropertyRow(key)
              }, (key: string) => this.blockUuid + '_' + key)
            }
            .width('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')

      // ─── 添加属性对话框 ───
      if (this.showAddDialog) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.4)')
          .onClick(() => { this.cancelAddProperty(); })

        Column({ space: 14 }) {
          Text('添加属性')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text'))
            .width('100%')

          // 属性名输入
          Column({ space: 4 }) {
            Text('属性名')
              .fontSize(12)
              .fontColor($r('app.color.muted_text'))
            TextInput({ text: this.newPropName, placeholder: '例如 priority' })
              .fontSize(13)
              .height(36)
              .borderRadius(6)
              .backgroundColor($r('app.color.surface2'))
              .onChange((value: string) => {
                this.newPropName = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // 类型选择
          Column({ space: 6 }) {
            Text('类型')
              .fontSize(12)
              .fontColor($r('app.color.muted_text'))
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.getTypeOptions(), (opt: TypeOption) => {
                this.TypeButton(opt)
              }, (opt: TypeOption) => opt.type.toString())
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // 确认/取消
          Row({ space: 10 }) {
            Button(t('cancel'))
              .fontSize(13)
              .layoutWeight(1)
              .height(36)
              .backgroundColor($r('app.color.surface2'))
              .fontColor($r('app.color.text'))
              .onClick(() => { this.cancelAddProperty(); })

            Button(t('confirm'))
              .fontSize(13)
              .layoutWeight(1)
              .height(36)
              .backgroundColor($r('app.color.primary'))
              .fontColor(Color.White)
              .onClick(() => { this.confirmAddProperty(); })
          }
          .width('100%')
        }
        .width('85%')
        .padding(20)
        .backgroundColor($r('app.color.surface1'))
        .borderRadius(10)
        .border({ width: 1, color: $r('app.color.border') })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TypeButton(opt: TypeOption) {
    Text(opt.label)
      .fontSize(12)
      .fontColor(this.newPropType === opt.type ? Color.White : $r('app.color.text'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(4)
      .backgroundColor(this.newPropType === opt.type ? $r('app.color.primary') : $r('app.color.surface2'))
      .margin({ right: 8, bottom: 8 })
      .onClick(() => { this.newPropType = opt.type; })
  }

  @Builder
  PropertyRow(key: string) {
    Row({ space: 8 }) {
      // 属性名
      Text(key)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.muted_text'))
        .width(80)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 值编辑器
      this.ValueEditor(key)

      // 删除按钮
      Row() {
        TablerIcon('x', 14, $r('app.color.muted_text'))
      }
      .width(24)
      .height(24)
      .justifyContent(FlexAlign.Center)
      .borderRadius(4)
      .onClick(() => { this.removeProperty(key); })
    }
    .width('100%')
    .padding({ left: 14, right: 10, top: 8, bottom: 8 })
  }

  @Builder
  ValueEditor(key: string) {
    if (this.getPropertyType(key) === PropertyType.CHECKBOX) {
      Row({ space: 8 }) {
        Toggle({ type: ToggleType.Checkbox, isOn: this.getPropertyValue(key) === 'true' })
          .onChange((isOn: boolean) => {
            this.updatePropertyAndRefresh(key, isOn ? 'true' : 'false');
          })
        Text(this.getPropertyValue(key) === 'true' ? '是' : '否')
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
    } else if (this.getPropertyType(key) === PropertyType.DATE) {
      Row({ space: 6 }) {
        TablerIcon('calendar', 14, $r('app.color.muted_text'))
        Text(this.getPropertyValue(key) === '' ? '选择日期' : this.getPropertyValue(key))
          .fontSize(13)
          .fontColor(this.getPropertyValue(key) === '' ? $r('app.color.muted_text') : $r('app.color.text'))
      }
      .layoutWeight(1)
      .height(32)
      .borderRadius(4)
      .backgroundColor($r('app.color.surface2'))
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => { this.openDatePicker(key); })
    } else if (this.getPropertyType(key) === PropertyType.NUMBER) {
      TextInput({ text: this.getPropertyValue(key), placeholder: '0' })
        .fontSize(13)
        .layoutWeight(1)
        .height(32)
        .borderRadius(4)
        .backgroundColor($r('app.color.surface2'))
        .type(InputType.Number)
        .onChange((val: string) => {
          this.updateProperty(key, val);
        })
    } else if (this.getPropertyType(key) === PropertyType.TAGS) {
      TextInput({ text: this.getPropertyValue(key), placeholder: 'tag1, tag2' })
        .fontSize(13)
        .layoutWeight(1)
        .height(32)
        .borderRadius(4)
        .backgroundColor($r('app.color.surface2'))
        .onChange((val: string) => {
          this.updateProperty(key, val);
        })
    } else if (this.getPropertyType(key) === PropertyType.LIST) {
      TextInput({ text: this.getPropertyValue(key), placeholder: 'item1, item2' })
        .fontSize(13)
        .layoutWeight(1)
        .height(32)
        .borderRadius(4)
        .backgroundColor($r('app.color.surface2'))
        .onChange((val: string) => {
          this.updateProperty(key, val);
        })
    } else {
      TextInput({ text: this.getPropertyValue(key), placeholder: 'value' })
        .fontSize(13)
        .layoutWeight(1)
        .height(32)
        .borderRadius(4)
        .backgroundColor($r('app.color.surface2'))
        .onChange((val: string) => {
          this.updateProperty(key, val);
        })
    }
  }
}
