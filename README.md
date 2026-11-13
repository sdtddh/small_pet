# SmallPet 🐾

一隻用 **Swift + AppKit** 寫的 macOS 桌面寵物，主角是《明日方舟 Arknights》的 **阿米婭 Amiya**，也可以切換成《神椿市協奏中》的 **理芽**（都是 Q 版同人）。她會自己走路、跑步、跳躍、坐下、睡覺，可以抓起來甩出去，還能換裝。

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

- **拖曳**：把她抓起來；放手時甩一下，她會被丟出去
- **拖到家具上**：拖著她經過擺出來的家具時，家具會亮起一圈光；在那裡放手，她會直直落下（不會被甩出去），落地後直接用它——餐桌：吃飯（算一次餵食，今天餵滿了就吃不下）、電腦桌：打電腦、鞦韆：盪鞦韆、飛機：開飛機
- **雙擊**：跳一下
- **右鍵** 或 **選單列的 🐾 圖示**：
  - 動作 ▸ 發呆 / 走路 / 跑步 / 跳躍 / 坐下 / 睡覺 / 跳舞
  - 角色 ▸ 阿米婭 / 理芽：切換時 App 會自動重開一下。每個角色的等級、背包、地下城戰利品、身上的衣服和台詞都是分開的；家具共用
  - 自動行動：打勾時她會自己隨機換動作（偏安靜，常常跑去螢幕角落坐一兩分鐘；電腦桌、鞦韆、飛機有擺出來的話也會自己過去）；取消後會一直做你選的動作
  - 跟著我打字 / 點擊：打勾後，你在任何 App 裡打字或點滑鼠，她就跟著你的節奏跳舞——每按一次跳一步，你按越快她跳越快，點滑鼠時還會轉向游標那邊；停手 1.5 秒後回去做原本的事。她在電腦桌前打電腦時則不跳舞，手改成跟著你的打字節奏敲鍵盤
    - 只偵測「有按鍵 / 有點擊」，不會讀你打了什麼字；密碼欄位 macOS 本來就不會送出按鍵
    - 點擊不需要權限；鍵盤需要到「系統設定 → 隱私權與安全性 → 輔助使用」允許 SmallPet（第一次打勾會跳出詢問，選單裡也有捷徑）
    - 每次重新 `./make-app.sh` 後簽章會變，macOS 可能要你在「輔助使用」裡把 SmallPet 移除再重新加入一次
    - 睡覺、被抓、出門冒險、正在吃飯 / 盪鞦韆 / 開飛機時不會被打擾
  - 說句話：讓她隨便說一句
  - 餵食：每天 2 次，餐桌擺上胡蘿蔔，她自己走過去坐下來吃，吃完拿到 XP（見下方「練等」）
  - 隱藏全部（**⌥F**，在任何 App 裡都能按）：寵物和家具一起藏起來，再按一次顯示回來；藏起來時她會暫停，重開 App 也會顯示回來
  - 開飛機：飛機有擺出來時，叫她現在去開（滑行、起飛、在天上繞二三十秒，再降落回停機位）
  - 家具與佈景：一次顯示 / 隱藏所有勾選的家具，也可以個別勾選餐桌、電腦桌、鞦韆、飛機。每件都可以左右拖曳，位置和勾選都會記住
  - 狀態 / 地下城…：看等級、經驗值、戰鬥力；派她去地下城冒險；看背包和戰報
  - 衣櫃…：換髮型、衣服和配件（會記住，下次開啟還在；每個角色各自記）
    - **外觀**（純造型，不加戰鬥力，髮型和衣服可以任意搭配）
      - 髮型：角色原本的、地雷系雙馬尾、日系鯔魚頭・奶茶、日系鯔魚頭・黑銀挑染、日系公主切、日系短鮑伯
      - 衣服：角色原本的、地雷系、量產型、日系水手服、日系街頭帽T、日系浴衣
    - **配件**：分五個部位
    - 手上：棒棒糖（＋地下城的氣球）
    - 頭：棒球帽、派對帽、花冠、耳機（＋地下城的草帽、魔法帽、王冠、蝴蝶結）
    - 臉：圓框眼鏡、墨鏡、愛心眼鏡（＋地下城的飛行護目鏡）
    - 脖子：圍巾、領結（＋地下城的鈴鐺項圈、披風）
    - 背後：全部要從地下城拿：小書包、天使翅膀、VIP 星耀之翼（+20，會拍動、發光、飄閃光）
- **單擊**：她會回你一句話；睡覺中點她會被叫醒

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
| `Sources/SmallPet/Character.swift` | 角色清單、目前角色、切換（重開 App） |
| `Sources/SmallPet/SpriteLibrary.swift` | 讀取目前角色的圖片與 `manifest.json`，以及共用的道具圖 |
| `Sources/SmallPet/PetSpeech.swift` | 說話：讀台詞庫、頭上的對話泡泡 |
| `Sources/SmallPet/PetStats.swift` | 練等：等級、XP、每天餵食次數、存檔 |
| `Sources/SmallPet/Scenery.swift` | 家具佈景視窗（餐桌、電腦桌、鞦韆的繩子、飛機前後兩層）、⌥F 全域快捷鍵的註冊 |
| `Sources/SmallPet/Dungeon.swift` | 地下城清單、成功率、掉落物 |
| `Sources/SmallPet/StatusWindow.swift` | 狀態視窗（SwiftUI）：狀態 / 地下城 / 背包三頁 |
| `Sources/SmallPet/Wardrobe.swift` | 換裝狀態與衣櫃視窗（SwiftUI） |
| `Sources/SmallPet/InputSync.swift` | 「跟著我打字 / 點擊」：全域監聽鍵盤、滑鼠（只看有沒有按，不讀內容）與輔助使用權限 |
| `Sources/SmallPet/PetWindow.swift` | 透明、無邊框、置頂的視窗 |
| `Tools/generate-bunny.swift` | 產生角色的 Q 版向量素材（`amiya` / `rim`）與家具 |

## 換外觀 / 加衣服

所有圖片都在 `Sources/SmallPet/Resources/`，每個角色一個資料夾：

```
Resources/
  characters/<角色>/
    manifest.json                    角色名稱、動作格數、播放速度、部位、服裝清單、sprite sheet 的切法
    phrases.json                     這個角色的台詞
    body.png                         本體
    outfits/<服裝id>.png              服裝疊圖
    looks/hair/<髮型id>/behind.png    外觀：垂在身後的頭髮
    looks/hair/<髮型id>/head.png      外觀：頭（兔耳、臉、頭髮）
    looks/clothes/<衣服id>/base.png   外觀：腳、垂下的手、衣服
    looks/clothes/<衣服id>/top.png    外觀：舉高的手、胡蘿蔔、睡覺的 z
  props/                             家具、飛機、降落傘（所有角色共用）
```

每一層是一張 **sprite sheet**：這一層所有動作的所有格排在同一張圖上，依 manifest 的 `actions` 順序
由左到右、由上到下，每列 8 格、每格 224×224 像素。`manifest.json` 的 `sheet` 記下每個動作從第幾格開始：

```json
"sheet": { "columns": 8, "cell": 224, "start": { "idle": 0, "walk": 4, "run": 10, … } }
```

例如 `walk` 的第 2 格是第 4 + 2 = 6 格：第 0 列、第 6 欄。

有 `looks/` 的話，App 用這四層（由下往上）疊出她本人，`body.png` 就不會用到；沒有的話（例如小貓素材）照舊用 `body`。
manifest 沒有 `sheet` 的舊素材，還是讀一格一張的 `body/<動作>_<格>.png`（支援 `.png` 和 `.pdf`）。

規則很簡單：

- **每一格畫布一樣大**（目前 112×112 點，輸出 224×224 像素），角色腳底對齊同一個位置。
- **服裝是透明背景的疊圖**，跟本體同動作、同格數，疊上去剛好穿在身上。
  某個動作沒畫衣服的話，會改用該服裝的 idle 圖。
- 素材由 `swift Tools/generate-bunny.swift [amiya|rim]` 產生，它會自動拼好 sprite sheet。
- `jump` 的 4 格有固定意義：0 蹲下、1 上升、2 下降、3 落地。

**新增一件衣服**：建 `outfits/<新id>/` 資料夾放圖，然後在 `manifest.json` 的 `outfits` 加一筆
`{"id": "新id", "name": "顯示名稱", "slot": "head"}`（slot 可用 `head`、`face`、`neck`）。

**新增一種髮型 / 衣服**：在 `Tools/generate-bunny.swift` 的「外觀」段落照著現有的寫一個 `HairStyle` 或 `ClothesStyle`，
加進 `hairStyles` / `clothesStyles` 清單，再重新產生素材。髮型只畫頭和頭髮、衣服只畫身體，所以任何組合都對得上。

**換掉整隻寵物**：直接用自己的圖覆蓋 `characters/<角色>/body/` 底下的檔案即可。

**新增角色**：在 `generate-bunny.swift` 的 `characterNames` 和 `Character.swift` 的 `Character.all` 各加一筆，畫出她的特徵（參考 `rim` 的寫法），再放一份 `phrases.json`。

**重新產生素材**（會覆蓋該角色的 `body/`、`outfits/`、`manifest.json`，以及共用的 `props/`；不會動到台詞）：

```bash
swift Tools/generate-bunny.swift        # 阿米婭
swift Tools/generate-bunny.swift rim    # 理芽
```

（`Tools/generate-sprites.swift` 是最早的小貓版，已經不支援角色資料夾，只留著參考。）

改完素材後重新 `swift run` 就會生效。

## 改台詞

台詞在 `Sources/SmallPet/Resources/characters/<角色>/phrases.json`，每個角色各一份，依情境分類，每次從該類隨機挑一句：

| 情境 | 什麼時候說 |
|------|-----------|
| `greeting_morning` / `afternoon` / `evening` / `night` | 啟動時，依時段打招呼 |
| `click` | 被點一下、選單「說句話」 |
| `wake` | 睡覺時被點醒 |
| `dragged` / `thrown` / `landed` | 被抓起來 / 被甩出去 / 落地 |
| `idle` `walk` `run` `jump` `sit` `sleep` `dance` | 開始做該動作時（自動換動作時只有 30% 機率碎念，且至少間隔 8 秒） |
| `meal` / `eat` / `full` | 餵食時往餐桌走 / 坐下開吃 / 今天已經餵滿了 |
| `corner` / `typing` / `swing` | 跑去角落坐 / 開始打電腦 / 開始盪鞦韆 |
| `syncdance` | 開始跟著你的節奏跳舞（25% 機率） |
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
| 草原 | 15 | 10 分鐘 | 草帽、氣球、鈴鐺項圈、零食 |
| 森林 | 40 | 30 分鐘 | 魔法帽、披風、飛行護目鏡、小書包、零食 |
| 城堡 | 80 | 60 分鐘 | 王冠、蝴蝶結、天使翅膀、零食 |
| 星空神殿 | 150 | 120 分鐘 | VIP 星耀之翼（成功時 1/4 機會）、零食 |

- 每天最多出門 3 次。成功率：戰力等於建議值 70%、兩倍以上 95%、只有一半 20%。
- 失敗什麼都沒有；拿到已經有的服裝會改給零食。
- 零食在「背包」頁吃，跟餵食一樣 +20 XP，但不佔每天的餵食次數。
- 冒險中關掉 App 也沒關係，下次打開時間到了她就會回來。
- 戰利品服裝的戰鬥力：草帽 +5、氣球 +1、鈴鐺項圈 +2、魔法帽 +9、披風 +8、護目鏡 +4、小書包 +3、王冠 +14、蝴蝶結 +11、天使翅膀 +6、VIP 星耀之翼 +20。拿到之後才會出現在衣櫃。
- 測試時不想等：用 `SMALLPET_FAST=1 swift run` 啟動，分鐘會變成秒。
- 地下城清單在 `Dungeon.swift`。
- 進度存在 `~/Library/Application Support/SmallPet/save.json`（理芽是 `save-rim.json`），想重來就刪掉對應的檔案。

## 之後可以練習加什麼

- 餵食：右鍵放一顆食物，寵物走過去吃
- 追滑鼠：游標靠近時跑過去
- 換毛色：本體畫成灰階，程式上色

## 聲明

阿米婭（Amiya）及《明日方舟》相關角色版權屬於 Hypergryph / Yostar；理芽及《神椿市協奏中》相關角色版權屬於 KAMITSUBAKI STUDIO / KTB。本專案為非商業的粉絲同人作品，所有素材皆由程式自行繪製，不包含官方圖片。
