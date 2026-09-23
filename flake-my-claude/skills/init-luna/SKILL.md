---
name: init-luna
description: 弱いモデルで開始したメインセッションのコンテキストを抑え、情報取得をGPT-5.6 Luna workerへ委任しながらオーケストレーションする。明示呼び出し時のみ使用する。
---

# Init Luna

このSkillは現在のメインモデルを変更しない。明示的に呼び出された時点から、本文が現在のセッションコンテキストに保持されている間の後続作業にも適用する。

## Role

- メインエージェントは、思考、判断、作業分解、委任、worker結果の評価、競合解消、承認の取得、最終回答に注力する。
- メインセッションへ流入するコンテキストを抑えるため、作業はsub-agent主体で進める。実行前に、依存関係、対象範囲、Write対象を含む作業計画を作り、適切な粒度のwork packageへ分解する。
- 情報取得、実装、検証などのworkerは`gpt-5.6-luna`、reasoning effort `max`で起動する。モデルまたはeffortを指定できない場合は、別の設定へ黙って代替せず、制約をユーザーへ報告する。

## Context routing

- workerには、可能な限り少ない量ではなく、一度で担当作業を完了するための必要十分なコンテキストを渡す。
- 原則として`fork_turns: none`を使い、目的、担当範囲、既決事項、権限制約、入力の参照先、Write ownership、期待結果、検証方法、停止条件をself-containedに指定する。
- required worker model overrideを維持するため、root modelを継承するfull-history forkは使用しない。
- 大きなファイル内容をworker指示へ貼り付けず、共有filesystem上の正本ファイルと必要なsectionをパスで示す。worker自身に対象を絞って読ませる。
- recent conversationにしか存在しない決定や承認が必要な場合だけ、必要最小限のpositive `fork_turns`を使う。
- 複数workerには、それぞれの担当に必要なコンテキストだけを渡す。共通制約は短く共有し、他workerの担当情報や無関係なraw dataを混ぜない。
- 同じ長い固定情報を複数workerが必要とし、既存の正本を直接参照できない場合だけ、適用されるproject-local instructionsで許可されたscratch領域へtask-localなcontext fileを作成してパスを共有してよい。
- context fileは正本にせず、source path、既決事項、担当範囲、制約のindexとして使う。secretを含めず、sourceが変化した場合は古いcontext fileを使用しない。
- context fileの利用はworker側のinput tokensをゼロにしない。rootによる全文再掲とメインセッションへのノイズ流入を避ける目的で使用する。

## Information retrieval

- repository全体の無差別な探索、Web検索結果の収集、ページ全体のHTML、raw log、lock file、生成物、vendor treeなど、量が多くノイズを伴う情報取得はworkerへ委任する。
- メインエージェントは、判断に必要な対象を絞った情報を直接確認してよい。これには、workerの要約・diff・検証結果、対象ファイルや行範囲、Webページの対象領域・本文・表示結果、変更の意図や安全性を確認する限定的なdiffを含む。
- lock fileや生成物自体が変更対象または重要な検証証拠である場合は除外しない。workerに必要部分を整理させるか、メインエージェントが対象を絞って確認する。
- workerには、結論、根拠、変更対象、検証結果、失敗、不確実性、未完了事項を簡潔に返させる。大量のraw出力は、判断に必要な場合を除いて返させない。

## Write ownership

- メインエージェント自身によるWriteは禁止しない。workerの調査結果を受けてメインエージェントが実装するか、workerへ実装まで委任するかは、共有mutable state、作業量、handoffコスト、コンテキスト消費を考慮して決める。
- 内容と宛先が完全に確定し、ユーザーが確認・承認済みで、生成、変換、merge、format、整合判断が不要なWriteは、メインエージェントが直接実行する。
- 同一の一連作業で変更され得るファイル集合が重複するworkerを並行実行しない。別hunkを担当する場合でも、同じファイルを変更し得るなら並行実行しない。
- formatter、generator、lock file、共有設定などを介して間接的に変更範囲が重なる場合も、重複するWriteとして扱う。Write対象が完全に分離されている場合だけ並行実行し、判断できない場合は逐次実行する。

## Active workers

- worker稼働中、メインエージェントは新たな調査、Write、実装、検証を行わない。必要なworkerを起動したらidleになり、`wait_agent`で完了を待つ。
- workerへのmessage、follow-up、interrupt、ユーザーからのsteeringへの対応など、オーケストレーションに必要な操作は行ってよい。

## Approval and authority

- ユーザーへの質問、確認、承認要求は、ユーザーと直接やりとりしているメインセッションだけが行う。
- workerはユーザー判断が必要な境界を越えず、必要な判断、対象、影響、選択肢をメインエージェントへ返して停止する。
- メインエージェントはユーザーの回答を受けた後、自身で承認済みのWriteを行うか、承認内容を明示してworkerへ再委任する。
- delegationは依頼範囲や権限を拡張しない。commit、push、activation、外部変更などは、明示的に依頼または承認された場合だけ行う。
