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
- **拖到家具上**：拖著她經過擺出來的家具時，家具會亮起一圈光；在那裡放手，她會直直落下（不會被甩出去），落地後直接用它——餐桌：吃飯（算一次餵食，今天餵滿了就吃不下）、電腦桌：打電腦、床：躺進被窩睡覺（點她會醒過來）、飛機：開飛機
- **雙擊**：跳一下
- **右鍵** 或 **選單列的 🐾 圖示**：
  - 狀態 / 地下城…：狀態、地下城、背包、權限四頁
    - 「狀態」頁的「跟著我打字 / 點擊」開關：打開後，你在任何 App 裡打字或點滑鼠，她就跟著你的節奏跳舞——每按一次跳一步，你按越快她跳越快，點滑鼠時還會轉向游標那邊；停手 1.5 秒後回去做原本的事。她在電腦桌前打電腦時則不跳舞，手改成跟著你的打字節奏敲鍵盤
        - 只偵測「有按鍵 / 有點擊」，不會讀你打了什麼字；密碼欄位 macOS 本來就不會送出按鍵
        - 點擊不需要權限；鍵盤需要到「系統設定 → 隱私權與安全性 → 輔助使用」允許 SmallPet（第一次打開會跳出詢問；「權限」頁會顯示現在有沒有允許，也有「前往設定」按鈕）
        - 每次重新 `./make-app.sh` 後簽章會變，macOS 可能要你在「輔助使用」裡把 SmallPet 移除再重新加入一次
        - 睡覺、被抓、出門冒險、正在吃飯 / 睡床 / 開飛機時不會被打擾
    - 「地下城」頁：出門冒險，或按「試打」打 15 秒看看 boss（不算次數、不給戰利品）；每張卡片列出會掉的服裝（還沒拿到的顯示 ???），並顯示還差幾件
    - 「權限」頁：哪些功能需要 macOS 權限（目前只有鍵盤要「輔助使用」）、現在有沒有允許、前往設定的按鈕
  - 衣櫃…：換髮型、衣服和配件
  - 動作 ▸ 說句話 / 自動行動 / 發呆 / 走路 / 跑步 / 跳躍 / 坐下 / 睡覺 / 跳舞
    - 說句話：讓她隨便說一句，不會打斷正在做的動作，也不影響自動行動
    - 自動行動：打勾時她會自己隨機換動作（偏安靜，常常跑去螢幕角落坐一兩分鐘；電腦桌、床、飛機有擺出來的話也會自己過去）
    - 其他動作：選了就取消自動行動，她會一直做那個動作，選單上的「動作」會變成「行動（鎖定為：跳舞）」這樣；跳躍例外，只跳一次、跳完回到原本的狀態
  - 角色 ▸ 阿米婭 / 理芽：切換時 App 會自動重開一下。每個角色的等級、背包、地下城戰利品、身上的衣服和台詞都是分開的；家具共用
  - 家具與佈景：一次顯示 / 隱藏所有勾選的家具，也可以個別勾選餐桌、電腦桌、床、飛機。位置和勾選都會記住
  - 隱藏全部（**⌥F**，在任何 App 裡都能按；在「結束」上面）：寵物和家具一起藏起來，再按一次顯示回來；藏起來時她會暫停，重開 App 也會顯示回來
- **按住家具拖**：左右拖是移動；往下拉放手會收起來（等於在選單取消勾選，她正在用的家具拉不下去）；往上拉放手會打開那件家具的小工具
  - 電腦桌：**計算機**。可以直接打算式按 Enter，或按畫面上的鍵。支援 + − × ÷、括號、`^` 次方、`%`、`log`（以 10 為底）、`ln`、`√`、`π`、`e`，
    乘號可以省略（`2π`、`3(4+1)`），函數不加括號也行（`log 100`、`√9`）。打字時下面即時顯示答案，按 = 後記進「紀錄」，點紀錄可以把結果放回算式
  - 餐桌：**吃飯**（餵食）。每天 2 次，盤子放上胡蘿蔔，她自己走過來坐下吃，吃完拿到 XP（見下方「練等」）；今天餵滿了她會說吃不下。「狀態」視窗也有餵食按鈕
  - 床、飛機還沒有小工具，往上拉只會彈一下
  - 狀態 / 地下城…：看等級、經驗值、戰鬥力；派她去地下城冒險；看背包和戰報
  - 衣櫃…：換髮型、衣服和配件（會記住，下次開啟還在；每個角色各自記）
    - **外觀**（純造型，不加戰鬥力，髮型和衣服可以任意搭配）
      - 髮型：角色原本的、地雷系雙馬尾、日系鯔魚頭・奶茶、日系鯔魚頭・黑銀挑染、日系公主切、日系短鮑伯
      - 衣服：角色原本的、地雷系、量產型、日系水手服、日系街頭帽T、日系浴衣
    - **配件**：分五個部位
    - 作戰武器：一開始只有樹枝（+0），其他要從地下城拿：棒棒糖、氣球（草原）、哥德雨傘（森林）、劍（城堡，+5）。一定要拿一樣，只有在地下城打 boss 時才會拿出來揮
    - 頭：棒球帽、派對帽、花冠、耳機、趴在頭上的 Mokke（＋地下城的草帽、魔法帽、王冠、蝴蝶結）
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
| `Sources/SmallPet/Scenery.swift` | 家具佈景視窗（餐桌、電腦桌、床和蓋在她身上的棉被、飛機前後兩層）、拖動手勢（移動 / 往下收起 / 往上開小工具）、⌥F 全域快捷鍵的註冊 |
| `Sources/SmallPet/CalculatorWindow.swift` | 電腦桌的小工具：計算機視窗（SwiftUI） |
| `Sources/SmallPet/MathExpression.swift` | 計算機的算式解析（不依賴 AppKit，可以單獨測試） |
| `Sources/SmallPet/Dungeon.swift` | 地下城清單、成功率、掉落物 |
| `Sources/SmallPet/StatusWindow.swift` | 狀態視窗（SwiftUI）：狀態 / 地下城 / 背包 / 權限四頁 |
| `Sources/SmallPet/Wardrobe.swift` | 換裝狀態與衣櫃視窗（SwiftUI） |
| `Sources/SmallPet/BossWindow.swift` | 地下城冒險時出現的 boss：圖、血條、被砍中的反應、傷害數字、打倒 / 打輸的動畫 |
| `Sources/SmallPet/InputSync.swift` | 「跟著我打字 / 點擊」：全域監聽鍵盤、滑鼠（只看有沒有按，不讀內容）與輔助使用權限 |
| `Sources/SmallPet/PetWindow.swift` | 透明、無邊框、置頂的視窗 |
| `Tools/generate-bunny.swift` | 產生角色的 Q 版向量素材（`amiya` / `rim`）與家具 |

## 換外觀 / 加衣服

所有圖片都在 `Sources/SmallPet/Resources/`。角色只剩「臉」和「預設穿什麼」，其他東西（髮型、衣服、服裝、兔耳之類的角色特徵）都放在 `shared/`，任何角色都能穿：

```
Resources/
  characters/<角色>/
    character.json                   名字、選單順序、臉（眼睛 / 嘴巴的畫法和顏色）、預設穿什麼
    phrases.json                     這個角色的台詞
    manifest.json                    動作格數、播放速度、sprite sheet 的切法（產生器輸出）
    face.png                         角色的臉（皮膚）
    features.png                     角色的五官：臉頰、眼睛、嘴巴
    outfits/vip_wings.png            跟角色輪廓有關的服裝
  shared/                            所有角色共用一份（App 在角色資料夾找不到某一層時來這裡找）
    items.json                       部位、服裝、角色特徵物件、髮型、衣服的清單
    anchors.json                     每一格的錨點矩陣（頭、上半身、手）
    outfits/<服裝id>/{front,back}.png 只畫一張的服裝（帽子、眼鏡…），跟著錨點動
    outfits/<服裝id>.png              逐格畫的服裝（作戰武器、翅膀）
    looks/hair/<髮型id>/behind.png    外觀：垂在身後的頭髮
    looks/hair/<髮型id>/back.png      外觀：臉後面的頭髮（背對時是整顆後腦勺）
    looks/hair/<髮型id>/front.png     外觀：臉前面的頭髮（兩側髮束、瀏海）
    looks/clothes/<衣服id>/base.png   外觀：腳、垂下的手、衣服
    looks/clothes/<衣服id>/top.png    外觀：舉高的手、胡蘿蔔、睡覺的 z
    items/<物件id>/<髮型id>.png       角色特徵物件（兔耳、兔尾巴用髮色畫，每種髮型一張）
    items/<物件id>.png                不跟髮色的物件（菱形耳環）
  props/                             家具、飛機、降落傘（所有角色共用）
```

每一層是一張 **sprite sheet**：這一層所有動作的所有格排在同一張圖上，依 manifest 的 `actions` 順序
由左到右、由上到下，每列 8 格、每格 224×224 像素。`manifest.json` 的 `sheet` 記下每個動作從第幾格開始：

```json
"sheet": { "columns": 8, "cell": 224, "start": { "idle": 0, "walk": 4, "run": 10, … } }
```

例如 `walk` 的第 2 格是第 4 + 2 = 6 格：第 0 列、第 6 欄。

App 用這十層（由下往上）疊出她本人：身後的頭髮、衣服、尾巴、耳朵、後腦頭髮、臉、前面的頭髮、耳環、五官、舉高的手。
耳朵、尾巴、耳飾是可以穿脫的物件（`items.json` 的 `bodySlots`）。原本屬於某個角色的物件、髮型、衣服都標了 `origin`，
衣櫃顯示成「兔耳（阿米婭）」「辮子短髮（理芽）」，任何角色都能穿。

角色原本的樣子寫在 `character.json` 的 `defaults`：第一次開啟、或從舊版升級時自動穿上。
衣櫃存檔有版本（`wardrobeVersion.<角色>`），舊存檔會一版一版轉換（見 `Wardrobe.migrate`）。

舊素材（例如小貓）沒有 `items.json` 和外觀圖層時，清單照舊從 `manifest.json` 讀、本體用一張 `body.png`；
manifest 沒有 `sheet` 的，讀一格一張的 `body/<動作>_<格>.png`（支援 `.png` 和 `.pdf`）。

規則很簡單：

- **每一格畫布一樣大**（目前 112×112 點，輸出 224×224 像素），角色腳底對齊同一個位置。
- **服裝是透明背景的疊圖**，跟本體同動作、同格數，疊上去剛好穿在身上。
  某個動作沒畫衣服的話，會改用該服裝的 idle 圖。
- 素材由 `swift Tools/generate-bunny.swift <角色>` 產生，它會自動拼好 sprite sheet。
- `jump` 的 4 格有固定意義：0 蹲下、1 上升、2 下降、3 落地。

**錨點服裝**：帽子、眼鏡、圍巾這類形狀不變的服裝只畫一張圖（`outfits/<id>/front.png`，背對時看得到的話再一張 `back.png`），
用的是「靜止姿勢」。`shared/anchors.json` 記下每個動作每一格的 2D 矩陣（`[a, b, c, d, tx, ty]`，單位是畫布的點，原點在左下角），
App 把那一格的矩陣套到圖層上，服裝就會跟著頭（`head`）、上半身（`upper`）或手（`hand`，拿胡蘿蔔時收起來）移動、傾斜、壓扁。
作戰武器（劍、棒棒糖、雨傘、氣球）、翅膀的形狀每格都不一樣，還是逐格畫（`outfits/<id>.png`）。

**新增一件衣服（手畫，不用寫程式）**：開一張 224×224 的透明畫布（2 倍解析度，對應 112×112 點的畫布），
照著靜止姿勢的位置畫（可以把 `idle` 第 0 格的本體疊在底下當參考，那一格就是靜止姿勢），存成 `shared/outfits/<新id>/front.png`，
然後在 `shared/items.json` 的 `outfits` 加一筆：

```json
{ "id": "beret", "name": "貝雷帽", "slot": "head", "power": 3, "anchor": "head" }
```

slot 可用 `head`、`face`、`neck`、`back`、`hand`，anchor 可用 `head`、`upper`、`hand`。所有角色、所有動作都能穿。
重新產生素材會覆蓋 `items.json`，所以要長久保留的話，在 `generate-bunny.swift` 的 `outfits` 加一件（並寫進 `outfitAnchors`）。

**新增一種髮型 / 衣服**：在 `Tools/generate-bunny.swift` 的「外觀」段落照著現有的寫一個 `HairStyle` 或 `ClothesStyle`，
加進 `hairStyles` / `clothesStyles` 清單，再重新產生素材。髮型只畫頭和頭髮、衣服只畫身體，所以任何組合都對得上。

**新增角色**：建 `characters/<id>/`，放一份 `phrases.json` 和 `character.json`：

```json
{
  "id": "mika",
  "name": "米卡",
  "order": 2,
  "face": { "eyes": "round", "eyeDark": "#3B2A12", "eyeIris": "#E07A2E", "mouth": "smile" },
  "defaults": { "hair": "short_bob", "clothes": "sailor", "ears": "bunny_ears", "tail": null, "earrings": "diamond_earrings" }
}
```

`eyes` 可用 `round`、`rim`，`mouth` 可用 `omega`、`smile`（要新的畫法就在產生器的 `drawEye` / `drawHead` 加一個選項）。
然後執行 `swift Tools/generate-bunny.swift mika`，只會多產生她的臉；App 會自動掃到 `character.json`，選單上就有她。

**重新產生素材**（會覆蓋該角色的 `face`、`features`、`outfits/`、`manifest.json`，以及共用的 `shared/`、`props/`；不會動到 `character.json` 和台詞）：

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
| `corner` / `typing` / `bed` | 跑去角落坐 / 開始打電腦 / 上床睡覺 |
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

在「狀態 / 地下城…」視窗的「地下城」頁按「出發」，那個地下城的 boss 會出現在她旁邊，她拿著衣櫃「作戰武器」選的東西（樹枝、劍、棒棒糖、雨傘…）一直砍到冒險時間結束：
每砍中一刀 boss 會閃一下、飄出傷害數字（大約等於戰鬥力），頭上的血條跟著時間往下掉。時間到分出勝負——贏了 boss 縮小消失、她跳舞報告戰利品；輸了 boss 得意地晃一晃離開、她坐下來沮喪一下。**點 boss** 可以讓她馬上多砍一刀，而且冒險時間少 1 秒（每點一下都算）。戰鬥中不能抓她、餵她，⌥F 會把 boss 一起藏起來。

| 地下城 | Boss | 建議戰力 | 時間 | 可能拿到 |
|---|---|---|---|---|
| 草原 | 草原史萊姆王 | 15 | 10 分鐘 | 草帽、氣球、鈴鐺項圈、棒棒糖、零食 |
| 森林 | 古樹樹精 | 40 | 30 分鐘 | 魔法帽、披風、飛行護目鏡、小書包、哥德雨傘、零食 |
| 城堡 | 黑暗騎士 | 80 | 60 分鐘 | 王冠、蝴蝶結、天使翅膀、劍、零食 |
| 星空神殿 | 星空神龍 | 150 | 120 分鐘 | VIP 星耀之翼（成功時 1/4 機會）、零食 |

- 每天最多出門 3 次。成功率：戰力等於建議值 70%、兩倍以上 95%、只有一半 20%。
- 失敗什麼都沒有；拿到已經有的服裝會改給零食。
- 零食在「背包」頁吃，跟餵食一樣 +20 XP，但不佔每天的餵食次數。
- 冒險中關掉 App 也沒關係，下次打開她會接著打，時間到了就分出勝負。
- 想先看看 boss：「狀態 / 地下城…」視窗「地下城」頁每個地下城的「試打」，打 15 秒就分勝負，不消耗次數、不給戰利品、不存檔。
- 戰利品服裝的戰鬥力：草帽 +5、氣球 +1、鈴鐺項圈 +2、魔法帽 +9、披風 +8、護目鏡 +4、小書包 +3、王冠 +14、蝴蝶結 +11、天使翅膀 +6、VIP 星耀之翼 +20。拿到之後才會出現在衣櫃。
- 測試時不想等：用 `SMALLPET_FAST=1 swift run` 啟動，分鐘會變成秒。
- 地下城清單在 `Dungeon.swift`；boss 的圖（像素風格，`renderPixelPNG`）在 `generate-bunny.swift` 的「地下城 boss」段落，畫面（血條、傷害數字）在 `BossWindow.swift`。
- 進度存在 `~/Library/Application Support/SmallPet/save.json`（理芽是 `save-rim.json`），想重來就刪掉對應的檔案。

## 之後可以練習加什麼

- 餵食：右鍵放一顆食物，寵物走過去吃
- 追滑鼠：游標靠近時跑過去
- 換毛色：本體畫成灰階，程式上色

## 聲明

阿米婭（Amiya）及《明日方舟》相關角色版權屬於 Hypergryph / Yostar；理芽及《神椿市協奏中》相關角色版權屬於 KAMITSUBAKI STUDIO / KTB。本專案為非商業的粉絲同人作品，所有素材皆由程式自行繪製，不包含官方圖片。
