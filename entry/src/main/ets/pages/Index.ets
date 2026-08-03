import { MainContainer } from '../components/layout/MainContainer';

@Entry
@Component
struct Index {
  build() {
    Column() {
      MainContainer()
    }
    .width('100%')
    .height('100%')
  }
}
