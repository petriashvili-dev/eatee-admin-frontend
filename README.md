# eatee Admin iOS

Отдельное SwiftUI-приложение админки eatee. Сейчас в нём реализован модуль ревью результатов агентов «Аудит» и «Генерация».

## Запуск

Откройте `eatee-admin-ios.xcodeproj` в Xcode и запустите схему **eatee-admin-ios**.

Сетевой слой использует production-контракт API: для разработки `http://localhost:5001`, для production измените `AdminAPIConfiguration.baseURL` на `https://eatee.ru`.
