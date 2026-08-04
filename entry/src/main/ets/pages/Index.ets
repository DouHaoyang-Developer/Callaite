import { MainContainer } from '../components/layout/MainContainer';
import { OnboardingPage } from '../components/onboarding/OnboardingPage';

@Entry
@Component
struct Index {
  @StorageLink('callaite_onboarded') onboarded: boolean = false;

  build() {
    Column() {
      if (!this.onboarded) {
        OnboardingPage()
      } else {
        MainContainer()
      }
    }
    .width('100%')
    .height('100%')
  }
}
