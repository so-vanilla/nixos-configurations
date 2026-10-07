# Dotfiles

編集可能な設定本体へ、Babashkaでファイル単位のsymlinkを配置する。
既存Nix設定は `nixos-configuration/` に保存し、Home Managerの内容・有効化を維持している。

## 使い方

Babashka `1.13.220` で検証済み。`bb` をPATHへ用意する。
配置処理にはNix・Git・ネットワーク接続を必要とせず、アプリやパッケージのインストールは行わない。
アプリはmacOSのNix／mise／brew、またはWSLのパッケージマネージャーなどで導入する。

```sh
./bin/dotfiles -l
./bin/dotfiles --dry-run git fish
./bin/dotfiles git fish
./bin/dotfiles git:work
./bin/dotfiles all
./bin/dotfiles all:work
./bin/dotfiles -f selections/macos.edn
./bin/dotfiles -f selections/work.edn
./bin/dotfiles -d git
./bin/dotfiles --check
```

オプションは対象指定の前後に書ける。実行場所に関係なく、スクリプトの実体の位置からリポジトリを取得する。
PATHへ追加する場合は、このリポジトリの `bin` を追加するか、`bin/dotfiles` へのsymlinkを作る。
ファイルを別の場所へコピーして実行する方式には対応しない。

`all` は実行OSで利用可能なコンフィグの全てを選択する。macOS専用のAeroSpace・VS Code・ZedはWSL/Linuxでは含まれない。
個別に非対応のコンフィグを指定した場合はエラーになる。Windows版Zedは `configs/zed/win/` に保存しているが、初版では自動配置しない。

divisionを省略すると各コンフィグのdefaultを使う。`work` がないものはdefaultへフォールバックし、解決結果を表示する。
全manifestに存在しないdivision名は、誤字を見逃さないためエラーにする。
`all:work git` のような指定では個別指定が優先する。個別指定同士で異なるdivisionを指定するとエラーになる。

選択ファイルは個別指定の文字列vectorだけを受け付ける。`all`、map、任意コードは受け付けない。
ファイル指定と直接指定は併用できる。異なるdivisionの個別指定が重なった場合はエラーになる。

```edn
["git:work" "fish:work" "bat" "btop"]
```

## 配置・削除・競合

通常の実行も `-d` も、対象コンフィグが宣言した配置先のrootを探索し、**このリポジトリ配下を指すsymlinkを全て掃除する**。
リンク先ファイルが削除済みでも、絶対・相対symlinkの両方を判定する。
通常の実行ではその後、現在の配置元ファイルへのsymlinkを張る。`-d` は掃除だけを行い、divisionにかかわらず対象IDのリンクを削除する。

例えば `configs/codex/shared/skills/example/` を削除して `./bin/dotfiles codex` を再実行すると、
配置先に残ったそのSkillのファイルリンクも削除される。現在の配置元に存在するファイルの一覧だけを削除対象にはしない。
空になった実ディレクトリは保持する。Skillの定義ファイルが消えるため、そのSkillは利用対象から外れる。

通常ファイル、他リポジトリのリンク、Nix storeへのリンク、対象外の設定は掃除しない。
ディレクトリsymlinkの内部は探索せず、リンク自体の所有者を判定する。
このリポジトリへの既存ディレクトリリンクは、掃除後に実ディレクトリとファイルリンクへ置き換える。
他管理のディレクトリsymlinkを親として書き込むことや、実ディレクトリをファイルで置き換えることは拒否する。

既存ファイル・他管理のリンクとの競合、不足した配置元、配置先重複は、全対象について書き込み前に検査する。
競合ファイルを退避して置換する場合だけ `--backup` を付ける。

```sh
./bin/dotfiles --dry-run --backup git
./bin/dotfiles --backup git
```

退避先は `$XDG_STATE_HOME/dotfiles/backups/`、未設定時は `~/.local/state/dotfiles/backups/`。
各退避先の `manifest.edn` に元のパスを記録する。symlinkはリンクのまま退避する。
途中で配置に失敗した場合は、その実行で削除したリンクと退避した競合物の復元を試み、復元できなかったものを報告する。
`--backup` は既存の管理者を無効化する操作を含まない。

`--check` は期待するリンク、古いリンク、競合を調べる。終了コードは一致なら0、配置の差異やI/O失敗なら1、引数・事前検査エラーなら2。
`--dry-run`・`-l`・`--check` は書き込みを行わない。

## 設定内容とローカル編集

- Git・Fishはdefault／workを持つ。workのeditorは `zed.exe`、Gitのユーザー名・メールはプライベートの値を初期値とする。
- GitのOS別credential helperはmacOSが `gh`、Linux/WSLが `store`。GPGはPATH上の `gpg` を使用する。
- workファイルを仕事用に編集した差分は、ユーザーがcommitせず運用する。
- Fishには通常コマンドによる初期化、既存のalias・abbr・`cy`・Pureを移植した。
- direnv、Nix専用の関数・初期化・環境変数・固定storeパスは新設定から除去した。
- Claude Code・Codexは指示と宣言済みSkillsを移植した。認証情報、履歴、Codexの実行時 `config.toml` は配置対象外。
- Fishの `fish_variables`、GPGの鍵など、実行時データは配置対象外。
- テーマとPureは同梱済み。Fishの色は起動時にテーマから読み込む。アプリや拡張機能の導入、`bat cache --build` は必要に応じて別途行う。
- VS Codeの設定は既存のCatppuccin拡張を参照する。拡張自体はこのスクリプトでは導入しない。

配置したsymlink経由の編集は配置元ファイルを変更する。アプリが保存時にリンクを通常ファイルへ置換した場合は、
`--check` で検出できる。差分を配置元へ取り込んでから、必要に応じて `--backup` で再配置する。

## コンフィグの追加

`configs/<id>/manifest.edn` と設定本体を追加する。配置エンジンへのID追加は不要。
OSとdivisionは独立しており、全divisionで同じcleanup範囲を使う。

```edn
{:version 1
 :id "example"
 :platforms [:macos :linux]
 :default "default"
 :roots {:macos [[:config "example"]]
         :linux [[:config "example"]]}
 :links [{:source "shared" :target [:config "example"] :tree true}]
 :variants {"default" {:links [{:source "default" :target [:config "example"] :tree true}]}
            "work" {:links [{:source "work" :target [:config "example"] :tree true}]}}}
```

`:source` はmanifestディレクトリ内の相対パス。`:target` は `[base 相対パス]`。
baseは `:home`・`:config`・`:data`・`:state` を使える。XDGの各環境変数を尊重し、未設定時は標準のHOME配下へ配置する。
macOSのApplication Supportは `[:home "Library/Application Support/..."]` として明示する。

`:tree true` はディレクトリ内の通常ファイルを再帰的にファイル単位で配置する。配置元treeのsymlinkは拒否する。
`:optional true` をtreeに付けると、配置元ディレクトリを丸ごと削除しても掃除を実行できる。Skillsのtreeで使用している。
単一ファイルの配置には `:tree` を付けない。全配置先は宣言したcleanup rootの配下に収める。
OS固有の追加リンクは `:platform-links {:macos [...] :linux [...]}` で指定する。
同じ配置先へ複数の配置元を重ねることはできない。

## Nixの継続運用

既存Nix設定は内容を変えず移動した。Home Managerによる設定配置・direnvなどの既存機能も継続している。
新dotfilesとの同期は自動で行わず、当面の実環境の編集はHome Manager側で行う。
同じ配置先へ新dotfilesを適用する時は、先にNix側の管理との競合を解消する。
GitHub Actionsのlock更新・snapshot補助スクリプトは新しいlockの場所へ対応済み。

```sh
nix flake update --flake ./nixos-configuration
sudo darwin-rebuild switch --flake ./nixos-configuration#chocolate
HM_USERNAME=your-user HM_GIT_EMAIL=your-email home-manager switch --impure --flake ./nixos-configuration#work
```

保存したHome Manager内の `update-nix` 関数は、従来のroot構成と処理をそのまま保持している。
新構成では上の明示コマンドを使う。関数の再設計は後のHome Manager変更時に行う。

## 開発・検証

```sh
bb test
./bin/dotfiles --home .local/example-home --platform linux all:work
./bin/dotfiles --home .local/example-home --platform linux --check all:work
```

`--home` を明示するとそのHOME配下へ配置し、実環境のXDG環境変数を使わない。
`--platform` は配置先OSの解決だけを切り替える。Linuxの実機動作をエミュレートするものではない。
テストはignore済みの `.local/test-runs/` 内で行い、実際のHOMEへ配置しない。
