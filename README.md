# ichiseEdit (ipadTextEditor)

iPad 専用のテキストエディタ。要件は [docs/requirements.md](docs/requirements.md) を参照。

## 開発環境

- Xcode 26 以降 / iPadOS 16.0 以降
- プロジェクトファイルは [XcodeGen](https://github.com/yonaskolb/XcodeGen) で生成する(`project.yml` が原本)

## セットアップ

```sh
brew install xcodegen   # 未インストールの場合
xcodegen generate       # ichiseEdit.xcodeproj を生成
open ichiseEdit.xcodeproj
```

ファイル構成を変更した場合(ファイルの追加・移動・削除)は `xcodegen generate` を再実行する。

## ディレクトリ構成

```
project.yml                 # XcodeGen 定義(プロジェクト設定の原本)
ichiseEdit/
  App/                      # アプリエントリポイント(DocumentGroup)
  Document/                 # TextDocument(FileDocument, UTF-8)
  Editor/                   # EditorView / TextView(TextKit 2 ベースの UITextView ラッパー)
  Resources/                # Assets.xcassets(AppIcon, AccentColor)
  Support/                  # Info.plist(XcodeGen が生成・管理)
docs/
  requirements.md           # 要件定義書
```

## コマンドラインビルド

```sh
xcodebuild -project ichiseEdit.xcodeproj -scheme ichiseEdit \
  -destination 'generic/platform=iOS Simulator' build
```
