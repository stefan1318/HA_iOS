# STEVORA на iPhone с Personal Team

## StevoraCompanion от unsigned IPA workflow-а

Това е нативното приложение за STEVORA OS Dev4 от `STEVORA/iOSApp`. От корена на хранилището изпълни командите по-долу. Ако XcodeGen липсва, инсталирай го с `brew install xcodegen`. Избери уникален Bundle ID с малки букви и го пази за следващите компилации.

```bash
cd STEVORA/iOSApp
swift Branding/generate-icon.swift Assets.xcassets/AppIcon.appiconset/AppIcon.png
STEVORA_PERSONAL_BUNDLE_ID=com.yourname.stevora.a1b2c3.ios xcodegen generate --spec project.personal.yml
open StevoraCompanion-Personal.xcodeproj
```

1. В Xcode 27.2 отвори **Xcode → Settings → Apple Accounts** и добави Apple акаунта си, ако вече не е добавен.
2. В **TARGETS → StevoraCompanion → Signing & Capabilities** избери **Debug-Personal**. Остави **Automatically manage signing** включено и избери своя **Personal Team**.
3. Свържи отключения iPhone и потвърди **Trust**, ако бъде поискано. Ако Xcode поиска Developer Mode, включи го в **Settings → Privacy & Security → Developer Mode** на iPhone, рестартирай и потвърди.
4. Избери схемата **STEVORA-Personal** и физическия iPhone от лентата в Xcode. Натисни **Register**, ако се появи под Signing, после **⌘R**.
5. Влез в своя STEVORA дом. Затвори и отвори приложението отново, за да провериш входа и запазената връзка. Профилът на Personal Team изтича след седем дни. Стартирай пак с **⌘R**, за да обновиш инсталацията.

Ако Bundle ID е зает, генерирай с нов уникален ID и избери екипа отново. Ако регенерираш след промяна на проекта, използвай запазения ID и провери избрания екип. Нативният target няма extensions, Swift пакети или специални entitlements. Фоновата локация, местната мрежа, микрофонът и OAuth запазват настройките си от нативния проект. `project.yml` и неговата схема `StevoraCompanion` продължават да обслужват unsigned IPA.

## HomeAssistant App-Debug с грешка за io.robbie.HomeAssistant.dev

Този вариант е за Companion приложението в корена, откъдето идва грешката за Wi-Fi, Siri, Push и другите права. Отвори го само ако искаш да тестваш именно Companion приложението.

1. От корена на това хранилище изпълни `python3 Tools/generate_personal_team_project.py com.yourname.stevora.a1b2c3`. Замени примера с твой уникален префикс с малки букви. Полученият идентификатор завършва на `.HomeAssistant.dev`. Използвай същия префикс при повторно генериране, за да обновяваш същата инсталация.
2. Отвори `STEVORA-Personal.xcodeproj` в Xcode 27.2 и изчакай Swift Package Manager. В **Xcode → Settings → Apple Accounts** добави Apple акаунта си, ако вече не е добавен.
3. В навигатора избери проекта, после **TARGETS → App → Signing & Capabilities**. За **Debug-Personal** включи **Automatically manage signing** и избери екипа с означение **Personal Team**. Xcode записва избора в локалния генериран проект, който Git игнорира.
4. Свържи отключения iPhone и потвърди **Trust**, ако се появи. Ако Xcode поиска Developer Mode, включи го в **Settings → Privacy & Security → Developer Mode** на телефона, рестартирай и потвърди. Избери схемата **STEVORA-Personal** и телефона от лентата в Xcode. Ако под Signing има бутон **Register**, натисни го. Натисни **⌘R**.
5. След старта въведи адреса на Home Assistant и влез. Затвори и отвори приложението отново, за да провериш дали връзката и настройките се запазват. По правилата на Apple профилът изтича след 7 дни. Стартирай отново с **⌘R**, за да обновиш инсталацията.

Ако Apple отхвърли Bundle ID като зает, премести генерирания проект извън хранилището, генерирай отново с друг префикс и избери Personal Team. При обновяване на клона използвай същата процедура със същия префикс, за да генерираш проекта от актуалните настройки. Ако имаш и обикновената Debug версия на телефона и входът отвори другото приложение, двете версии използват един и същ OAuth URL scheme (`homeassistant-dev`).

Вариантът включва приложението, `Shared-iOS` и `Codegen`. Запазва заключените Swift пакети. Данните се съхраняват в собствената папка на приложението и в стандартните му настройки. Вариантът е без специалните права за App Groups, споделен Keychain, APNs, локален push provider, Associated Domains, Siri, Wi-Fi информация, NFC, HealthKit, HomeKit, CarPlay и Matter extension. Разширенията за обработка и изглед на известия, Share, Widgets и Apple Watch също са изключени. Подписването и схемите в `HomeAssistant.xcodeproj` продължават да се управляват отделно.
