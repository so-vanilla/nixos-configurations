set -l repo_path (ghq root)/github.com/so-vanilla/nixos-configurations
set -l original_dir (pwd)

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

set -l os (uname -s)

if test $os = Linux
    # NixOS: firewall/default.nix をステージしてから rebuild
    git add hosts/ThinkPadX13/networking/firewall/default.nix

    if not nix flake update
        echo "Error: nix flake update に失敗しました"
        git reset HEAD -- hosts/ThinkPadX13/networking/firewall/default.nix
        if test (count $staged) -gt 0
            git add $staged
        end
        cd $original_dir
        return 1
    end

    if not sudo nixos-rebuild switch --flake .#vanilla
        echo "Error: nixos-rebuild に失敗しました"
        git reset HEAD -- hosts/ThinkPadX13/networking/firewall/default.nix
        if test (count $staged) -gt 0
            git add $staged
        end
        cd $original_dir
        return 1
    end

    git reset HEAD -- hosts/ThinkPadX13/networking/firewall/default.nix

else if test $os = Darwin
    if not nix flake update
        echo "Error: nix flake update に失敗しました"
        if test (count $staged) -gt 0
            git add $staged
        end
        cd $original_dir
        return 1
    end

    if not , home-manager switch --flake .#work --impure
        echo "Error: home-manager switch に失敗しました"
        if test (count $staged) -gt 0
            git add $staged
        end
        cd $original_dir
        return 1
    end

else
    echo "Error: サポートされていないOS ($os)"
    if test (count $staged) -gt 0
        git add $staged
    end
    cd $original_dir
    return 1
end

# flake.lock に差分があるか確認
if not git diff --name-only flake.lock | string length -q
    echo "flake.lock に変更なし、スキップします"
    if test (count $staged) -gt 0
        git add $staged
    end
    cd $original_dir
    return 0
end

# commit & push
set -l timestamp (date +%Y%m%d%H%M)
git add flake.lock
if not git commit -m "snapshot $timestamp"
    echo "Error: commit に失敗しました"
    if test (count $staged) -gt 0
        git add $staged
    end
    cd $original_dir
    return 1
end

if not git push
    echo "Error: push に失敗しました"
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

cd $original_dir
echo "=== 完了 ==="
