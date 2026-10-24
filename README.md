# ОК · Нативный клиент для iPhone

Первый прототип неофициального клиента Одноклассников: **SwiftUI, iOS 17+**, тестовые данные, полностью офлайн. Настоящая авторизация и API ОК пока не подключены.

## Что можно попробовать

- Профиль с обложкой, редактированием имени и описания, списком друзей и поиском.
- Лента с демонстрационными публикациями, «классами» и системным меню «Поделиться».
- Фотографии, фильтры по альбомам, полноэкранный просмотр с перелистыванием, избранное и отправка фотографии.
- Светлая, тёмная и системная темы, настройка тактильного отклика, обновление и очистка кеша.
- SwiftData сохраняет снимок данных и реакции. Настройки и локальные правки профиля хранятся в UserDefaults.
- Все фотографии включены в приложение; интернет для демо не нужен.

## Установка с Windows

1. Откройте [GitHub Actions](https://github.com/Erapchu/ok_ios/actions/workflows/ios.yml). Сборка запускается при push; её также можно запустить через **Run workflow**.
2. Дождитесь зелёного результата **iOS · Test & IPA**. Внизу страницы запуска скачайте артефакт **OKNative-unsigned-ipa**. Распакуйте ZIP: внутри `OKNative-unsigned.ipa`.
3. Установите [Sideloadly](https://sideloadly.io/) и необходимые драйверы Apple по инструкции на его сайте. Подключите iPhone по USB и подтвердите доверие компьютеру.
4. Перетащите `.ipa` в Sideloadly, выберите iPhone, укажите свой Apple ID и нажмите **Start**. Apple ID и пароль **не нужны в GitHub и в исходниках приложения**.
5. При необходимости подтвердите разработчика: **Настройки → Основные → VPN и управление устройством**. Если iOS запросит режим разработчика, включите его в **Конфиденциальность и безопасность → Режим разработчика**, перезагрузите телефон и подтвердите включение.
6. Запускайте **ОК Нативный** с обычной иконки на рабочем столе.

Для бесплатного Apple ID подпись обычно действует 7 дней; затем приложение нужно переподписать. Sideloadly поддерживает автоматическое обновление подписи. Для обновлений используйте тот же Apple ID и Bundle ID, чтобы сохранить локальные данные. См. [официальный FAQ Sideloadly](https://sideloadly.io/faq.html) и [Developer Mode у Apple](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

## Сборка

В репозитории уже есть `OKNative.xcodeproj` и общая схема `OKNative`. Внешних Swift-пакетов и генераторов для сборки не требуется. На Mac откройте проект в Xcode 16+; для запуска на физическом устройстве выберите свою Team в Signing & Capabilities. Bundle ID: `app.erapchu.oknative`.

GitHub Actions использует `macos-15`: проверяет структуру проекта, запускает XCTest на доступном симуляторе iPhone, архивирует приложение для `generic/platform=iOS` с отключённой подписью и упаковывает `Payload/OKNative.app` в `.ipa`. Подпись выполняется позднее в Sideloadly. Сертификаты, provisioning profiles и платная программа разработчика для CI не нужны.

```bash
# На macOS: тесты (укажите доступный симулятор)
xcodebuild test -project OKNative.xcodeproj -scheme OKNative \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGN_IDENTITY=-

# Архив и неподписанный IPA
xcodebuild archive -project OKNative.xcodeproj -scheme OKNative \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/OKNative.xcarchive CODE_SIGNING_ALLOWED=NO
bash scripts/package_ipa.sh
```

Тестовая сборка симулятора использует локальную подпись `-` и отдельные `Simulator.entitlements`, чтобы тестировать настоящий Keychain. Для этого не нужны сертификаты Apple. Эти entitlements не применяются к архиву для iPhone.

После добавления или удаления Swift-файлов обновите проект: `python3 scripts/generate_project.py`. Генерация детерминированная и не требует пакетов. Для быстрой проверки на Windows или macOS:

```bash
python3 scripts/generate_project.py --check
python3 scripts/verify_project.py
```

## Структура и следующий этап

`App/` — запуск, контейнер SwiftData и тема. `Views/` — нативные экраны. `Models/` — Codable-модели и кеш. `Services/AppStore.swift` — загрузка, кеш и реакции на MainActor; `SocialService` — заменяемый источник данных. `DemoSocialService` использует Swift Concurrency и возвращает тестовые данные.

`HTTPClient` — транспорт URLSession с `async/await`, проверкой HTTPS и HTTP-статусов, декодированием и отменой. `KeychainTokenStore` — actor для записи, обновления, чтения и удаления OAuth-токенов с `WhenUnlockedThisDeviceOnly`. В демо эти компоненты не обращаются к ОК и не создают токены.

Для реального аккаунта следующий этап — зарегистрировать приложение на платформе ОК, проверить доступные OAuth-разрешения и методы API, затем реализовать `SocialService`. Секрет приложения нельзя включать в iOS-бинарник; если выбранный поток потребует секрет, потребуется серверная часть. Наличие прототипа не означает, что API разрешает все функции сайта.

Тесты проверяют восстановление кеша и реакций, обработку повреждённого кеша, сохранение старых данных при ошибке обновления, очистку кеша без потери избранного, отмену, запрет HTTP и жизненный цикл записи Keychain. Фотографии и иконка описаны в [ASSET_CREDITS.md](ASSET_CREDITS.md).
