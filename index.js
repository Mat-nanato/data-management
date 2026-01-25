import express from "express";
import fetch from "node-fetch";
import * as cheerio from "cheerio";
import OpenAI from "openai";
import fs from "fs"; 

const app = express();
const PORT = process.env.PORT || 3000;

// =======================
// OpenAI 設定
// =======================
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
});

// =======================
// 簡易ヘルスチェック
// =======================
app.get("/health", (_, res) => {
  res.json({ status: "ok" });
});

// =======================
// HTML 取得確認用
// =======================
app.get("/fetch", async (_, res) => {
  try {
    const r = await fetch("https://www.family.co.jp/");
    const html = await r.text();
fs.writeFileSync("fm.html", html); // ← HTML を保存

    res.json({
      length: html.length
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// =======================
// 最新情報取得用
// =======================
app.get("/latest-info", async (req, res) => {
  try {
    // 公式HP取得
    const r = await fetch("https://www.family.co.jp/goods/newgoods.html");
    const html = await r.text();

    // HTML パース
fs.writeFileSync("fm.html", html); // ← HTML 保存
    const $ = cheerio.load(html);
    const products = [];
    $(".ly-mod-infoset").each((_, el) => {
      const name = $(el).find(".ly-mod-infoset-name").text().trim();
      const price = $(el).find(".ly-mod-infoset-price").text().trim();
      const region = $(el).find(".ly-mod-infoset-area").text().trim() || "全国";
      if (name) products.push({ name, price, region });
    });

    // OpenAI 要約
    const messages = [
      { role: "system", content: "以下は公式HPから取得した事実データです。推測や補完は禁止。" },
      { role: "user", content: JSON.stringify(products, null, 2) },
      { role: "user", content: "上記データを箇条書きでまとめてください。" }
    ];

    const responseAI = await openai.chat.completions.create({
      model: "gpt-4.1-mini",
      messages,
      temperature: 0
    });

    const summary = responseAI.choices[0].message.content;
    res.json({ latestInfo: summary });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// =======================
// サーバー起動
// =======================
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

