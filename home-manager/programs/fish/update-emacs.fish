set -l base (ghq root)/github.com/so-vanilla
set -l repos aide flake-my-emacs nixos-configurations
set -l last_index (count $repos)
set -l original_dir (pwd)

for i in (seq (count $repos))
    set -l repo $repos[$i]
    set -l repo_path $base/$repo

    echo "=== $repo ==="

    if not cd $repo_path
        echo "Error: $repo_path に移動できません"
        cd $original_dir
        return 1
    end

    # ステージング済みファイルを記録
    set -l staged (git diff --cached --name-only)

    # ステージング済みがあればアンステージ
    if test (count $staged) -gt 0
        git reset HEAD -- $staged
    end

    # nix flake update
    if test $repo = nixos-configurations
        if not nix flake update my-emacs
            echo "Error: nix flake update my-emacs に失敗しました ($repo)"
            if test (count $staged) -gt 0
                git add $staged
            end
            cd $original_dir
            return 1
        end
    else
        if not nix flake update
            echo "Error: nix flake update に失敗しました ($repo)"
            if test (count $staged) -gt 0
                git add $staged
            end
            cd $original_dir
            return 1
        end
    end

    # flake.lock に差分があるか確認
    if not git diff --name-only flake.lock | string length -q
        echo "flake.lock に変更なし、スキップします"
        if test (count $staged) -gt 0
            git add $staged
        end
        continue
    end

    # commit & push
    set -l timestamp (date +%Y%m%d%H%M)
    git add flake.lock
    if not git commit -m "snapshot $timestamp"
        echo "Error: commit に失敗しました ($repo)"
        if test (count $staged) -gt 0
            git add $staged
        end
        cd $original_dir
        return 1
    end

    if not git push
        echo "Error: push に失敗しました ($repo)"
        if test (count $staged) -gt 0
            git add $staged
        end
        cd $original_dir
        return 1
    end

    # 記録したファイルを再ステージ
    if test (count $staged) -gt 0
        git add $staged
    end

    # GitHub伝播待ち (最後のリポジトリでは不要)
    if test $i -lt $last_index
        echo "GitHub伝播待ち (5秒)..."
        sleep 5
    end
end

cd $original_dir
echo "=== 完了 ==="
