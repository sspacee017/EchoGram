<p align="center">
  <img src="echogram-icon.png" width="96" height="96" alt="Иконка EchoGram">
</p>

<h1 align="center">EchoGram</h1>

<p align="center">Неофициальный клиент Telegram для macOS</p>

## Возможности

- **Музыка.** В отдельной вкладке открываются веб-библиотеки SoundCloud, Spotify и Яндекс Музыки. Войти можно через соответствующий сервис.
- **Ссылки.** Веб-страницы из сообщений можно открывать в боковой панели, оставаясь в чате.
- **Режим стримера.** Выберите «EchoGram → Режим стримера» или нажмите ⇧⌘S, чтобы скрыть окно чатов и отключить уведомления.

## Сборка на Mac

Понадобятся Git, Xcode 26 с компонентом Metal Toolchain, Homebrew и Rosetta 2 на Mac с Apple Silicon. Установите зависимости и запустите сборку из корня этого репозитория.

```sh
brew install cmake ninja meson nasm yasm zlib autoconf libtool automake pkg-config rustup
bash prepare-source.sh
bash build-native.sh
open dist/EchoGram.app
```

`prepare-source.sh` скачивает закреплённую версию Telegram для macOS с подмодулями и применяет изменения EchoGram из `echogram.patch`. Исходники после подготовки находятся в `Upstream/TelegramSwift`.

Для отладки используйте `bash build-native.sh --debug`. После первой полной сборки флаг `--app-only` позволяет повторно собрать приложение без подготовки нативных библиотек.

## Первый вход

1. Получите собственные `api_id` и `api_hash` в [Telegram API development tools](https://my.telegram.org/apps).
2. Создайте файл `~/Library/Application Support/dev.echogram.fork/telegram-api.json`. Запишите в него объект JSON с числовым полем `api_id` и строковым полем `api_hash`. Ограничьте доступ к файлу командой `chmod 600 "$HOME/Library/Application Support/dev.echogram.fork/telegram-api.json"`.
3. Запустите EchoGram. На телефоне откройте «Настройки → Устройства → Подключить устройство» и отсканируйте QR-код. Также можно войти по номеру телефона.

Файл с реквизитами хранится в папке поддержки приложения на вашем Mac.

## Исходники и лицензия

EchoGram основан на [Telegram для macOS](https://github.com/TelegramMessenger/telegram-macos) и использует Telegram API. Исходный код распространяется по [GNU GPL v2](LICENSE). Изменённые файлы перечислены в [CHANGES.md](CHANGES.md).
