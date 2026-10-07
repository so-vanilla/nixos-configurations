# 設定資材の出典

初版は、既存リポジトリの宣言と2026-09-30時点のmacOS配置を照合して作成した。
work実機の配置は未取得。work版は既存Home Managerの宣言に基づき、Gitのidentityはユーザー指定のプライベート初期値とする。

| 資材 | 出典・変更 |
|---|---|
| Git / Fish | 保存した `nixos-configuration/home-manager/programs/` とmacOS生成結果。OS・work差分を移植し、Nix専用機能・direnvを除去 |
| AeroSpace | 既存リポジトリの `aerospace.toml` を内容変更なしで保存 |
| Zed macOS / Windows | 既存リポジトリの4ファイルを内容変更なしで保存。Windows自動配置は対象外 |
| bat / btop / eza / Fishのテーマ | 現在配置されているCatppuccin Latte資材を保存。btop設定・ezaテーマの末尾の空行だけ正規化 |
| GPG / VS Code / marksman | 既存の宣言またはmacOS生成結果に基づく通常の設定ファイル |
| Claude Code / Codex | 保存した `flake-my-claude` の指示・Skills。Claude Codeの宣言済みskillOverridesも移植 |
| Pure | 現在導入されているPureのfunctions・conf.dを同梱。Nix prompt専用関数とその呼び出し・既定値を削除 |

Pureの取得元は [pure-fish/pure](https://github.com/pure-fish/pure)。同梱版のversionは `fish/vendor/pure/conf.d/pure.fish`、ライセンスは `fish/vendor/pure/LICENSE` を参照。
Pureの更新・アンインストールにはFisherを使わず、この同梱資材とmanifestを変更して再配置する。

Catppuccin資材の出典とライセンス:

- [bat](https://github.com/catppuccin/bat): `bat/LICENSE.catppuccin`
- [btop](https://github.com/catppuccin/btop): `btop/LICENSE.catppuccin`
- [eza](https://github.com/catppuccin/eza): `eza/LICENSE.catppuccin`
- [Fish](https://github.com/catppuccin/fish): `fish/LICENSE.catppuccin`

スクリプトは配備時にこれらをダウンロードしない。
