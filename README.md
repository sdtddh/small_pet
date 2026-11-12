# SmallPet 🐾

一隻用 **Swift + AppKit** 寫的 macOS 桌面小貓。牠會自己走路、跑步、跳躍、坐下、睡覺，可以抓起來甩出去，還能換裝。

## 需要什麼

- 一台 Mac
- **Xcode Command Line Tools**（提供 `swift` 編譯器）。若還沒裝：

```bash
xcode-select --install
```

確認裝好：

```bash
swift --version
```

## 編譯與執行

在專案資料夾裡：

```bash
swift run
```

第一次會先編譯再啟動；之後只要沒改程式，會直接跑。寵物出現後：

- **拖曳**：把牠抓起來；放手時甩一下，牠會被丟出去
- **雙擊**：跳一下
- **右鍵** 或 **選單列的 🐾 圖示**：
  - 動作 ▸ 發呆 / 走路 / 跑步 / 跳躍 / 坐下 / 睡覺 / 跳舞
  - 自動行動：打勾時牠會自己隨機換動作（偏安靜，常常跑去螢幕角落坐一兩分鐘；電腦桌、鞦韆、飛機有擺出來的話也會自己過去）；取消後會一直做你選的動作
  - 說句話：讓牠隨便說一句
  - 餵食：每天 2 次，餐桌擺上胡蘿蔔，她自己走過去坐下來吃，吃完拿到 XP（見下方「練等」）
  - 隱藏全部（**⌥F**，在任何 App 裡都能按）：寵物和家具一起藏起來，再按一次顯示回來；藏起來時她會暫停，重開 App 也會顯示回來
  - 開飛機：飛機有擺出來時，叫她現在去開（滑行、起飛、在天上繞二三十秒，再降落回停機位）
  - 家具與佈景：一次顯示 / 隱藏所有勾選的家具，也可以個別勾選餐桌、電腦桌、鞦韆、飛機。每件都可以左右拖曳，位置和勾選都會記住
  - 狀態 / 地下城…：看等級、經驗值、戰鬥力；派她去地下城冒險；看背包和戰報
  - 衣櫃…：分五個部位換裝（會記住，下次開啟還在）
    - 手上：氣球、棒棒糖
    - 頭：棒球帽、派對帽、花冠、耳機（＋地下城的草帽、魔法帽、王冠、蝴蝶結）
    - 臉：圓框眼鏡、墨鏡、飛行護目鏡、愛心眼鏡
    - 脖子：圍巾、領結、鈴鐺項圈（＋地下城的披風）
    - 背後：小書包、天使翅膀、VIP 星耀之翼（+20，會拍動、發光、飄閃光）
- **單擊**：牠會回你一句話；睡覺中點牠會被叫醒

> 這是常駐視窗程式，`swift run` 會一直佔用該終端機。要結束就用選單的「結束」，或在終端機按 `Ctrl + C`。

## 做成可以雙擊啟動的 App

```bash
./make-app.sh
```

會在專案資料夾產生 `SmallPet.app`，之後在 Finder 雙擊就能啟動，不需要開終端機。
可以拖到「應用程式」資料夾，或加到「系統設定 → 一般 → 登入項目」開機自動啟動。
改過程式或素材後，重新跑一次 `./make-app.sh` 即可更新。

## 其他常用指令

```bash
swift build            # 只編譯，不執行
swift build -c release # 編譯最佳化版本（跑起來更順）
swift run -c release   # 編譯並執行 release 版
```

編譯產物在 `.build/`（可安全刪除，會自動重建）。

## 用 Xcode 開發（可選）

想要有自動補全、除錯器、圖形介面，直接：

```bash
open Package.swift
```

Xcode 會把這個 Swift Package 當專案打開，按左上角 ▶︎ 就能跑。

## 檔案結構

| 檔案 | 作用 |
|------|------|
| `Package.swift` | 專案設定（Swift Package Manager） |
| `Sources/SmallPet/main.swift` | 進入點，建立 App |
| `Sources/SmallPet/AppDelegate.swift` | 組裝一切：選單、動畫計時器 |
| `Sources/SmallPet/Pet.swift` | 行為：動作狀態機、重力、跳躍、拖曳甩出（手感參數在 `Tuning`） |
| `Sources/SmallPet/PetAction.swift` | 所有動作的定義、自動模式的權重與持續時間 |
| `Sources/SmallPet/PetView.swift` | 用多層圖片疊出寵物 + 服裝、處理滑鼠 |
| `Sources/SmallPet/SpriteLibrary.swift` | 讀取 `Resources/` 的圖片與 `manifest.json` |
| `Sources/SmallPet/PetSpeech.swift` | 說話：讀台詞庫、頭上的對話泡泡 |
| `Sources/SmallPet/PetStats.swift` | 練等：等級、XP、每天餵食次數、存檔 |
| `Sources/SmallPet/Scenery.swift` | 家具佈景視窗（餐桌、電腦桌、鞦韆的繩子、飛機前後兩層）、⌥F 全域快捷鍵的註冊 |
| `Sources/SmallPet/Dungeon.swift` | 地下城清單、成功率、掉落物 |
| `Sources/SmallPet/StatusWindow.swift` | 狀態視窗（SwiftUI）：狀態 / 地下城 / 背包三頁 |
| `Sources/SmallPet/Wardrobe.swift` | 換裝狀態與衣櫃視窗（SwiftUI） |
| `Sources/SmallPet/PetWindow.swift` | 透明、無邊框、置頂的視窗 |
| `Tools/generate-sprites.swift` | 產生小貓的向量風格素材 |
| `Tools/generate-bunny.swift` | 產生兔耳女孩的 Q 版向量素材（目前使用中） |

## 換外觀 / 加衣服

所有圖片都在 `Sources/SmallPet/Resources/`：

```
Resources/
  manifest.json                    動作格數、播放速度、部位、服裝清單
  body/<動作>_<格>.png              本體，例如 walk_0.png ~ walk_5.png
  outfits/<服裝id>/<動作>_<格>.png   服裝疊圖
```

規則很簡單：

- **每張圖畫布一樣大**（目前 112×112 點，輸出 224×224 像素），角色腳底對齊同一個位置。
- **服裝是透明背景的疊圖**，跟本體同動作、同格數，疊上去剛好穿在身上。
  某個動作沒畫衣服的話，會改用該服裝的 idle 圖。
- 支援 `.png` 和 `.pdf`（向量，放大不糊）。從 Figma / Illustrator 匯出即可。
- `jump` 的 4 格有固定意義：0 蹲下、1 上升、2 下降、3 落地。

**新增一件衣服**：建 `outfits/<新id>/` 資料夾放圖，然後在 `manifest.json` 的 `outfits` 加一筆
`{"id": "新id", "name": "顯示名稱", "slot": "head"}`（slot 可用 `head`、`face`、`neck`）。

**換掉整隻寵物**：直接用自己的圖覆蓋 `body/` 底下的檔案即可。

**重新產生素材**（會覆蓋 `body/`、`outfits/` 和 `manifest.json`）：

```bash
swift Tools/generate-bunny.swift    # 兔耳女孩（目前使用中）
swift Tools/generate-sprites.swift  # 換回小貓
```

改完素材後重新 `swift run` 就會生效。

## 改台詞

台詞都在 `Sources/SmallPet/Resources/phrases.json`，依情境分類，每次從該類隨機挑一句：

| 情境 | 什麼時候說 |
|------|-----------|
| `greeting_morning` / `afternoon` / `evening` / `night` | 啟動時，依時段打招呼 |
| `click` | 被點一下、選單「說句話」 |
| `wake` | 睡覺時被點醒 |
| `dragged` / `thrown` / `landed` | 被抓起來 / 被甩出去 / 落地 |
| `idle` `walk` `run` `jump` `sit` `sleep` `dance` | 開始做該動作時（自動換動作時只有 30% 機率碎念，且至少間隔 8 秒） |
| `meal` / `eat` / `full` | 餵食時往餐桌走 / 坐下開吃 / 今天已經餵滿了 |
| `corner` / `typing` / `swing` | 跑去角落坐 / 開始打電腦 / 開始盪鞦韆 |
| `fly` / `landing` | 坐上飛機 / 準備降落 |
| `tired` / `lose` | 今天出門次數用完 / 冒險失敗回來 |
| `wardrobe` | 換完衣服 |

在陣列裡加減句子即可，改完重新執行就生效。碎念的機率在 `Pet.swift` 的 `chatterChance`，間隔在 `PetSpeech.swift` 的 `chatterCooldown`。

## 練等

- 每天可以餵 2 次（當地時間 0 點重置），每次 +20 XP。餵食時就算餐桌是隱藏的也會暫時出現，吃完再收起來。
- 升到下一級需要「50 × 目前等級」XP，升等時她會跳舞慶祝。
- 戰鬥力 = 等級 × 10 + 身上服裝的加成（衣櫃裡服裝名稱後面的 +N）。
- 數值都在 `PetStats.swift` 開頭（`feedsPerDay`、`xpPerFeed`、`xpToNext`）；服裝加成在 `generate-bunny.swift` 的 `outfitPower`。

### 地下城

在「狀態 / 地下城…」視窗的「地下城」頁按「出發」，她會跑出螢幕，時間到再跑回來報告結果。

| 地下城 | 建議戰力 | 時間 | 可能拿到 |
|---|---|---|---|
| 草原 | 15 | 10 分鐘 | 草帽、零食 |
| 森林 | 40 | 30 分鐘 | 魔法帽、披風、零食 |
| 城堡 | 80 | 60 分鐘 | 王冠、蝴蝶結、零食 |

- 每天最多出門 3 次。成功率：戰力等於建議值 70%、兩倍以上 95%、只有一半 20%。
- 失敗什麼都沒有；拿到已經有的服裝會改給零食。
- 零食在「背包」頁吃，跟餵食一樣 +20 XP，但不佔每天的餵食次數。
- 冒險中關掉 App 也沒關係，下次打開時間到了她就會回來。
- 戰利品服裝的戰鬥力：草帽 +5、魔法帽 +9、披風 +8、王冠 +14、蝴蝶結 +11（一般服裝 +1～+6，天使翅膀最高 +6）。拿到之後才會出現在衣櫃。
- 測試時不想等：用 `SMALLPET_FAST=1 swift run` 啟動，分鐘會變成秒。
- 地下城清單在 `Dungeon.swift`。
- 進度存在 `~/Library/Application Support/SmallPet/save.json`，想重來就刪掉這個檔案。

## 之後可以練習加什麼

- 餵食：右鍵放一顆食物，寵物走過去吃
- 追滑鼠：游標靠近時跑過去
- 換毛色：本體畫成灰階，程式上色
