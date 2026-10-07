(ns dotfiles.core
  (:require [babashka.cli :as cli]
            [babashka.fs :as fs]
            [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.set :as set]
            [clojure.string :as str])
  (:import [java.io PushbackReader]
           [java.nio.file Files LinkOption]
           [java.nio.file.attribute BasicFileAttributes]
           [java.time Instant]
           [java.util UUID]))

(defn fail [message] (throw (ex-info message {:exit 2})))
(defn absolute [p] (.normalize (.toAbsolutePath (fs/path p))))
(defn entry? [p] (fs/exists? p {:nofollow-links true}))

(defn canonical
  "Resolve existing ancestors and symlinks, including a missing final component."
  ([p] (canonical (absolute p) 0))
  ([p links]
   (when (> links 64) (fail (str "symlinkの循環を解決できません: " p)))
   (cond
     (fs/sym-link? p)
     (canonical (absolute (.resolve (fs/parent p) (fs/read-link p))) (inc links))
     (fs/exists? p) (fs/real-path p)
     (fs/parent p) (.resolve (canonical (fs/parent p) links) (fs/file-name p))
     :else p)))

(defn inside? [parent child] (.startsWith (fs/path child) (fs/path parent)))
(defn owned-link? [repo-root p]
  (and (fs/sym-link? p)
       (try (inside? repo-root (canonical p)) (catch Exception _ false))))

(defn read-edn [p]
  (try
    (with-open [r (PushbackReader. (io/reader (str p)))]
      (let [value (edn/read {:eof ::eof} r)]
        (when (or (= ::eof value) (not= ::eof (edn/read {:eof ::eof} r)))
          (fail (str "EDNは1つの値を指定してください: " p)))
        value))
    (catch Exception e (fail (str "EDNを読み込めません: " p " (" (ex-message e) ")")))))

(defn relative-path! [value label]
  (when-not (and (string? value) (not (str/blank? value))
                 (not (.isAbsolute (fs/path value)))
                 (not-any? #{".." "."} (map str (iterator-seq (.iterator (fs/path value))))))
    (fail (str label "は空でない相対パスを指定してください: " (pr-str value))))
  value)

(defn validate-target! [value]
  (when-not (and (vector? value) (= 2 (count value))
                 (contains? #{:home :config :data :state} (first value)))
    (fail (str "配置先は[base 相対パス]で指定してください: " (pr-str value))))
  (relative-path! (second value) "配置先"))

(defn validate-links! [links]
  (when-not (vector? links) (fail ":linksはvectorで指定してください"))
  (doseq [link links]
    (when-not (and (map? link) (empty? (set/difference (set (keys link))
                                                        #{:source :target :tree :optional})))
      (fail (str "不正なlink定義: " (pr-str link))))
    (relative-path! (:source link) "配置元")
    (validate-target! (:target link))
    (doseq [flag [:tree :optional] :when (contains? link flag)]
      (when-not (boolean? (get link flag)) (fail (str flag "はbooleanです"))))
    (when (and (:optional link) (not (:tree link)))
      (fail ":optionalはtreeにだけ指定できます"))))

(defn validate-manifest! [directory manifest]
  (when-not (and (map? manifest) (= 1 (:version manifest))
                 (= (fs/file-name directory) (:id manifest))
                 (not= "all" (:id manifest))
                 (re-matches #"[a-z][a-z0-9-]*" (:id manifest ""))
                 (vector? (:platforms manifest)) (seq (:platforms manifest))
                 (every? #{:macos :linux} (:platforms manifest))
                 (map? (:variants manifest)) (seq (:variants manifest))
                 (contains? (:variants manifest) (:default manifest))
                 (map? (:roots manifest))
                 (empty? (set/difference (set (keys manifest))
                                         #{:version :id :platforms :default :roots :links
                                           :platform-links :variants})))
    (fail (str "不正なmanifest: " directory)))
  (doseq [platform (:platforms manifest)]
    (when-not (and (vector? (get-in manifest [:roots platform]))
                   (seq (get-in manifest [:roots platform])))
      (fail (str "cleanup rootがありません: " (:id manifest) " " platform)))
    (doseq [target (get-in manifest [:roots platform])] (validate-target! target)))
  (validate-links! (:links manifest []))
  (doseq [[platform links] (:platform-links manifest)]
    (when-not (some #{platform} (:platforms manifest)) (fail "未対応OSのlink定義です"))
    (validate-links! links))
  (doseq [[division variant] (:variants manifest)]
    (when-not (and (string? division) (re-matches #"[a-z][a-z0-9-]*" division)
                   (map? variant) (= #{:links} (set (keys variant))))
      (fail (str "不正なdivision: " (:id manifest) " " division)))
    (validate-links! (:links variant)))
  (assoc manifest :directory (canonical directory)))

(defn registry [repo-root]
  (let [directory (fs/path repo-root "configs")]
    (when-not (fs/directory? directory) (fail "configsディレクトリがありません"))
    (into (sorted-map)
          (for [p (sort (fs/list-dir directory)) :when (fs/directory? p)]
            (do
              (when (fs/sym-link? p) (fail (str "configディレクトリは実体にしてください: " p)))
              (let [manifest (validate-manifest! p (read-edn (fs/path p "manifest.edn")))]
                [(:id manifest) manifest]))))))

(defn host-platform []
  (let [name (str/lower-case (System/getProperty "os.name"))]
    (cond (or (str/includes? name "mac") (str/includes? name "darwin")) :macos
          (str/includes? name "linux") :linux
          :else (fail "初版の自動配置はmacOSとLinux/WSLに対応しています"))))

(defn context [repo-root opts]
  (let [home-dir (absolute (or (:home opts) (System/getenv "HOME")
                               (System/getProperty "user.home")))
        platform (if-let [p (:platform opts)] (keyword p) (host-platform))
        xdg (fn [name fallback]
              (let [value (when-not (:home opts) (System/getenv name))]
                (if (str/blank? value) (fs/path home-dir fallback)
                    (do (when-not (.isAbsolute (fs/path value)) (fail (str name "は絶対パスです")))
                        (absolute value)))))]
    (when-not (#{:macos :linux} platform) (fail "--platformはmacosまたはlinuxです"))
    {:repo-root (canonical repo-root) :platform platform
     :bases {:home home-dir :config (xdg "XDG_CONFIG_HOME" ".config")
             :data (xdg "XDG_DATA_HOME" ".local/share")
             :state (xdg "XDG_STATE_HOME" ".local/state")}}))

(defn destination [ctx [base relative]] (absolute (fs/path (get-in ctx [:bases base]) relative)))

(defn selection [manifests platform tokens]
  (let [divisions (conj (set (mapcat #(keys (:variants %)) (vals manifests))) "default")]
    (vals
     (reduce
      (fn [selected token]
        (when-not (string? token) (fail "選択ファイルの要素は文字列です"))
        (let [[_ id requested] (re-matches #"([a-z][a-z0-9-]*)(?::([a-z][a-z0-9-]*))?" token)
              division (or requested "default")
              all? (= "all" id)
              priority (if all? 0 1)
              ids (if all? (filter #(some #{platform} (:platforms (get manifests %)))
                                   (keys manifests)) [id])]
          (when-not id (fail (str "不正な指定: " token)))
          (when-not (contains? divisions division) (fail (str "未知のdivision: " division)))
          (reduce
           (fn [result config-id]
             (let [manifest (get manifests config-id)]
               (when-not manifest (fail (str "未知のコンフィグ: " config-id)))
               (when-not (some #{platform} (:platforms manifest))
                 (fail (str config-id "は" (name platform) "に対応していません")))
               (let [resolved (if (contains? (:variants manifest) division)
                                division (:default manifest))
                     item {:id config-id :requested division :division resolved
                           :priority priority :manifest manifest}
                     previous (get result config-id)]
                 (cond
                   (nil? previous) (assoc result config-id item)
                   (> priority (:priority previous)) (assoc result config-id item)
                   (< priority (:priority previous)) result
                   (= resolved (:division previous)) result
                   :else (fail (str "divisionの指定が矛盾しています: " config-id))))))
           selected ids)))
      (sorted-map) tokens))))

(defn tree-files [directory]
  (mapcat (fn [p]
            (cond (fs/sym-link? p) (fail (str "配置元treeにsymlinkがあります: " p))
                  (fs/directory? p) (tree-files p)
                  (fs/regular-file? p) [p]
                  :else (fail (str "通常ファイル以外の配置元です: " p))))
          (sort (fs/list-dir directory))))

(defn expand-link [ctx manifest {:keys [source target tree optional]}]
  (let [src (absolute (fs/path (:directory manifest) source))
        dst (destination ctx target)]
    (when-not (inside? (:directory manifest) (canonical src))
      (fail (str "配置元がconfigの外にあります: " src)))
    (cond
      (and tree optional (not (entry? src))) []
      (and tree (fs/directory? src) (not (fs/sym-link? src)))
      (mapv (fn [file] {:source (canonical file)
                        :target (absolute (fs/path dst (fs/relativize src file)))})
            (tree-files src))
      tree (fail (str "配置元ディレクトリがありません: " src))
      (fs/regular-file? src) [{:source (canonical src) :target dst}]
      :else (fail (str "配置元ファイルがありません: " src)))))

(defn ancestors [p]
  (take-while some? (iterate fs/parent (fs/parent p))))

(defn scan-links [repo-root p]
  (cond
    (fs/sym-link? p) (if (owned-link? repo-root p) [p] [])
    (fs/directory? p) (mapcat #(scan-links repo-root %) (sort (fs/list-dir p)))
    :else []))

(defn stamp [p]
  (let [a (Files/readAttributes (fs/path p) BasicFileAttributes
                                (into-array LinkOption [LinkOption/NOFOLLOW_LINKS]))]
    {:key (str (.fileKey a)) :size (.size a) :modified (str (.lastModifiedTime a))
     :link (when (fs/sym-link? p) (str (fs/read-link p)))}))

(defn plan [ctx selected opts]
  (let [repo-root (:repo-root ctx)
        all-roots (vec (distinct (mapcat #(map (partial destination ctx)
                                               (get-in % [:manifest :roots (:platform ctx)])) selected)))
        roots (vec (remove (fn [p] (some #(and (not= p %) (inside? % p)) all-roots)) all-roots))
        links (if (:delete opts) []
                  (vec (mapcat (fn [{:keys [manifest division]}]
                                 (mapcat (partial expand-link ctx manifest)
                                         (concat (:links manifest)
                                                 (get-in manifest [:platform-links (:platform ctx)])
                                                 (get-in manifest [:variants division :links])))) selected)))
        targets (map :target links)]
    (doseq [root roots]
      (when (or (some #{root} (vals (:bases ctx)))
                (inside? (fs/path repo-root "configs") root))
        (fail (str "cleanup rootが広すぎるか配置元と重なっています: " root))))
    (doseq [a selected b selected :when (neg? (compare (:id a) (:id b)))
            x (get-in a [:manifest :roots (:platform ctx)])
            y (get-in b [:manifest :roots (:platform ctx)])]
      (let [x (destination ctx x) y (destination ctx y)]
        (when (or (inside? x y) (inside? y x))
          (fail (str "コンフィグのcleanup範囲が重なっています: " (:id a) " / " (:id b))))))
    (when-not (= (count targets) (count (distinct targets))) (fail "配置先が重複しています"))
    (doseq [target targets]
      (when-not (some #(inside? % target) roots) (fail (str "配置先がcleanup範囲外です: " target))))
    ;; Root ancestors must be real directories before any cleanup scan.
    (doseq [p (distinct (mapcat ancestors roots)) :when (entry? p)]
      (when (fs/sym-link? p)
        (fail (str "配置先の親symlinkを辿れません: " p)))
      (when-not (fs/directory? p)
        (fail (str "配置先の親がディレクトリではありません: " p))))
    (let [cleanup (vec (distinct (mapcat #(scan-links repo-root %) roots)))
          cleanup-set (set cleanup)
          conflicts (vec (filter #(and (entry? %)
                                       (not (some (fn [removed] (inside? removed %)) cleanup-set)))
                                 targets))]
      ;; Owned directory links, including nested Skill links, are unlinked before installing.
      (doseq [p (distinct (mapcat ancestors targets)) :when (entry? p)]
        (when (and (fs/sym-link? p) (not (contains? cleanup-set p)))
          (fail (str "配置先の親symlinkを辿れません: " p)))
        (when (and (not (fs/sym-link? p)) (not (fs/directory? p)))
          (fail (str "配置先の親がディレクトリではありません: " p))))
      (doseq [p conflicts]
        (when (fs/directory? p {:nofollow-links true}) (fail (str "配置先に実ディレクトリがあります: " p))))
      (when (and (seq conflicts) (not (or (:backup opts) (:check opts))))
        (fail (str "配置先が競合しています。退避する場合は--backupを指定してください: "
                   (str/join ", " conflicts))))
      {:roots roots :links links :cleanup (mapv #(hash-map :target % :stamp (stamp %)) cleanup)
       :conflicts (mapv #(hash-map :target % :stamp (stamp %)) conflicts)})))

(defn same-entry! [{:keys [target stamp]}]
  (when-not (and (entry? target) (= stamp (dotfiles.core/stamp target)))
    (fail (str "事前検査後に配置先が変更されました: " target))))

(defn make-parents! [p created]
  (when (and p (not (entry? p)))
    (make-parents! (fs/parent p) created)
    (fs/create-dir p)
    (swap! created conj p)
    (fs/set-posix-file-permissions p "rwx------")))

(defn apply-plan! [ctx {:keys [links cleanup conflicts]} opts]
  (let [removed (atom []) backed-up (atom []) installed (atom []) created (atom [])
        backup-dir (fs/path (get-in ctx [:bases :state]) "dotfiles/backups"
                             (str (System/currentTimeMillis) "-" (UUID/randomUUID)))
        restore-errors (atom [])]
    (try
      (doseq [{:keys [source]} links]
        (when-not (and (fs/regular-file? source) (= source (canonical source)))
          (fail (str "事前検査後に配置元が失われたかsymlinkに変わりました: " source))))
      (doseq [item cleanup]
        (same-entry! item)
        (fs/delete (:target item))
        (swap! removed conj item))
      (doseq [[i item] (map-indexed vector conflicts)]
        (same-entry! item)
        (let [backup (fs/path backup-dir (format "%04d-%s" i (fs/file-name (:target item))))]
          (make-parents! backup-dir created)
          (fs/move (:target item) backup)
          (swap! backed-up conj (assoc item :backup backup))))
      (doseq [{:keys [source target] :as link} links]
        (make-parents! (fs/parent target) created)
        (fs/create-sym-link target source)
        (swap! installed conj link))
      (when (seq @backed-up)
        (spit (str (fs/path backup-dir "manifest.edn"))
              (pr-str {:created (str (Instant/now))
                       :entries (mapv #(select-keys (update (update % :target str) :backup str)
                                                    [:target :backup]) @backed-up)}))
        (println "BACKUP" (str backup-dir)))
      (println (format "OK: %dリンク削除、%dファイル配置、%d件退避"
                       (count cleanup) (count links) (count conflicts)))
      0
      (catch Exception original
        (let [attempt (fn [f] (try (f) (catch Exception e (swap! restore-errors conj (ex-message e)))))]
          (doseq [{:keys [source target]} (reverse @installed)]
            (attempt #(if (and (fs/sym-link? target) (= (str source) (str (fs/read-link target))))
                        (fs/delete target) (fail (str "新リンクが変更されています: " target)))))
          (doseq [{:keys [target backup]} (reverse @backed-up)]
            (attempt #(do (when (entry? target) (fail (str "退避先を復元できません: " target)))
                          (fs/move backup target))))
          ;; Remove newly created empty directories before restoring old directory links.
          (doseq [p (reverse @created)]
            (when (and (not (fs/sym-link? p)) (fs/directory? p) (empty? (fs/list-dir p)))
              (attempt #(fs/delete p))))
          (doseq [{:keys [target stamp]} (reverse @removed)]
            (attempt #(do (when (entry? target) (fail (str "旧リンクを復元できません: " target)))
                          (fs/create-sym-link target (:link stamp)))))
          (throw (ex-info (str "配置に失敗しました: " (ex-message original)
                              (if (seq @restore-errors)
                                (str " / 復元失敗: " (str/join "; " @restore-errors))
                                " / 変更を復元しました")) {:exit 1} original)))))))

(defn check-plan [{:keys [links cleanup conflicts]}]
  (let [targets (set (map :target links))
        stale (remove #(contains? targets (:target %)) cleanup)
        missing (filter (fn [{:keys [target source]}]
                          (not (and (fs/sym-link? target)
                                    (try (= (canonical target) source)
                                         (catch Exception _ false))))) links)]
    (doseq [{:keys [target]} missing] (println "MISSING/DIFFERENT" (str target)))
    (doseq [{:keys [target]} stale] (println "STALE" (str target)))
    (doseq [{:keys [target]} conflicts] (println "CONFLICT" (str target)))
    (if (or (seq missing) (seq stale) (seq conflicts)) 1
        (do (println "OK: 配置は一致しています") 0))))

(def option-spec
  {:delete {:alias :d :coerce :boolean}
   :file {:alias :f :coerce :string}
   :list {:alias :l :coerce :boolean}
   :dry-run {:alias :n :coerce :boolean}
   :backup {:coerce :boolean}
   :check {:coerce :boolean}
   :home {:coerce :string}
   :platform {:coerce :string}
   :help {:alias :h :coerce :boolean}})

(defn help []
  (println "Usage: dotfiles [options] git fish | all | all:work")
  (println "  -f FILE       EDN vectorに列挙された設定を配置")
  (println "  -d            管理ディレクトリ内の所有リンクだけ削除")
  (println "  -l            有効な設定・division・配置先を一覧表示")
  (println "  -n, --dry-run 変更予定を表示（書き込みなし）")
  (println "  --backup      競合するファイル・他管理リンクを退避")
  (println "  --check       配置の一致を検査（書き込みなし）")
  (println "  --home DIR    配置先HOMEを変更（XDG環境変数を使用しない）")
  (println "  --platform OS macos / linux（省略時は自動判定）"))

(defn -main [repo-root args]
  (try
    (let [parsed (cli/parse-args args {:spec (assoc option-spec :selectors
                                                   {:coerce [:string] :positional true})
                                      :args->opts (repeat :selectors) :restrict true
                                      :restrict-args true :no-keyword-opts true})
          opts (dissoc (:opts parsed) :selectors)
          args (:selectors (:opts parsed))]
      (cond
        (or (:help opts) (and (empty? args) (not (:file opts)) (not (:list opts))
                             (not (:check opts)) (not (:delete opts)))) (do (help) 0)
        :else
        (do
          (when (> (count (filter opts [:list :check :delete])) 1)
            (fail "-l、--check、-dは同時に指定できません"))
          (when (and (or (:list opts) (:check opts)) (or (:backup opts) (:dry-run opts)))
            (fail "一覧・検査モードに--backup/--dry-runは指定できません"))
          (let [ctx (context repo-root opts)
                manifests (registry (:repo-root ctx))
                file-tokens (when (:file opts)
                              (let [value (read-edn (:file opts))]
                                (when-not (and (vector? value) (every? string? value)
                                               (every? #(not (re-matches #"all(?::.*)?" %)) value))
                                  (fail "選択ファイルは個別IDの文字列vectorです（all不可）"))
                                value))
                tokens (vec (concat file-tokens args))
                tokens (if (and (empty? tokens) (or (:list opts) (:check opts))) ["all"] tokens)
                _ (when (empty? tokens) (fail "対象コンフィグを指定してください"))
                selected (selection manifests (:platform ctx) tokens)]
            (doseq [{:keys [id requested division]} selected :when (not= requested division)]
              (println "FALLBACK" (str id ":" requested " -> " division)))
            (if (:list opts)
              (do
                (doseq [{:keys [id manifest]} selected]
                  (println id "divisions=" (str/join "," (sort (keys (:variants manifest))))
                           "platforms=" (str/join "," (map name (:platforms manifest)))
                           "roots=" (str/join "," (map #(str (destination ctx %))
                                                       (get-in manifest [:roots (:platform ctx)])))))
                0)
              (let [result (plan ctx selected opts)]
                (cond
                  (:check opts) (check-plan result)
                  (:dry-run opts)
                  (do (doseq [{:keys [target]} (:cleanup result)] (println "UNLINK" (str target)))
                      (doseq [{:keys [target]} (:conflicts result)] (println "BACKUP" (str target)))
                      (doseq [{:keys [target source]} (:links result)]
                        (println "LINK" (str target) "->" (str source)))
                      0)
                  :else (apply-plan! ctx result opts))))))))
    (catch Exception e
      (binding [*out* *err*] (println "ERROR:" (ex-message e)))
      (:exit (ex-data e) 2))))
