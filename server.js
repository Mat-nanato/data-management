import express from "express";
import puppeteer from "puppeteer";
import fetch from "node-fetch";

const app = express();
const PORT = process.env.PORT || 3000;

app.get("/latest-info", async (_, res) => {
  let browser;

  try {
    browser = await puppeteer.launch({
      headless: false,
      args: ["--no-sandbox", "--disable-setuid-sandbox"]
    });

    const page = await browser.newPage();

    // ==== 新商品情報 ====
    await page.goto("https://www.family.co.jp/goods/newgoods.html", {
      waitUntil: "networkidle2"
    });
    await new Promise(r => setTimeout(r, 2000));

    const newGoodsText = await page.evaluate(() => document.body.innerText);
    const lines = newGoodsText
      .split("\n")
      .map(l => l.trim())
      .filter(l => !!l);

    const products = [];
    for (let i = 0; i < lines.length; i++) {
      const priceMatch = lines[i].match(/([0-9,]+)円/);
      if (priceMatch) {
        const price = priceMatch[1].replace(/,/g, "");
        const title = i > 0 ? lines[i - 1] : "";
        products.push({ name: title, price: `${price}円` });
      }
    }

    // ==== キャンペーン情報 ====
    await page.goto("https://www.family.co.jp/campaign.html", {
      waitUntil: "networkidle2"
    });
    await new Promise(r => setTimeout(r, 2000));

    const campaignText = await page.evaluate(() => document.body.innerText);
    const campaignLines = campaignText
      .split("\n")
      .map(l => l.trim())
      .filter(l => l.length > 10 && !/広告|閉じる/.test(l));

    const campaigns = campaignLines.map(c => ({ title: c, url: "" }));

    await browser.close();

    // ===== ここから追加 =====
    const logMessage = "✅ Render にキャッシュ送信完了";
    console.log(logMessage);

    await fetch("https://data-management-2.onrender.com/save-log", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        message: logMessage,
        source: "local-node",
        createdAt: new Date().toISOString()
      })
    });
    // ===== ここまで追加 =====

    res.json({ products, campaigns });

  } catch (err) {
    if (browser) await browser.close();
    console.error("Puppeteer error:", err);

    res.status(500).json({
      products: [],
      campaigns: [],
      error: "Failed to fetch"
    });
  }
});

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});

