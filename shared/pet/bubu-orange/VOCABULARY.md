# 橙色卜卜背词库

将词库保存为 `vocabulary.json`：

- macOS：`~/Library/Application Support/io.github.mayday-materials.orange-bubu-quota-panel/vocabulary.json`
- Windows：`%APPDATA%\OrangeBubuQuotaPanel\vocabulary.json`

也可设置 `BUBU_VOCABULARY_PATH` 指向任意 JSON 文件。根节点可直接是数组，也可使用本目录的 `vocabulary-template.json` 中的 `{ "words": [...] }` 结构。

每个单词需要 `word` 与 `meaning`；`id`、`phonetic`、`example` 可选。`definition` 或 `translation` 也可替代 `meaning`。

学习记录只保存在同一应用目录的 `vocabulary-progress.json`。点击“记住啦”会安排 1、3、7、30 天后的复习；“等会再学”会延后 15 分钟，不计为错误。
