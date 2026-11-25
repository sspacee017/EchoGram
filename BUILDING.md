# Сборка EchoGram

## Сборка из исходников

Понадобятся Git, Xcode 26 с компонентом Metal Toolchain, Homebrew и Rosetta 2 на Mac с Apple Silicon. Установите зависимости и запустите сборку из корня репозитория или распакованного архива исходников.

```sh
brew install cmake ninja meson nasm yasm zlib autoconf libtool automake pkg-config rustup
bash prepare-source.sh
bash build-native.sh
open dist/EchoGram.app
```

Исходники клиента лежат в [Upstream/TelegramSwift](Upstream/TelegramSwift). В клоне репозитория `prepare-source.sh` скачивает закреплённые версии подмодулей. В архиве исходников зависимости для сборки уже на месте.

Для отладки используйте `bash build-native.sh --debug`. После первой полной сборки флаг `--app-only` позволяет повторно собрать приложение без подготовки нативных библиотек.

## Реквизиты для сборки из исходников

1. Получите собственные `api_id` и `api_hash` в [Telegram API development tools](https://my.telegram.org/apps).
2. Создайте папку поддержки командой `mkdir -p -m 700 "$HOME/Library/Application Support/dev.echogram.fork"`, затем создайте файл `~/Library/Application Support/dev.echogram.fork/telegram-api.json`. Запишите в него объект JSON с числовым полем `api_id` и строковым полем `api_hash`. Ограничьте доступ к файлу командой `chmod 600 "$HOME/Library/Application Support/dev.echogram.fork/telegram-api.json"`.
3. Запустите EchoGram. На телефоне откройте «Настройки → Устройства → Подключить устройство» и отсканируйте QR-код. Также можно войти по номеру телефона.

EchoGram читает реквизиты из папки поддержки при запуске. Права на папку должны быть `700`, а на файл — `600`.

## Сборка с входом по QR

Из корня проекта запустите сборку с флагом `--qr-release`. Она возьмёт реквизиты из локального файла, описанного выше. Для другого файла задайте `ECHOGRAM_TELEGRAM_API_FILE` перед сборкой.

```sh
bash build-native.sh --qr-release
bash package-qr-release.sh .build/qr-release/EchoGram.app dist/EchoGram-macos-arm64.zip
```

В CI можно передать значения через `ECHOGRAM_TELEGRAM_API_ID` и `ECHOGRAM_TELEGRAM_API_HASH`. Храните их отдельно в хранилище секретов CI.

При первом запуске эта сборка сразу открывает экран входа. Пара компилируется в исполняемый файл, и её можно извлечь из скачанного приложения.
