# 釉料配方计算器 — Supabase 版

单文件 HTML 计算器，数据存 Supabase（Postgres + Auth + Storage），支持多人各自独立账号、跨设备同步。

## 1. 创建 Supabase 项目

1. 去 [supabase.com](https://supabase.com) 新建一个项目，记下 **Project URL** 和 **anon public key**（Settings → API）。
   - anon key 可以放心写进前端代码里，安全性由 RLS（行级安全策略）保证，不是靠密钥保密。
   - 绝对不要把 `service_role` key 放到浏览器里。

2. **Authentication → Providers → Email**：保持开启，但关掉 **"Allow new users to sign up"**（改成邀请制，不开放注册）。

3. **Authentication → URL Configuration**：把部署后的静态站点 URL（比如 `https://xxx.github.io/xxx/`）加进 **Redirect URLs**，否则 magic link 邮件里的链接跳转会失败。

4. **Authentication → Users**：手动点 "Add user"，加自己和其他要用这个工具的人的邮箱。

## 2. 建表 + RLS 策略

打开 Supabase 项目的 **SQL Editor**，把同目录下 [`schema.sql`](./schema.sql) 的全部内容粘进去，执行一次。

这会创建：
- `notebook_entries` / `favourites` / `history_entries` 三张表，都带 RLS（每个人只能读写自己的行）
- `history_entries` 的 after-insert 触发器：每个用户只保留最近 50 条历史记录
- 私有 Storage bucket `glaze-photos`，按 `{user_id}/...` 分文件夹隔离，RLS 保证互相看不到对方的图

## 3. 配置前端

打开 `notebook_v6_3.html`，找到文件开头 `<script>` 里的这两行：

```js
const SUPABASE_URL = 'YOUR_SUPABASE_URL';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```

换成你自己项目的值（Settings → API 页面能找到）。

## 4. 部署

这是纯静态单文件，不需要服务器。任选一种：

- **GitHub Pages**：把 `notebook_v6_3.html` 放进一个仓库，Settings → Pages 里指向对应分支/目录
- **Vercel / Netlify**：直接把这个文件夹拖进去部署，或者连 Git 仓库自动部署

部署完拿到最终 URL 之后，记得回到 Supabase 的 **Authentication → URL Configuration** 把这个 URL 加进 Redirect URLs（如果第 1 步用的是临时占位 URL）。

## 5. 登录

打开部署后的页面，输入邮箱（必须是第 1 步在 Supabase Users 里手动加过的邮箱），点"发送登录链接"，去邮箱点链接即可登录。每个账号的数据完全独立。

## 6. 迁移旧数据（可选，一次性）

如果你之前用的是纯本地版本（localStorage/IndexedDB），已经积累了配方本数据（比如 `釉料配方本_2026-06-21.json`）：

1. 用自己的账号登录新版页面
2. 切到"配方本"标签页，点"↑ 导入 JSON"，选那个旧的导出文件
3. 会按记录里的旧 id 自动去重、逐条写入数据库，图片会重新上传到 Storage（分批上传，避免一次性并发太多请求）
4. 完成后会弹窗提示导入了多少条、多少张图片

原始 JSON 文件不会被修改或删除，保留作为备份即可。

收藏夹同理，用"收藏夹"标签页里的导入功能导入旧的收藏导出文件。

历史记录（History）不做迁移——本来就是自动生成、会持续积累的临时记录，不需要手动搬。
