import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { AppState } from '../../state/AppState';
import { PropertyEngine, PropertyType, PropertySchema } from '../../core/engine/PropertyEngine';

/**
 * PropertyConfig — 属性 Schema 配置 UI。
 *
 * 对应 Logseq property/schema.cljs 的可视化编辑。
 *
 * 职责：
 *  - 列出已注册的自定义属性 Schema（可编辑/删除）
 *  - 列出内置属性（只读）
 *  - 提供添加/编辑对话框：名称、类型、默认值、枚举选项
 *
 * 注意：
 *  - 使用 PropertyEngine（core/engine/PropertyEngine.ets）的数值型 PropertyType 枚举
 *  - 自定义 Schema 名称列表持久化到 AppStorage（'callaite_customSchemas'）
 *  - 注册时调用 PropertyEngine.registerSchema
 */

const STORAGE_KEY_CUSTOM_SCHEMAS = 'callaite_customSchemas';

// 类型选项列表：显示名 + PropertyType 值
interface TypeOption {
  label: string;
  value: PropertyType;
}

const TYPE_OPTIONS: TypeOption[] = [
  { label: '文本', value: PropertyType.TEXT },
  { label: '数字', value: PropertyType.NUMBER },
  { label: '复选框', value: PropertyType.CHECKBOX },
  { label: '日期', value: PropertyType.DATE },
  { label: '标签', value: PropertyType.TAGS },
  { label: '列表', value: PropertyType.LIST }
];

// Select 组件所需的 { value: string } 数组类型 — 通过显式构造避免对象字面量问题
interface SelectOption {
  value: string;
}

@Component
export struct PropertyConfig {
  @State schemas: Map<string, PropertySchema> = new Map<string, PropertySchema>();
  @State schemaList: string[] = [];
  @State builtinList: string[] = [];
  @State showAddDialog: boolean = false;
  @State isEditing: boolean = false;
  @State editingName: string = '';
  @State editingType: PropertyType = PropertyType.TEXT;
  @State editingDefault: string = '';
  @State editingOptions: string = '';
  @State selectTypeIndex: number = 0;

  aboutToAppear(): void {
    this.builtinList = PropertyEngine.getInstance().getBuiltinProperties();
    this.loadCustomSchemas();
  }

  /**
   * 从 AppStorage 加载自定义 Schema 名称列表，并重新从 PropertyEngine 读取 schema 定义。
   */
  private loadCustomSchemas(): void {
    const raw = AppStorage.get<string>(STORAGE_KEY_CUSTOM_SCHEMAS);
    const names: string[] = [];
    if (raw) {
      try {
        const parsed = JSON.parse(raw) as string[];
        if (parsed && parsed.length > 0) {
          for (let i = 0; i < parsed.length; i++) {
            names.push(parsed[i]);
          }
        }
      } catch (_e) {
        // 忽略解析错误
      }
    }

    const map = new Map<string, PropertySchema>();
    const list: string[] = [];
    for (let i = 0; i < names.length; i++) {
      const schema = PropertyEngine.getInstance().getSchema(names[i]);
      if (schema) {
        map.set(names[i], schema);
        list.push(names[i]);
      }
    }
    this.schemas = map;
    this.schemaList = list;
  }

  /**
   * 持久化自定义 Schema 名称列表到 AppStorage。
   */
  private persistCustomSchemaNames(): void {
    AppStorage.setOrCreate(STORAGE_KEY_CUSTOM_SCHEMAS, JSON.stringify(this.schemaList));
  }

  /**
   * 将 editingType 转换为 TYPE_OPTIONS 中的索引。
   */
  private typeToIndex(type: PropertyType): number {
    for (let i = 0; i < TYPE_OPTIONS.length; i++) {
      if (TYPE_OPTIONS[i].value === type) {
        return i;
      }
    }
    return 0;
  }

  /**
   * 获取 PropertyType 的显示名。
   */
  private typeLabel(type: PropertyType): string {
    for (let i = 0; i < TYPE_OPTIONS.length; i++) {
      if (TYPE_OPTIONS[i].value === type) {
        return TYPE_OPTIONS[i].label;
      }
    }
    return '文本';
  }

  /**
   * 获取 schema 的类型标签（安全访问 Map）。
   */
  private schemaTypeLabel(name: string): string {
    const schema = this.schemas.get(name);
    if (schema) {
      return this.typeLabel(schema.type);
    }
    return '文本';
  }

  /**
   * 获取 schema 的默认值显示文本（空默认值显示为 '-'）。
   */
  private schemaDefaultLabel(name: string): string {
    const schema = this.schemas.get(name);
    if (schema) {
      if (schema.defaultValue.length === 0) {
        return '-';
      }
      return schema.defaultValue;
    }
    return '-';
  }

  /**
   * 构建 Select 选项列表（避免箭头函数返回对象字面量）。
   */
  private buildSelectOptions(): SelectOption[] {
    const result: SelectOption[] = [];
    for (let i = 0; i < TYPE_OPTIONS.length; i++) {
      const opt: SelectOption = { value: TYPE_OPTIONS[i].label };
      result.push(opt);
    }
    return result;
  }

  /**
   * 打开新增对话框。
   */
  private openAddDialog(): void {
    this.isEditing = false;
    this.editingName = '';
    this.editingType = PropertyType.TEXT;
    this.editingDefault = '';
    this.editingOptions = '';
    this.selectTypeIndex = 0;
    this.showAddDialog = true;
  }

  /**
   * 打开编辑对话框。
   */
  private openEditDialog(name: string): void {
    const schema = this.schemas.get(name);
    if (!schema) {
      return;
    }
    this.isEditing = true;
    this.editingName = schema.name;
    this.editingType = schema.type;
    this.editingDefault = schema.defaultValue;
    this.editingOptions = schema.options.join(', ');
    this.selectTypeIndex = this.typeToIndex(schema.type);
    this.showAddDialog = true;
  }

  /**
   * 将选项字符串解析为 string[]。按逗号分隔，去除空白与空项。
   */
  private parseOptions(raw: string): string[] {
    const result: string[] = [];
    if (!raw) {
      return result;
    }
    const parts = raw.split(',');
    for (let i = 0; i < parts.length; i++) {
      const trimmed = parts[i].trim();
      if (trimmed.length > 0) {
        result.push(trimmed);
      }
    }
    return result;
  }

  /**
   * 校验表单输入，返回错误信息。空字符串表示通过。
   */
  private validateForm(): string {
    const name = this.editingName.trim();
    if (name.length === 0) {
      return '属性名不能为空';
    }
    // 仅在新增时检查重名
    if (!this.isEditing) {
      // 检查与内置属性冲突
      for (let i = 0; i < this.builtinList.length; i++) {
        if (this.builtinList[i] === name) {
          return '属性名与内置属性冲突';
        }
      }
      // 检查与已存在自定义属性冲突
      if (this.schemas.has(name)) {
        return '属性名已存在';
      }
    }
    return '';
  }

  /**
   * 确认保存（新增或编辑）。
   */
  private confirmSave(): void {
    const error = this.validateForm();
    if (error.length > 0) {
      console.warn('[PropertyConfig] ' + error);
      return;
    }

    const name = this.editingName.trim();
    const options = this.parseOptions(this.editingOptions);

    // 注册到 PropertyEngine
    PropertyEngine.getInstance().registerSchema(name, this.editingType, this.editingDefault, options);

    // 更新本地 Map 与列表
    const newSchema: PropertySchema = {
      name: name,
      type: this.editingType,
      defaultValue: this.editingDefault,
      options: options
    };
    const newMap = new Map<string, PropertySchema>();
    this.schemas.forEach((v: PropertySchema, k: string) => {
      newMap.set(k, v);
    });
    newMap.set(name, newSchema);
    this.schemas = newMap;

    // 更新列表（新增时追加，编辑时保留原位置）
    if (!this.isEditing) {
      const newList: string[] = [];
      for (let i = 0; i < this.schemaList.length; i++) {
        newList.push(this.schemaList[i]);
      }
      newList.push(name);
      this.schemaList = newList;
      this.persistCustomSchemaNames();
    }

    // 触发 UI 刷新
    AppState.bumpBlocksVersion();
    this.showAddDialog = false;
  }

  /**
   * 删除自定义 Schema。
   */
  private deleteSchema(name: string): void {
    const newMap = new Map<string, PropertySchema>();
    this.schemas.forEach((v: PropertySchema, k: string) => {
      if (k !== name) {
        newMap.set(k, v);
      }
    });
    this.schemas = newMap;

    const newList: string[] = [];
    for (let i = 0; i < this.schemaList.length; i++) {
      if (this.schemaList[i] !== name) {
        newList.push(this.schemaList[i]);
      }
    }
    this.schemaList = newList;
    this.persistCustomSchemaNames();
    AppState.bumpBlocksVersion();
  }

  build() {
    Stack() {
      // 主内容
      Column({ space: 16 }) {
        // 标题栏
        Row({ space: 12 }) {
          Row() {
            TablerIcon('arrow-left', 18, $r('app.color.text'))
          }
          .width(36).height(36)
          .onClick(() => {
            AppState.setCurrentPage('Settings');
          })

          Text('属性配置')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text'))
            .layoutWeight(1)

          Row() {
            TablerIcon('plus', 18, $r('app.color.primary'))
          }
          .width(36).height(36)
          .onClick(() => {
            this.openAddDialog();
          })
        }
        .width('100%')
        .padding({ top: 16, bottom: 8 })

        // 自定义属性区
        this.SectionHeader('自定义属性')

        if (this.schemaList.length === 0) {
          Text('暂无自定义属性，点击右上角添加')
            .fontSize(13)
            .fontColor($r('app.color.muted_text'))
            .width('100%')
            .padding({ top: 12, bottom: 12, left: 12, right: 12 })
        } else {
          ForEach(this.schemaList, (name: string) => {
            this.SchemaRow(name)
          }, (name: string) => name)
        }

        Divider().color($r('app.color.border')).margin({ top: 8, bottom: 8 })

        // 内置属性区（只读）
        this.SectionHeader('内置属性')

        ForEach(this.builtinList, (name: string) => {
          this.BuiltinRow(name)
        }, (name: string) => name)

        Blank()
      }
      .width('100%')
      .height('100%')
      .padding({ left: 20, right: 20 })
      .alignItems(HorizontalAlign.Start)

      // 添加/编辑对话框（叠加层）
      if (this.showAddDialog) {
        this.AddEditDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SectionHeader(label: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.muted_text'))
      .width('100%')
      .padding({ top: 4, bottom: 4 })
  }

  @Builder
  SchemaRow(name: string) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text'))
        Row({ space: 6 }) {
          Text(this.schemaTypeLabel(name))
            .fontSize(11)
            .fontColor($r('app.color.primary'))
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .borderRadius(3)
            .backgroundColor($r('app.color.surface2'))
          Text('默认: ' + this.schemaDefaultLabel(name))
            .fontSize(11)
            .fontColor($r('app.color.muted_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: 4 }) {
        Row() {
          TablerIcon('edit', 14, $r('app.color.muted_text'))
        }
        .width(28).height(28)
        .onClick(() => {
          this.openEditDialog(name);
        })

        Row() {
          TablerIcon('trash', 14, $r('app.color.danger'))
        }
        .width(28).height(28)
        .onClick(() => {
          this.deleteSchema(name);
        })
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 8, left: 8, right: 8 })
    .borderRadius(8)
    .backgroundColor($r('app.color.surface1'))
  }

  @Builder
  BuiltinRow(name: string) {
    Row({ space: 8 }) {
      TablerIcon('lock', 14, $r('app.color.muted_text'))
      Text(name)
        .fontSize(14)
        .fontColor($r('app.color.text'))
        .layoutWeight(1)
      Text('内置')
        .fontSize(10)
        .fontColor($r('app.color.muted_text'))
        .padding({ left: 4, right: 4, top: 1, bottom: 1 })
        .borderRadius(3)
        .backgroundColor($r('app.color.surface2'))
    }
    .width('100%')
    .padding({ top: 6, bottom: 6, left: 8, right: 8 })
  }

  @Builder
  AddEditDialog() {
    // 半透明遮罩 + 居中对话框
    Stack({ alignContent: Alignment.Center }) {
      // 遮罩层
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.4)')
        .onClick(() => {
          this.showAddDialog = false;
        })

      // 对话框主体
      Column({ space: 12 }) {
        Text(this.isEditing ? '编辑属性' : '添加属性')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text'))
          .width('100%')

        // 属性名
        Column({ space: 4 }) {
          Text('属性名')
            .fontSize(12)
            .fontColor($r('app.color.muted_text'))
          TextInput({ text: this.editingName, placeholder: '例如 priority' })
            .fontSize(13)
            .height(36)
            .enabled(!this.isEditing)
            .onChange((value: string) => {
              this.editingName = value;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 类型
        Column({ space: 4 }) {
          Text('类型')
            .fontSize(12)
            .fontColor($r('app.color.muted_text'))
          Select(this.buildSelectOptions())
            .selected(this.selectTypeIndex)
            .value(this.typeLabel(this.editingType))
            .onSelect((index: number) => {
              this.selectTypeIndex = index;
              this.editingType = TYPE_OPTIONS[index].value;
            })
            .width('100%')
            .height(36)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 默认值
        Column({ space: 4 }) {
          Text('默认值')
            .fontSize(12)
            .fontColor($r('app.color.muted_text'))
          TextInput({ text: this.editingDefault, placeholder: '默认值（可空）' })
            .fontSize(13)
            .height(36)
            .onChange((value: string) => {
              this.editingDefault = value;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 选项列表
        Column({ space: 4 }) {
          Text(this.editingType === PropertyType.TAGS || this.editingType === PropertyType.LIST
            ? '选项列表（逗号分隔）' : '选项列表（仅 TAGS/LIST 使用）')
            .fontSize(12)
            .fontColor($r('app.color.muted_text'))
          TextInput({ text: this.editingOptions, placeholder: 'option1, option2, option3' })
            .fontSize(13)
            .height(36)
            .onChange((value: string) => {
              this.editingOptions = value;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 操作按钮
        Row({ space: 8 }) {
          Button(t('cancel'))
            .fontSize(13)
            .layoutWeight(1)
            .backgroundColor($r('app.color.surface2'))
            .fontColor($r('app.color.text'))
            .onClick(() => {
              this.showAddDialog = false;
            })
          Button(t('confirm'))
            .fontSize(13)
            .layoutWeight(1)
            .backgroundColor($r('app.color.primary'))
            .fontColor(Color.White)
            .onClick(() => {
              this.confirmSave();
            })
        }
        .width('100%')
      }
      .width('80%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor($r('app.color.surface1'))
    }
    .width('100%')
    .height('100%')
  }
}
