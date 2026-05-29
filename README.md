# maxxtang-loc

統計 [@MAXXTANG](https://github.com/MAXXTANG/) 在 GitHub 上累積寫了多少行程式碼 — 以「快照」方式，月度更新並保留歷史。

**線上查看：** https://maxxtang.github.io/maxxtang-loc/

## 怎麼運作

```
每月 1 號 / 手動觸發
       │
       ▼
GitHub Action (snapshot.yml)
       │
       ├─ scripts/count.sh
       │    ├─ GitHub API 列出所有非 fork repo
       │    ├─ 對每個 repo: git clone --depth=1
       │    ├─ tokei --output json 計算
       │    └─ 加總 → 寫入 data/history.json
       │
       └─ git commit + push
              │
              ▼
   docs/index.html (Chart.js)
   讀 history.json 畫歷史曲線
```

## 為什麼是月度快照而不是即時

- 99% 時間統計不會變，即時系統會白燒額度
- 真正想看的是「成長曲線」，月度粒度剛好
- 重大里程碑想看？手動 workflow_dispatch 一鍵更新

## 檔案結構

```
maxxtang-loc/
├── .github/workflows/snapshot.yml   # 每月 cron + 手動觸發
├── scripts/count.sh                  # 統計核心
├── data/history.json                 # 累積歷史（追蹤的）
├── docs/index.html                   # GitHub Pages 前端
└── README.md
```

## 本地測試

```bash
# 需要 GitHub CLI + tokei + jq
brew install gh tokei jq
gh auth login

# 跑一次，結果寫到 data/history.json
GH_USER=MAXXTANG ./scripts/count.sh
```

## 公開服務模式（Phase 2，未實作）

未來會用 Cloudflare Worker + GitHub `/languages` API 提供「任意 username 即時近似查詢」。
精確查詢請 fork 本 repo，將你的 username 加入 `users.yml`。

## 路線圖

- [x] Phase 1: 個人模式（MAXXTANG）
- [ ] Phase 2: 公開查詢（Cloudflare Worker）
- [ ] Phase 3: 里程碑通知（Telegram，達 100k / 500k / 1M 推播）
- [ ] Phase 4: 增加更多 metric（commit 頻率、PR 數、active days）

## 授權

MIT
