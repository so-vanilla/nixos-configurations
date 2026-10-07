(ns dotfiles.core-test
  (:require [babashka.fs :as fs]
            [clojure.test :refer [deftest is testing]]
            [dotfiles.core :as core])
  (:import [java.io StringWriter]
           [java.util UUID]))

(def project-root (core/canonical "."))

(defn put! [root relative value]
  (let [p (fs/path root relative)]
    (fs/create-dirs (fs/parent p))
    (spit (str p) value)
    p))

(defn add-config! [repo id]
  (put! repo (str "configs/" id "/manifest.edn")
        (pr-str {:version 1 :id id :platforms [:macos :linux] :default "default"
                 :roots {:macos [[:config id]] :linux [[:config id]]}
                 :links []
                 :variants {"default" {:links [{:source "default" :target [:config id] :tree true}]}
                            "work" {:links [{:source "work" :target [:config id] :tree true}]}}}))
  (put! repo (str "configs/" id "/default/config") "private")
  (put! repo (str "configs/" id "/work/config") "work"))

(defmacro with-fixture [[repo home] & body]
  `(let [scratch# (fs/path project-root ".local/test-runs" (str (UUID/randomUUID)))
         ~repo (fs/path scratch# "repo") ~home (fs/path scratch# "home")]
     (fs/create-dirs ~repo)
     (fs/create-dirs ~home)
     (add-config! ~repo "alpha")
     (try ~@body (finally (fs/delete-tree scratch#)))))

(defn run-cli [repo home & args]
  (let [out (StringWriter.) err (StringWriter.)]
    (binding [*out* out *err* err]
      {:exit (core/-main repo (concat ["--home" (str home) "--platform" "linux"] args))
       :out (str out) :err (str err)})))

(defn linked-to? [link target]
  (and (fs/sym-link? link) (= (core/canonical link) (core/canonical target))))

(deftest install-repeat-switch-and-remove
  (with-fixture [repo home]
    (let [target (fs/path home ".config/alpha/config")]
      (is (= 0 (:exit (run-cli repo home "alpha"))))
      (is (linked-to? target (fs/path repo "configs/alpha/default/config")))
      (is (= 0 (:exit (run-cli repo home "alpha"))))
      (is (= 0 (:exit (run-cli repo home "--check" "alpha"))))
      (is (= 0 (:exit (run-cli repo home "alpha:work"))))
      (is (= "work" (slurp (str target))))
      (is (= 0 (:exit (run-cli repo home "alpha" "-d"))))
      (is (not (core/entry? target))))))

(deftest removed-skill-and-broken-relative-links-are-cleaned
  (with-fixture [repo home]
    (let [source (put! repo "configs/alpha/default/skills/deleted/SKILL.md" "skill")
          target (fs/path home ".config/alpha/skills/deleted/SKILL.md")
          broken (fs/path home ".config/alpha/old.fish")]
      (is (= 0 (:exit (run-cli repo home "alpha"))))
      (fs/delete source)
      (is (fs/sym-link? target))
      (is (not (fs/exists? target)))
      (fs/create-sym-link broken (fs/relativize (fs/parent broken) (fs/path repo "deleted.fish")))
      (is (= 1 (:exit (run-cli repo home "--check" "alpha"))))
      (is (= 0 (:exit (run-cli repo home "alpha"))))
      (is (not (core/entry? target)))
      (is (not (core/entry? broken)))
      (is (= 0 (:exit (run-cli repo home "--check" "alpha")))))))

(deftest delete-does-not-require-payload
  (with-fixture [repo home]
    (is (= 0 (:exit (run-cli repo home "alpha"))))
    (fs/delete-tree (fs/path repo "configs/alpha/default"))
    (is (= 0 (:exit (run-cli repo home "-d" "alpha"))))
    (is (not (core/entry? (fs/path home ".config/alpha/config"))))))

(deftest cleanup-preserves-manual-files-other-repositories-and-other-configs
  (with-fixture [repo home]
    (add-config! repo "beta")
    (is (= 0 (:exit (run-cli repo home "all"))))
    (let [manual (put! home ".config/alpha/manual.conf" "keep")
          sibling (put! (fs/path (fs/parent repo) "repo-other") "settings" "external")
          external (fs/path home ".config/alpha/external")
          cycle (fs/path home ".config/alpha/cycle")
          beta (fs/path home ".config/beta/config")]
      (fs/create-sym-link external sibling)
      (fs/create-sym-link cycle "cycle")
      (is (= 0 (:exit (run-cli repo home "-d" "alpha"))))
      (is (= "keep" (slurp (str manual))))
      (is (fs/sym-link? external))
      (is (fs/sym-link? cycle))
      (is (fs/sym-link? beta)))))

(deftest all-work-fallback-explicit-override-and-platform-filter
  (with-fixture [repo home]
    (let [common {:version 1 :id "common" :platforms [:macos :linux] :default "default"
                  :roots {:macos [[:config "common"]] :linux [[:config "common"]]}
                  :links [{:source "shared" :target [:config "common"] :tree true}]
                  :variants {"default" {:links []}}}]
      (put! repo "configs/common/manifest.edn" (pr-str common))
      (put! repo "configs/common/shared/config" "shared")
      (put! repo "configs/macos-only/manifest.edn"
            (pr-str (assoc common :id "macos-only" :platforms [:macos]
                           :roots {:macos [[:config "macos-only"]]}
                           :links [{:source "shared" :target [:config "macos-only"] :tree true}])))
      (put! repo "configs/macos-only/shared/config" "mac")
      (let [result (run-cli repo home "all:work")]
        (is (= 0 (:exit result)))
        (is (re-find #"FALLBACK common:work -> default" (:out result))))
      (is (= "work" (slurp (str (fs/path home ".config/alpha/config")))))
      (is (= "shared" (slurp (str (fs/path home ".config/common/config")))))
      (is (not (core/entry? (fs/path home ".config/macos-only"))))
      (is (= 0 (:exit (run-cli repo home "alpha" "all:work"))))
      (is (= "private" (slurp (str (fs/path home ".config/alpha/config")))))
      (is (= 2 (:exit (run-cli repo home "macos-only"))))
      (is (= 2 (:exit (run-cli repo home "all:wrok"))))
      (is (= 2 (:exit (run-cli repo home "alpha" "alpha:work")))))))

(deftest enumeration-files-are-data-only
  (with-fixture [repo home]
    (let [file (put! (fs/parent repo) "selection.edn" "[\"alpha:work\"]")]
      (is (= 0 (:exit (run-cli repo home "-f" (str file))))))
    (doseq [content ["[\"all\"]" "{:config \"alpha\"}" "[alpha]" "[\"alpha\"] []"
                     "#=(System/exit 99)" "[\"unknown\"]"]]
      (let [file (put! (fs/parent repo) "invalid.edn" content)]
        (is (= 2 (:exit (run-cli repo home "-f" (str file)))))
        (is (= "work" (slurp (str (fs/path home ".config/alpha/config")))))))))

(deftest dry-run-and-preflight-errors-do-not-mutate
  (with-fixture [repo home]
    (is (= 0 (:exit (run-cli repo home "alpha" "--dry-run"))))
    (is (not (core/entry? (fs/path home ".config"))))
    (add-config! repo "beta")
    (is (= 0 (:exit (run-cli repo home "alpha"))))
    (put! home ".config/beta/config" "manual")
    (let [stamp (core/stamp (fs/path home ".config/alpha/config"))]
      (is (= 2 (:exit (run-cli repo home "all:work"))))
      (is (= stamp (core/stamp (fs/path home ".config/alpha/config"))))
      (is (= "manual" (slurp (str (fs/path home ".config/beta/config")))))
      (fs/delete (fs/path repo "configs/beta/work/config"))
      (fs/delete (fs/path repo "configs/beta/work"))
      (is (= 2 (:exit (run-cli repo home "--backup" "all:work"))))
      (is (= stamp (core/stamp (fs/path home ".config/alpha/config")))))))

(deftest backup-preserves-file-and-foreign-link
  (with-fixture [repo home]
    (put! home ".config/alpha/config" "manual")
    (is (= 0 (:exit (run-cli repo home "--backup" "alpha"))))
    (let [backups (fs/glob (fs/path home ".local/state/dotfiles/backups") "*/0000-config")]
      (is (= 1 (count backups)))
      (is (= "manual" (slurp (str (first backups))))))
    (fs/delete (fs/path home ".config/alpha/config"))
    (fs/create-sym-link (fs/path home ".config/alpha/config") "/nix/store/missing-generation/config")
    (is (= 2 (:exit (run-cli repo home "alpha"))))
    (is (= 0 (:exit (run-cli repo home "--backup" "alpha"))))
    (let [backups (fs/glob (fs/path home ".local/state/dotfiles/backups") "*/0000-config")]
      (is (some #(and (fs/sym-link? %)
                      (= "/nix/store/missing-generation/config" (str (fs/read-link %)))) backups)))))

(deftest directory-symlinks-are-not-traversed
  (with-fixture [repo home]
    (let [outside (put! (fs/parent repo) "outside/config" "keep")
          root (fs/path home ".config/alpha")]
      (fs/create-dirs (fs/parent root))
      (fs/create-sym-link root (fs/parent outside))
      (is (= 2 (:exit (run-cli repo home "--backup" "alpha"))))
      (is (= "keep" (slurp (str outside))))
      (fs/delete root)
      (fs/create-sym-link root (fs/path repo "configs/alpha/default"))
      (is (= 0 (:exit (run-cli repo home "alpha"))))
      (is (not (fs/sym-link? root)))
      (is (= "private" (slurp (str (fs/path repo "configs/alpha/default/config"))))))))

(deftest file-root-can-be-reinstalled
  (with-fixture [repo home]
    (put! repo "configs/alpha/manifest.edn"
          (pr-str {:version 1 :id "alpha" :platforms [:linux] :default "default"
                   :roots {:linux [[:home ".app/AGENTS.md"]]}
                   :links [{:source "default/config" :target [:home ".app/AGENTS.md"]}]
                   :variants {"default" {:links []}}}))
    (is (= 0 (:exit (run-cli repo home "alpha"))))
    (is (= 0 (:exit (run-cli repo home "alpha"))))))

(deftest rollback-restores-previous-links-and-backups
  (with-fixture [repo home]
    (put! repo "configs/alpha/default/second" "second")
    (put! repo "configs/alpha/work/second" "work-second")
    (is (= 0 (:exit (run-cli repo home "alpha"))))
    (fs/delete (fs/path home ".config/alpha/second"))
    (put! home ".config/alpha/second" "manual")
    (let [original fs/create-sym-link calls (atom 0)
          result (with-redefs [fs/create-sym-link
                              (fn [& args]
                                (if (= 2 (swap! calls inc)) (throw (ex-info "injected I/O failure" {}))
                                    (apply original args)))]
                   (run-cli repo home "--backup" "alpha:work"))]
      (is (= 1 (:exit result)))
      (is (re-find #"変更を復元しました" (:err result)))
      (is (= "private" (slurp (str (fs/path home ".config/alpha/config")))))
      (is (= "manual" (slurp (str (fs/path home ".config/alpha/second"))))))))

(deftest changed-plan-is-rejected-without-deleting-new-data
  (with-fixture [repo home]
    (run-cli repo home "alpha")
    (let [ctx (core/context repo {:home (str home) :platform "linux"})
          selected (core/selection (core/registry repo) :linux ["alpha:work"])
          result (core/plan ctx selected {})
          target (fs/path home ".config/alpha/config")]
      (fs/delete target)
      (spit (str target) "changed-after-preflight")
      (is (thrown? Exception (core/apply-plan! ctx result {})))
      (is (= "changed-after-preflight" (slurp (str target)))))))

(deftest bundled-configs-and-manifests-are-portable
  (with-fixture [repo home]
    (is (= 0 (:exit (run-cli project-root home "all:work"))))
    (is (= 0 (:exit (run-cli project-root home "--check" "all:work"))))
    (is (= "zed.exe --wait"
           (second (re-find #"editor = \"([^\"]+)\""
                            (slurp (str (fs/path home ".config/git/config")))))))
    (is (not (core/entry? (fs/path home ".config/direnv"))))
    (is (not (core/entry? (fs/path home ".config/fish/functions/update-nix.fish"))))
    (is (not (core/entry? (fs/path home ".config/zed"))))))

(deftest missing-source-after-preflight-preserves-old-links
  (with-fixture [repo home]
    (run-cli repo home "alpha")
    (let [ctx (core/context repo {:home (str home) :platform "linux"})
          selected (core/selection (core/registry repo) :linux ["alpha:work"])
          result (core/plan ctx selected {})
          target (fs/path home ".config/alpha/config")
          before (core/stamp target)]
      (fs/delete (fs/path repo "configs/alpha/work/config"))
      (is (thrown? Exception (core/apply-plan! ctx result {})))
      (is (= before (core/stamp target))))))

(deftest invalid-options-and-mode-combinations-do-not-write
  (with-fixture [repo home]
    (doseq [args [["--unknown" "alpha"] ["alpha" "--unknown"]
                  ["--check" "-d" "alpha"] ["-l" "--backup"]
                  ["--platform" "windows" "alpha"]]]
      (is (= 2 (:exit (apply run-cli repo home args)))))
    (is (not (core/entry? (fs/path home ".config"))))))

(deftest nested-owned-skill-directory-link-is-converted
  (with-fixture [repo home]
    (put! repo "configs/alpha/default/skills/example/SKILL.md" "skill")
    (let [target (fs/path home ".config/alpha/skills/example")]
      (fs/create-dirs (fs/parent target))
      (fs/create-sym-link target (fs/path repo "configs/alpha/default/skills/example"))
      (is (= 0 (:exit (run-cli repo home "alpha"))))
      (is (not (fs/sym-link? target)))
      (is (fs/sym-link? (fs/path target "SKILL.md")))
      (is (= "skill" (slurp (str (fs/path repo "configs/alpha/default/skills/example/SKILL.md"))))))))

(deftest rollback-restores-an-owned-directory-link
  (with-fixture [repo home]
    (put! repo "configs/alpha/work/second" "work-second")
    (let [target (fs/path home ".config/alpha")
          original-source (fs/path repo "configs/alpha/default")
          original fs/create-sym-link calls (atom 0)]
      (fs/create-dirs (fs/parent target))
      (fs/create-sym-link target original-source)
      (let [result (with-redefs [fs/create-sym-link
                                (fn [& args]
                                  (if (= 2 (swap! calls inc)) (throw (ex-info "injected I/O failure" {}))
                                      (apply original args)))]
                     (run-cli repo home "alpha:work"))]
        (is (= 1 (:exit result)))
        (is (re-find #"変更を復元しました" (:err result)))
        (is (fs/sym-link? target))
        (is (= (str original-source) (str (fs/read-link target))))
        (is (= "private" (slurp (str (fs/path target "config")))))))))
