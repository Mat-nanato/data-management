// index.js（Render 側）
import express from "express";
import fs from "fs";

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// ==============================
// Swift → Render : テキスト保存
// ==============================
app.post("/save-text", (req, res) => {
  const text = req.body.text;

  if (!text) {
    return res.status(400).json({ error: "no text" });
  }

  try {
    fs.writeFileSync("latest-info.txt", text, "utf8");
    console.log("✅ Swift からテキスト保存完了");
    res.json({ ok: true });
  } catch (err) {
    console.error("❌ 保存失敗:", err);
    res.status(500).json({ error: "failed to save" });
  }
});

// ==============================
// Render → Swift : 保存テキスト取得
// ==============================
app.get("/latest-text", (req, res) => {
  try {
    if (!fs.existsSync("latest-info.txt")) {
      return res.json({ text: "" });
    }

    const text = fs.readFileSync("latest-info.txt", "utf8");
    res.json({ text });
  } catch (err) {
    console.error("❌ 読み込み失敗:", err);
    res.status(500).json({ error: "failed to read" });
  }
});

// ==============================
// サーバー起動
// ==============================
app.listen(PORT, () => {
  console.log(`🚀 Render server running on port ${PORT}`);
});

