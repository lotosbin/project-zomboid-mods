;; bin2_modpack_update.fnl
;; 更新 bin2_modpack require 列表
;; 用法: fennel bin2_modpack_update.fnl

;; 读取文件内容
(fn read-file [path]
  (let [f (io.open path "r")
        content (if f (f:read "*a") "")
        _ (if f (f:close))]
    content))

;; 写入文件
(fn write-file [path content]
  (let [file (io.open path "w")]
    (file:write content)
    (file:close)))

;; 从服务器 ini 获取模组列表
(fn get-server-mods [server-ini-path]
  (let [content (read-file server-ini-path)
        mods-line (content:match "Mods=([^\n]+)")
        mods []]
    (when mods-line
      (let [cleaned (mods-line:gsub ";" "\n")]
        (for [i 1 (# (cleaned:gmatch "[^\n]+"))]
          (let [mod (cleaned:match "([^\n]+)" i)]
            (when mod
              (let [trimmed (mod:match "^%s*(.-)%s*$")]
                (when (# trimmed > 0)
                  (table.insert mods trimmed))))))))
    (table.sort mods)
    mods))

;; 从 mod.info 获取 require 列表
(fn get-require-mods [mod-info-path]
  (let [content (read-file mod-info-path)
        require-line (content:match "require=([^\n]+)")
        mods []]
    (when require-line
      (let [cleaned (require-line:gsub "[\\,\n]" " ")]
        (for [i 1 (# (cleaned:gmatch "[^%s]+"))]
          (let [mod (cleaned:match "([^%s]+)" i)]
            (when (and mod (# mod > 0) (mod:match "^%a") (not (mod:match "^\\")))
              (let [trimmed (mod:match "^%s*(.-)%s*$")]
                (when (# trimmed > 0)
                  (table.insert mods trimmed)))))))
    (table.sort mods)
    mods))

;; 比较两个列表
(fn compare-lists [list1 list2]
  (let [set2 {}
        diff-added {}
        diff-removed {}]
    (each [_ v (ipairs list2)] (tset set2 v true))
    (each [_ v (ipairs list1)] (when (not set2[v]) (tset diff-removed v true)))
    (let [set1 {}]
      (each [_ v (ipairs list1)] (set set1[v] true))
      (each [_ v (ipairs list2)] (when (not set1[v]) (tset diff-added v true))))
    (let [result-added []]
      (each [k _ (pairs diff-added)] (table.insert result-added k))
      (table.sort result-added)
      (let [result-removed []]
        (each [k _ (pairs diff-removed)] (table.insert result-removed k))
        (table.sort result-removed)
        {:added result-added :removed result-removed}))))

;; 主函数
(fn main [args]
  (let [server-ini (or (. args 1) "/Volumes/StorageMacMini2/liubinbin/Yuanjingtech/gamer/project-zomboid/Zomboid/Server/penglai.ini")
        mod-info-path "./bin2_b42/Contents/mods/bin2_modpack/42.15.0/mod.info"
        changelog-path "./bin2_b42/Contents/mods/bin2_modpack/42.15.0/Changelog.txt"

        server-mods (get-server-mods server-ini)
        require-mods (get-require-mods mod-info-path)
        diff (compare-lists server-mods require-mods)]

    (print "=== 服务器新增 ===")
    (each [_ v (ipairs diff.added)] (print v))

    (print "\n=== 服务器移除 ===")
    (each [_ v (ipairs diff.removed)] (print v))

    (print "\n请手动更新 mod.info require= 列表")

    ;; 读取 changelog 并在 [ ALERT_CONFIG ] 后插入新日志
    (let [changelog (read-file changelog-path)
          today (os.date "%m/%d/%Y")
          new-entry (string.format "[ %s ]\n- 添加模组: %s\n- 移除模组: %s\n- 更新 modversion\n[ ------ ]\n\n"
            today
            (table.concat diff.added ", ")
            (table.concat diff.removed ", "))
          ;; 在 ALERT_CONFIG 块之后插入新日志
          updated-changelog (changelog:gsub "([ ALERT_CONFIG ].-[ ------ ])(\n)"
                                               "%1\n" .. new-entry))]
      (write-file changelog-path updated-changelog)
      (print "\n已更新 Changelog.txt"))))

(main args)
