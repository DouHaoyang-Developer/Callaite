import { PropertyType } from '../../core/models/Constants';
import { TablerIcon } from '../common/Icons';

/**
 * PropertyValueEditor — 属性值编辑器。
 * 根据属性类型显示对应的编辑控件。
 * 支持 text / number / checkbox / date / tags / url。
 */
@Component
export struct PropertyValueEditor {
  @Prop propKey: string = '';
  @Prop @Watch('onPropValueChanged') propValue: string = '';
  @Prop propType: string = PropertyType.TEXT;
  /**
   * W7-U1.2：值变更上报。
   *
   * 该组件自身**不持有数据通路**（只按类型渲染控件 + 上报），落库由宿主注入：
   * `PropertyEditor` 用它渲染 TEXT/NUMBER/TAGS 三类的值列，回调里接
   * `PropertyEngine.setProperty` → `DataStore.savePage` → .md。
   * 默认空实现 ⇒ 独立渲染时是只读展示，不会产生无落点的写入。
   */
  onValueChange: (key: string, value: string) => void = (): void => {};
  @State editValue: string = '';

  aboutToAppear(): void {
    this.editValue = this.propValue;
  }

  /**
   * 外部值变化时重置本地编辑态（@Prop 是单向的，不重置会显示旧值）。
   */
  onPropValueChanged(): void {
    this.editValue = this.propValue;
  }

  build() {
    Row({ space: 8 }) {
      Text(this.propKey)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.muted_text'))
        .width(80)

      if (this.propType === PropertyType.CHECKBOX) {
        Toggle({ type: ToggleType.Checkbox })
          .width(24)
          .height(24)
      } else if (this.propType === PropertyType.DATE) {
        TextInput({ text: this.editValue, placeholder: 'yyyy-MM-dd' })
          .fontSize(13)
          .layoutWeight(1)
          .height(32)
          .borderRadius(4)
          .backgroundColor($r('app.color.surface2'))
          .onChange((value: string) => {
            this.editValue = value;
            this.onValueChange(this.propKey, value);
          })
      } else if (this.propType === PropertyType.TAGS) {
        TextInput({ text: this.editValue, placeholder: 'tag1, tag2' })
          .fontSize(13)
          .layoutWeight(1)
          .height(32)
          .borderRadius(4)
          .backgroundColor($r('app.color.surface2'))
          .onChange((value: string) => {
            this.editValue = value;
            this.onValueChange(this.propKey, value);
          })
      } else if (this.propType === PropertyType.NUMBER) {
        TextInput({ text: this.editValue, placeholder: '0' })
          .fontSize(13)
          .layoutWeight(1)
          .height(32)
          .borderRadius(4)
          .backgroundColor($r('app.color.surface2'))
          .type(InputType.Number)
          .onChange((value: string) => {
            this.editValue = value;
            this.onValueChange(this.propKey, value);
          })
      } else if (this.propType === PropertyType.URL) {
        TextInput({ text: this.editValue, placeholder: 'https://' })
          .fontSize(13)
          .layoutWeight(1)
          .height(32)
          .borderRadius(4)
          .backgroundColor($r('app.color.surface2'))
          .type(InputType.URL)
          .onChange((value: string) => {
            this.editValue = value;
            this.onValueChange(this.propKey, value);
          })
      } else {
        // TEXT / PAGE / BLOCK / CLASS
        TextInput({ text: this.editValue, placeholder: 'value' })
          .fontSize(13)
          .layoutWeight(1)
          .height(32)
          .borderRadius(4)
          .backgroundColor($r('app.color.surface2'))
          .onChange((value: string) => {
            this.editValue = value;
            this.onValueChange(this.propKey, value);
          })
      }
    }
    .width('100%')
    .padding({ top: 2, bottom: 2 })
  }
}
