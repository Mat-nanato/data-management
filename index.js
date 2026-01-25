import express from "express";
import puppeteer from "puppeteer";
import fetch from "node-fetch";

const app = express();
const PORT = process.env.PORT || 3000;

app.get("/latest-info", async (_, res) => {
  let browser;
  try {
    console.log("🚀 Puppeteer 開始");

    // Puppeteer 起動
    browser = await puppeteer.launch({
      headless: true,
      args: ["--no-sandbox", "--disable-setuid-sandbox"]
    });

    const page = await browser.newPage();
    console.log("📝 新しいページ作成完了");

    // ==== 新商品情報 ====
    console.log("📄 新商品ページへ移動中...");
    await page.goto("https://www.family.co.jp/goods/newgoods.html", { waitUntil: "networkidle2" });
    await new Promise(r => setTimeout(r, 3000)); // 3秒待機
    console.log("✅ 新商品ページロード完了");

    const newGoodsText = await page.evaluate(() => document.body.innerText);
    const lines = newGoodsText.split("\n").map(l => l.trim()).filter(l => !!l);

    const products = [];
    for (let i = 0; i < lines.length; i++) {
      const priceMatch = lines[i].match(/([0-9,]+)円/);
      if (priceMatch) {
        const price = priceMatch[1].replace(/,/g, "");
        const title = i > 0 ? lines[i - 1] : "";
        products.push({ name: title, price: `${price}円` });
      }
    }
    console.log(`🛍️ 新商品情報取得完了 (${products.length} 件)`);

    // ==== キャンペーン情報 ====
    console.log("📄 キャンペーンページへ移動中...");
    await page.goto("https://www.family.co.jp/campaign.html", { waitUntil: "networkidle2" });
    await new Promise(r => setTimeout(r, 3000));
    console.log("✅ キャンペーンページロード完了");

    const campaignText = await page.evaluate(() => document.body.innerText);
    const campaignLines = campaignText
      .split("\n")
      .map(l => l.trim())
      .filter(l => l.length > 10 && !/広告|閉じる/.test(l));
    const campaigns = campaignLines.map(c => ({ title: c, url: "" }));
    console.log(`🎯 キャンペーン情報取得完了 (${campaigns.length} 件)`);

    // ==== Render に送信 ====
    console.log("🚀 Render に送信中...");
    try {
      const response = await fetch("https://data-management-2.onrender.com/update-latest-info", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ products, campaigns })
      });
      const json = await response.json();
      console.log("✅ Render にキャッシュ送信完了", json);
    } catch (e) {
      console.error("⚠️ Render 送信失敗", e);
    }

    await browser.close();
    res.json({ products, campaigns });

  } catch (err) {
    if (browser) await browser.close();
    console.error("Puppeteer error:", err);
    res.status(500).json({ products: [], campaigns: [], error: "Failed to fetch data" });
  }
});

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});

