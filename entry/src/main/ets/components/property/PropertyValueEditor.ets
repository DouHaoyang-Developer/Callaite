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
  @Prop propValue: string = '';
  @Prop propType: string = PropertyType.TEXT;
  @State editValue: string = '';

  aboutToAppear(): void {
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
          .onChange((value: string) => { this.editValue = value; })
      } else if (this.propType === PropertyType.TAGS) {
        TextInput({ text: this.editValue, placeholder: 'tag1, tag2' })
          .fontSize(13)
          .layoutWeight(1)
          .height(32)
          .onChange((value: string) => { this.editValue = value; })
      } else if (this.propType === PropertyType.NUMBER) {
        TextInput({ text: this.editValue, placeholder: '0' })
          .fontSize(13)
          .layoutWeight(1)
          .height(32)
          .type(InputType.Number)
          .onChange((value: string) => { this.editValue = value; })
      } else if (this.propType === PropertyType.URL) {
        TextInput({ text: this.editValue, placeholder: 'https://' })
          .fontSize(13)
          .layoutWeight(1)
          .height(32)
          .type(InputType.URL)
          .onChange((value: string) => { this.editValue = value; })
      } else {
        // TEXT / PAGE / BLOCK / CLASS
        TextInput({ text: this.editValue, placeholder: 'value' })
          .fontSize(13)
          .layoutWeight(1)
          .height(32)
          .onChange((value: string) => { this.editValue = value; })
      }
    }
    .width('100%')
    .padding({ top: 2, bottom: 2 })
  }
}
