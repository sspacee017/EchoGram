# Изменения EchoGram

EchoGram изменяет исходники Telegram для macOS. Снимок изменений подготовлен 24 ноября 2026 года на базе коммита `38309ec95e59be3958d1e6fe9be331d72527a38d`.

Список ниже относится к файлам в `echogram.patch`. Изменения для Telegram-iOS входят в исходный проект Telegram для macOS и применяются его скриптом сборки.

A — добавлен, D — удалён, M — изменён.

```text
D	Telegram-Mac/Assets.xcassets/AppIcon.appiconset/Contents.json
D	Telegram-Mac/Assets.xcassets/AppIcon.appiconset/Logo_1024.png
D	Telegram-Mac/Assets.xcassets/AppIcon.appiconset/Logo_128.png
D	Telegram-Mac/Assets.xcassets/AppIcon.appiconset/Logo_16.png
D	Telegram-Mac/Assets.xcassets/AppIcon.appiconset/Logo_256-1.png
D	Telegram-Mac/Assets.xcassets/AppIcon.appiconset/Logo_256.png
D	Telegram-Mac/Assets.xcassets/AppIcon.appiconset/Logo_32-1.png
D	Telegram-Mac/Assets.xcassets/AppIcon.appiconset/Logo_32.png
D	Telegram-Mac/Assets.xcassets/AppIcon.appiconset/Logo_512-1.png
D	Telegram-Mac/Assets.xcassets/AppIcon.appiconset/Logo_512.png
D	Telegram-Mac/Assets.xcassets/AppIcon.appiconset/Logo_64.png
A	Telegram-Mac/Assets.xcassets/EchoGramIcon.appiconset/Contents.json
A	Telegram-Mac/Assets.xcassets/EchoGramIcon.appiconset/Logo_1024.png
A	Telegram-Mac/Assets.xcassets/EchoGramIcon.appiconset/Logo_128.png
A	Telegram-Mac/Assets.xcassets/EchoGramIcon.appiconset/Logo_16.png
A	Telegram-Mac/Assets.xcassets/EchoGramIcon.appiconset/Logo_256-1.png
A	Telegram-Mac/Assets.xcassets/EchoGramIcon.appiconset/Logo_256.png
A	Telegram-Mac/Assets.xcassets/EchoGramIcon.appiconset/Logo_32-1.png
A	Telegram-Mac/Assets.xcassets/EchoGramIcon.appiconset/Logo_32.png
A	Telegram-Mac/Assets.xcassets/EchoGramIcon.appiconset/Logo_512-1.png
A	Telegram-Mac/Assets.xcassets/EchoGramIcon.appiconset/Logo_512.png
A	Telegram-Mac/Assets.xcassets/EchoGramIcon.appiconset/Logo_64.png
A	Telegram-Mac/Assets.xcassets/EchoGramSoundCloud.imageset/Contents.json
A	Telegram-Mac/Assets.xcassets/EchoGramSoundCloud.imageset/icon.png
A	Telegram-Mac/Assets.xcassets/EchoGramSpotify.imageset/Contents.json
A	Telegram-Mac/Assets.xcassets/EchoGramSpotify.imageset/icon.png
A	Telegram-Mac/Assets.xcassets/EchoGramYandexMusic.imageset/Contents.json
A	Telegram-Mac/Assets.xcassets/EchoGramYandexMusic.imageset/icon.png
M	Telegram-Mac/Debug.xcconfig
M	Telegram-Mac/Info.plist
M	Telegram-Mac/Release.xcconfig
M	Telegram-Mac/account/SharedNotificationManager.swift
M	Telegram-Mac/app/AppDelegate.swift
M	Telegram-Mac/app/ApplicationContext.swift
A	Telegram-Mac/app/EchoGramBrowser.swift
A	Telegram-Mac/app/EchoGramMusic.swift
A	Telegram-Mac/app/EchoGramStreamer.swift
M	Telegram-Mac/app/MainViewController.swift
M	Telegram-Mac/packages-integration/hooks/ChatHistoryUIHooksInstall.swift
M	Telegram-Mac/packages-integration/hooks/TelegramLinksHooksInstall.swift
M	Telegram-Mac/updater/AppUpdateViewController.swift
M	Telegram-Mac/utils/InAppLinks.swift
M	Telegram-Mac/utils/UNUserNotifications.swift
M	Telegram.xcodeproj/project.pbxproj
M	core-xprojects/openssl/OpenSSLEncryption/build.sh
M	packages/ApiCredentials/Sources/ApiCredentials/Config.swift
M	packages/ChatUI/Sources/ChatUI/ChatInputMenuView.swift
M	packages/ChatUI/Sources/ChatUI/ChatInputSendButton.swift
M	packages/ChatUI/Sources/ChatUI/ChatInputView.swift
M	packages/ChatUI/Sources/ChatUI/ChatSyntheticContents.swift
M	packages/ColorPalette/Sources/ColorPalette/ColorPalette.swift
M	packages/GeneralRows/Sources/GeneralRows/GeneralActionButtonRowItem.swift
M	packages/GeneralRows/Sources/GeneralRows/GeneralRowItem.swift
M	packages/PeerMediaUI/Sources/PeerMediaUI/PeerMediaWebpageRowContent.swift
M	packages/SettingsUI/Sources/SettingsUI/AccountViewController.swift
M	packages/TGUIKit/Sources/TGSplitView.swift
M	packages/TGUIKit/Sources/TabBarView.swift
M	packages/TGUIKit/Tests/TGUIKitTests/SplitViewContinuousDragTests.swift
M	packages/TelegramTheme/Sources/TelegramTheme/Appearance.swift
M	packages/TelegramTheme/Sources/TelegramTheme/TelegramPresentationTheme.swift
```
