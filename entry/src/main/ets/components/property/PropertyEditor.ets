import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { AppState } from '../../state/AppState';
import { PropertyEngine, PropertyType } from '../../core/engine/PropertyEngine';
import { PropertyValueEditor } from './PropertyValueEditor';
import { PropertyType as ValueType } from '../../core/models/Constants';

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
  /** W7-U1.2：添加属性失败时的可见提示（静默 no-op 会表现为「按钮失灵」） */
  @State addError: string = '';

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

  /**
   * 各类型的合法默认值。
   *
   * ⚠️ W7-U1.2 修复（设备实测缺陷）：此前除 CHECKBOX 外一律返回空串，
   * 而 PropertyEngine.validateProperty 对已注册 Schema 的 NUMBER 要求
   * `^-?\d+(\.\d+)?$`、DATE 要求 `^\d{4}-\d{2}-\d{2}$` —— **空串一律不通过**，
   * setProperty 随即静默 return：实测「添加属性 → 选『数字』→ 确认」后
   * 面板仍是「暂无属性」、.md 无任何变化（按钮按了没反应）。
   * 修复后按类型给出合法默认值：NUMBER→'0'、DATE→今天、CHECKBOX→'false'、其余→''。
   */
  getDefaultForType(type: PropertyType): string {
    if (type === PropertyType.CHECKBOX) {
      return 'false';
    }
    if (type === PropertyType.NUMBER) {
      return '0';
    }
    if (type === PropertyType.DATE) {
      return PropertyEditor.todayString();
    }
    return '';
  }

  /** 今天的 yyyy-MM-dd（DATE 类型属性的合法默认值） */
  static todayString(): string {
    const now = new Date();
    const m = now.getMonth() + 1;
    const monthStr = m < 10 ? '0' + m : '' + m;
    const day = now.getDate();
    const dayStr = day < 10 ? '0' + day : '' + day;
    return now.getFullYear() + '-' + monthStr + '-' + dayStr;
  }

  confirmAddProperty(): void {
    if (this.newPropName !== '') {
      const engine = PropertyEngine.getInstance();
      const defaultValue = this.getDefaultForType(this.newPropType);
      if (this.newPropType !== PropertyType.TEXT) {
        // ⚠️ 必须把 defaultValue 一并写进 Schema（此前传的是 ''，见 getDefaultForType 注释）
        engine.registerSchema(this.newPropName, this.newPropType, defaultValue, []);
      }
      engine.setProperty(this.blockUuid, this.newPropName, defaultValue);
      AppState.bumpBlocksVersion();
      this.refreshProperties();

      // 写回校验：PropertyEngine.setProperty 对「校验不通过」「块不存在」都是静默 return，
      // 不回读就会出现「点了确认、界面无变化、也没有任何提示」的假成功（实测且已复现）。
      if (!this.properties.has(this.newPropName)) {
        this.addError = '写入失败：' + this.newPropName
          + ' 可能已注册为其它类型（键名复用会沿用旧 Schema 校验），或该值不符合其校验规则';
        return;
      }
      this.addError = '';
    }
    this.showAddDialog = false;
    this.newPropName = '';
    this.newPropType = PropertyType.TEXT;
  }

  cancelAddProperty(): void {
    this.showAddDialog = false;
    this.newPropName = '';
    this.newPropType = PropertyType.TEXT;
    this.addError = '';
  }

  /**
   * W7-U1.2：数值型 PropertyType（PropertyEngine）→ 字符串型 PropertyType（Constants）映射。
   *
   * 仓库里存在**两套属性类型枚举**，取值口径不同：
   *  · PropertyEngine.PropertyType：数值 0..5（TEXT/NUMBER/CHECKBOX/DATE/TAGS/LIST），无 URL/PAGE/BLOCK/CLASS
   *  · Constants.PropertyType ：字符串 'text'/'number'/'checkbox'/'date'/'tags'/'url'/'page'/'block'/'class'，无 LIST
   * PropertyValueEditor 用的是后者（@Prop propType: string）。
   * TEXT/NUMBER/TAGS 两侧取值一一对应；LIST 在 Constants 无对应项，
   * 故 LIST 不交给共享编辑器（见 usesSharedValueEditor）。
   */
  static sharedValueType(type: PropertyType): string {
    if (type === PropertyType.NUMBER) {
      return ValueType.NUMBER;
    }
    if (type === PropertyType.TAGS) {
      return ValueType.TAGS;
    }
    return ValueType.TEXT;
  }

  /**
   * W7-U1.2：哪些类型交给 PropertyValueEditor 渲染值列。
   *
   * 只承接与内置分支**能力等价**的三类（placeholder / 输入类型逐项对应）：
   *  · TEXT   → placeholder 'value'        （一致）
   *  · NUMBER → placeholder '0' + 数字键盘  （一致）
   *  · TAGS   → placeholder 'tag1, tag2'   （一致）
   * 不承接（保留本组件内置分支，替换必须保证既有能力不丢 ✗）：
   *  · CHECKBOX → 需 Toggle 的 isOn 双向显示 + onChange 写回，PropertyValueEditor 无此绑定
   *  · DATE     → 需点击拉起 DatePickerDialog，PropertyValueEditor 只是文本框
   *  · LIST     → placeholder 'item1, item2' 在字符串枚举里无对应类型，会被降级为 'value'
   */
  usesSharedValueEditor(type: PropertyType): boolean {
    return type === PropertyType.TEXT || type === PropertyType.NUMBER
      || type === PropertyType.TAGS;
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
          .alignItems(VerticalAlign.Center)
          .width(28)
          .height(28)
          .justifyContent(FlexAlign.Center)
          .borderRadius(4)
          .onClick(() => {
            this.newPropName = '';
            this.newPropType = PropertyType.TEXT;
            this.addError = '';
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
              this.addError = '';
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

          // W7-U1.2：写入失败提示（原先 setProperty 静默 return ⇒ 确认后毫无反馈）
          if (this.addError !== '') {
            Text(this.addError)
              .fontSize(11)
              .fontColor($r('app.color.danger'))
              .width('100%')
          }

          // 确认/取消
          Row({ space: 10 }) {
            Button(t('cancel')).type(ButtonType.Capsule)
              .fontSize(13)
              .layoutWeight(1)
              .height(36)
              .backgroundColor($r('app.color.surface2'))
              .fontColor($r('app.color.text'))
              .onClick(() => { this.cancelAddProperty(); })

            Button(t('confirm')).type(ButtonType.Capsule)
              .fontSize(13)
              .layoutWeight(1)
              .height(36)
              .backgroundColor($r('app.color.primary'))
              .fontColor($r('app.color.on_primary'))
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
      .fontColor(this.newPropType === opt.type ? $r('app.color.on_primary') : $r('app.color.text'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(4)
      .backgroundColor(this.newPropType === opt.type ? $r('app.color.primary') : $r('app.color.surface2'))
      .margin({ right: 8, bottom: 8 })
      .onClick(() => { this.newPropType = opt.type; })
  }

  @Builder
  PropertyRow(key: string) {
    Row({ space: 8 }) {
      if (this.usesSharedValueEditor(this.getPropertyType(key))) {
        // W7-U1.2：文本族（TEXT/NUMBER/TAGS）的值列改用 PropertyValueEditor。
        // 该组件自带「属性名列（80vp）」——故此分支不再重复渲染 Text(key)，
        // 写回由 onValueChange → updateProperty → PropertyEngine.setProperty 承担。
        Column() {
          PropertyValueEditor({
            propKey: key,
            propValue: this.getPropertyValue(key),
            propType: PropertyEditor.sharedValueType(this.getPropertyType(key)),
            onValueChange: (k: string, v: string): void => {
              this.updateProperty(k, v);
            }
          })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      } else {
        // 属性名
        Text(key)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.muted_text'))
          .width(80)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 值编辑器（CHECKBOX / DATE / LIST 专属分支）
        this.ValueEditor(key)
      }

      // 删除按钮
      Row() {
        TablerIcon('x', 14, $r('app.color.muted_text'))
      }
      .alignItems(VerticalAlign.Center)
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
